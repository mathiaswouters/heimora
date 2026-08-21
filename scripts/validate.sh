#!/usr/bin/env bash
# Check that a machine matches what ansible/site.yml is supposed to leave behind.
#
# Reads package lists and paths from ansible/group_vars/all.yml so this stays
# in sync with the playbook. NVIDIA / gaming checks are skipped when lspci
# sees no NVIDIA adapter (same rule as the nvidia role).
#
# Usage:
#   ./scripts/validate.sh
#   /opt/heimora/scripts/validate.sh
#
# Exit 1 if anything failed. Warnings (manual steps, reboot needed) do not
# fail the script.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
VARS_FILE="$REPO_ROOT/ansible/group_vars/all.yml"

PASS=0
WARN=0
FAIL=0

if [[ -t 1 ]]; then
    RESET='\033[0m'; BOLD='\033[1m'
    GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'
else
    RESET=''; BOLD=''
    GREEN=''; YELLOW=''; RED=''; CYAN=''
fi

ok()   { echo -e "${GREEN}[OK]${RESET}   $1"; PASS=$((PASS + 1)); }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; WARN=$((WARN + 1)); }
fail() { echo -e "${RED}[FAIL]${RESET} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo -e "${CYAN}${BOLD}=== $1 ===${RESET}"; }

yaml_scalar() {
    python3 - "$VARS_FILE" "$1" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
m = re.search(rf"^{re.escape(key)}:\s*(.*?)\s*$", text, re.M)
if not m:
    sys.exit(1)
val = m.group(1)
if " #" in val:
    val = val.split(" #", 1)[0].rstrip()
val = val.strip().strip('"').strip("'")
print(val)
PY
}

yaml_list() {
    python3 - "$VARS_FILE" "$1" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines()
i = 0
while i < len(lines):
    if re.match(rf"^{re.escape(key)}:\s*(#.*)?$", lines[i]):
        i += 1
        while i < len(lines):
            line = lines[i]
            if line.strip() == "" or line.lstrip().startswith("#"):
                i += 1
                continue
            m = re.match(r"^  - (.+)$", line)
            if not m:
                break
            item = m.group(1)
            if " #" in item:
                item = item.split(" #", 1)[0]
            print(item.strip())
            i += 1
        break
    i += 1
else:
    sys.exit(1)
PY
}

expand_user() {
    local value="$1"
    value="${value//\{\{ provision_user \}\}/$PROVISION_USER}"
    value="${value//\{\{provision_user\}\}/$PROVISION_USER}"
    printf '%s\n' "$value"
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

rpm_ok() {
    rpm -q "$1" >/dev/null 2>&1
}

service_is() {
    # service_is <unit> enabled|active
    systemctl is-"$2" "$1" >/dev/null 2>&1
}

user_in_group() {
    local user="$1" group="$2"
    id -nG "$user" 2>/dev/null | grep -qw "$group"
}

file_contains() {
    local path="$1" pattern="$2"
    [[ -f "$path" ]] && grep -Eq -- "$pattern" "$path"
}

# --- load vars --------------------------------------------------------------

if [[ ! -f "$VARS_FILE" ]]; then
    echo "Cannot find $VARS_FILE — run this from a heimora checkout." >&2
    exit 2
fi

PROVISION_USER="$(yaml_scalar provision_user)"
DOTFILES_REPO="$(yaml_scalar dotfiles_repo)"
DOTFILES_DEST="$(expand_user "$(yaml_scalar dotfiles_dest)")"
DOTFILES_VERSION="$(yaml_scalar dotfiles_version)"
GRUB_TIMEOUT="$(yaml_scalar grub_timeout)"
GRUB_TIMEOUT_STYLE="$(yaml_scalar grub_timeout_style)"
GRUB_DISTRIBUTOR="$(yaml_scalar grub_distributor)"
GRUB_THEME="$(yaml_scalar grub_theme)"
GRUB_THEME_PATH="$(yaml_scalar grub_theme_path)"
GRUB_THEME_SCREEN="$(yaml_scalar grub_theme_screen)"
K8S_MINOR="$(yaml_scalar kubernetes_yum_minor)"

mapfile -t DOTFILES_SCOPES < <(yaml_list dotfiles_scopes)
mapfile -t COPR_REPOS < <(yaml_list copr_repos)
mapfile -t BASE_PACKAGES < <(yaml_list base_packages)
mapfile -t SWAY_PACKAGES < <(yaml_list sway_packages)
mapfile -t APP_PACKAGES < <(yaml_list app_packages)
mapfile -t DEVOPS_PACKAGES < <(yaml_list devops_packages)
mapfile -t NVIDIA_PACKAGES < <(yaml_list nvidia_packages)
mapfile -t GAMING_PACKAGES < <(yaml_list gaming_packages)
mapfile -t FLATPAK_APPS < <(yaml_list flatpak_apps)
mapfile -t GRUB_REMOVE_ARGS < <(yaml_list grub_remove_kernel_args)
mapfile -t GRUB_EXTRA_ARGS < <(yaml_list grub_extra_kernel_args)

TARGET_HOME="$(getent passwd "$PROVISION_USER" | cut -d: -f6 || true)"
[[ -n "$TARGET_HOME" ]] || TARGET_HOME="/home/$PROVISION_USER"

HAS_NVIDIA=0
if have_cmd lspci && lspci 2>/dev/null | grep -q NVIDIA; then
    HAS_NVIDIA=1
fi

FEDORA_MAJOR=""
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    FEDORA_MAJOR="${VERSION_ID%%.*}"
fi

echo -e "${BOLD}Heimora validation${RESET}"
echo "  checkout:  $REPO_ROOT"
echo "  user:      $PROVISION_USER"
echo "  nvidia:    $([[ $HAS_NVIDIA -eq 1 ]] && echo yes || echo 'no (gaming/driver checks skipped)')"

# --- host -------------------------------------------------------------------

section "Host"

if [[ -f /etc/os-release ]] && grep -q '^ID=fedora' /etc/os-release; then
    ok "Fedora ${VERSION_ID:-unknown}"
else
    fail "Not Fedora (heimora targets a Fedora Everything install)"
fi

if getent passwd "$PROVISION_USER" >/dev/null; then
    ok "User $PROVISION_USER exists"
else
    fail "User $PROVISION_USER is missing (must match provision_user)"
fi

if getent group wheel >/dev/null && user_in_group "$PROVISION_USER" wheel; then
    ok "$PROVISION_USER is in wheel"
else
    fail "$PROVISION_USER is not in wheel"
fi

shell="$(getent passwd "$PROVISION_USER" | cut -d: -f7 || true)"
if [[ "$(basename -- "${shell:-}")" == zsh ]]; then
    ok "Login shell is $shell"
else
    fail "Login shell is '${shell:-unset}', expected zsh"
fi

if [[ -z "${SUDO_USER:-}" && "$(id -un)" != "$PROVISION_USER" ]]; then
    warn "Running as $(id -un), not $PROVISION_USER — user-session checks may be skipped"
fi

# --- repositories -----------------------------------------------------------

section "Repositories"

check_repo_file() {
    local name="$1" file="$2"
    if [[ -f "$file" ]]; then
        ok "Repo $name ($file)"
    else
        fail "Repo $name missing ($file)"
    fi
}

if rpm_ok rpmfusion-free-release && rpm_ok rpmfusion-nonfree-release; then
    ok "RPM Fusion free + nonfree"
else
    fail "RPM Fusion release packages are not installed"
fi

check_repo_file hashicorp /etc/yum.repos.d/hashicorp.repo
check_repo_file kubernetes /etc/yum.repos.d/kubernetes.repo
check_repo_file vscode /etc/yum.repos.d/code.repo
check_repo_file cursor /etc/yum.repos.d/cursor.repo
check_repo_file docker /etc/yum.repos.d/docker-ce-stable.repo
check_repo_file nordvpn /etc/yum.repos.d/nordvpn.repo

if [[ -f /etc/yum.repos.d/kubernetes.repo ]] && grep -q "$K8S_MINOR" /etc/yum.repos.d/kubernetes.repo; then
    ok "Kubernetes repo tracks $K8S_MINOR"
else
    fail "Kubernetes repo does not mention $K8S_MINOR"
fi

for copr in "${COPR_REPOS[@]}"; do
    copr_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${copr//\//:}.repo"
    if [[ -f "$copr_file" ]]; then
        ok "COPR $copr"
    else
        fail "COPR $copr is not enabled ($copr_file)"
    fi
done

if [[ "${ID:-}" == fedora && -n "$FEDORA_MAJOR" && "$FEDORA_MAJOR" -lt 44 ]]; then
    cliphist_copr="$(yaml_scalar cliphist_copr)"
    cliphist_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${cliphist_copr//\//:}.repo"
    if [[ -f "$cliphist_file" ]]; then
        ok "cliphist COPR ($cliphist_copr) on Fedora $FEDORA_MAJOR"
    else
        fail "cliphist COPR missing on Fedora $FEDORA_MAJOR ($cliphist_file)"
    fi
fi

# --- packages ---------------------------------------------------------------

check_rpm_list() {
    local label="$1"
    shift
    local missing=()
    local pkg
    for pkg in "$@"; do
        if ! rpm_ok "$pkg"; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "$label (${#} packages)"
    else
        fail "$label missing: ${missing[*]}"
    fi
}

section "Packages"

check_rpm_list "base" "${BASE_PACKAGES[@]}"
check_rpm_list "sway" "${SWAY_PACKAGES[@]}"
check_rpm_list "apps" "${APP_PACKAGES[@]}"
check_rpm_list "devops" "${DEVOPS_PACKAGES[@]}"
check_rpm_list "greetd" greetd greetd-tuigreet

if rpm_ok bitwarden; then
    ok "bitwarden (official RPM)"
else
    fail "bitwarden is not installed"
fi

if have_cmd zoxide; then
    ok "zoxide is on PATH (zshrc requires it)"
else
    fail "zoxide is not on PATH — new zsh sessions will error"
fi

if [[ $HAS_NVIDIA -eq 1 ]]; then
    check_rpm_list "nvidia" "${NVIDIA_PACKAGES[@]}"
    check_rpm_list "gaming" "${GAMING_PACKAGES[@]}"
else
    warn "No NVIDIA GPU in lspci — skipped nvidia/gaming packages (expected on a VM)"
fi

# --- groups & services ------------------------------------------------------

section "Groups and services"

for group in docker nordvpn; do
    if user_in_group "$PROVISION_USER" "$group"; then
        ok "$PROVISION_USER is in $group"
    else
        fail "$PROVISION_USER is not in $group"
    fi
done

if [[ $HAS_NVIDIA -eq 1 ]]; then
    if user_in_group "$PROVISION_USER" gamemode; then
        ok "$PROVISION_USER is in gamemode"
    else
        fail "$PROVISION_USER is not in gamemode"
    fi
fi

check_unit() {
    local unit="$1" want_active="${2:-1}"
    if service_is "$unit" enabled; then
        ok "$unit is enabled"
    else
        fail "$unit is not enabled"
    fi
    if [[ "$want_active" -eq 1 ]]; then
        if service_is "$unit" active; then
            ok "$unit is active"
        else
            fail "$unit is not active"
        fi
    fi
}

check_unit firewalld
check_unit bluetooth
check_unit docker
check_unit nordvpnd
# greetd Conflicts=getty@tty1 — it may be enabled but not running on the
# console that is executing this script. Enabled is the contract.
if service_is greetd enabled; then
    ok "greetd is enabled"
else
    fail "greetd is not enabled"
fi
if service_is greetd active; then
    ok "greetd is active"
else
    warn "greetd is not active (normal if you are still on getty@tty1)"
fi

default_target="$(systemctl get-default 2>/dev/null || true)"
if [[ "$default_target" == graphical.target ]]; then
    ok "Default target is graphical.target"
else
    fail "Default target is '${default_target:-unknown}', expected graphical.target"
fi

# --- login chain ------------------------------------------------------------

section "Login (greetd → Sway)"

if getent passwd greeter >/dev/null; then
    ok "greeter account exists"
else
    fail "greeter account is missing — greetd will exit and take getty@tty1 with it"
fi

if [[ -x /usr/local/bin/heimora-sway ]]; then
    ok "/usr/local/bin/heimora-sway is executable"
else
    fail "/usr/local/bin/heimora-sway is missing or not executable"
fi

# Without the flag, sway <= 1.11 exits the moment it sees nvidia-drm and greetd
# bounces back to tuigreet, which looks like a rejected password.
if [[ $HAS_NVIDIA -eq 1 ]]; then
    if file_contains /usr/local/bin/heimora-sway '\-\-unsupported-gpu'; then
        ok "heimora-sway passes --unsupported-gpu to sway"
    else
        fail "heimora-sway does not pass --unsupported-gpu — sway will exit on the proprietary NVIDIA driver"
    fi
fi

if file_contains /etc/greetd/config.toml 'command = "tuigreet --time --cmd /usr/local/bin/heimora-sway"' \
    && file_contains /etc/greetd/config.toml 'user = "greeter"'; then
    ok "greetd launches tuigreet → heimora-sway as greeter"
else
    fail "/etc/greetd/config.toml does not match the playbook (tuigreet / heimora-sway / greeter)"
fi

if [[ -d /var/cache/tuigreet ]]; then
    owner="$(stat -c '%U:%G' /var/cache/tuigreet 2>/dev/null || true)"
    if [[ "$owner" == greeter:greeter ]]; then
        ok "/var/cache/tuigreet owned by greeter"
    else
        fail "/var/cache/tuigreet owner is '${owner:-unknown}', expected greeter:greeter"
    fi
else
    fail "/var/cache/tuigreet is missing"
fi

if [[ -d /dev/dri ]]; then
    if ls /dev/dri/card* >/dev/null 2>&1; then
        ok "DRM node present under /dev/dri (Sway needs this)"
    else
        fail "/dev/dri exists but has no card* — Sway will not start"
    fi
else
    fail "/dev/dri is missing — Sway will not start"
fi

# --- bootloader -------------------------------------------------------------

section "Bootloader"

if [[ ! -f /etc/default/grub ]]; then
    warn "No /etc/default/grub — bootloader role is a no-op on this machine"
else
    if file_contains /etc/default/grub "^GRUB_TIMEOUT=${GRUB_TIMEOUT}$"; then
        ok "GRUB_TIMEOUT=$GRUB_TIMEOUT"
    else
        fail "GRUB_TIMEOUT is not $GRUB_TIMEOUT"
    fi
    if file_contains /etc/default/grub "^GRUB_TIMEOUT_STYLE=${GRUB_TIMEOUT_STYLE}$"; then
        ok "GRUB_TIMEOUT_STYLE=$GRUB_TIMEOUT_STYLE"
    else
        fail "GRUB_TIMEOUT_STYLE is not $GRUB_TIMEOUT_STYLE"
    fi
    if file_contains /etc/default/grub "^GRUB_DISTRIBUTOR=\"${GRUB_DISTRIBUTOR}\"$"; then
        ok "GRUB_DISTRIBUTOR=$GRUB_DISTRIBUTOR"
    else
        fail "GRUB_DISTRIBUTOR is not $GRUB_DISTRIBUTOR"
    fi

    if [[ "$GRUB_THEME" == true ]]; then
        if file_contains /etc/default/grub "^GRUB_THEME=\"${GRUB_THEME_PATH}\"$"; then
            ok "GRUB_THEME=$GRUB_THEME_PATH"
        else
            fail "GRUB_THEME is not $GRUB_THEME_PATH"
        fi
        theme_dir="$(dirname "$GRUB_THEME_PATH")"
        if [[ -f "$GRUB_THEME_PATH" && -f "$theme_dir/background.jpg" ]]; then
            ok "GRUB theme files present ($GRUB_THEME_SCREEN background)"
        else
            fail "GRUB theme files missing under $theme_dir"
        fi
        if file_contains /etc/default/grub '^GRUB_TERMINAL_OUTPUT="gfxterm"'; then
            ok "GRUB_TERMINAL_OUTPUT=gfxterm"
        else
            fail "GRUB_TERMINAL_OUTPUT is not gfxterm"
        fi
    fi

    cmdline_file="$(tr -s ' ' </etc/default/grub | grep -E '^GRUB_CMDLINE_LINUX=' || true)"
    live_cmdline="$(< /proc/cmdline)"
    grub_bad=0
    for token in "${GRUB_REMOVE_ARGS[@]}"; do
        if grep -Eq "(^|[[:space:]])GRUB_CMDLINE_LINUX=.*[[:space:]]${token}([\"[:space:]]|$)" <<<"$cmdline_file" \
            || grep -Eq "(^|[[:space:]])${token}([[:space:]]|$)" <<<"$live_cmdline"; then
            fail "Kernel arg '$token' is still present (should have been stripped)"
            grub_bad=1
        fi
    done
    if [[ $grub_bad -eq 0 ]]; then
        ok "Removed kernel args are gone (${GRUB_REMOVE_ARGS[*]})"
    fi
    for token in "${GRUB_EXTRA_ARGS[@]}"; do
        if grep -Eq "(^|[[:space:]])${token}([[:space:]]|$)" <<<"$live_cmdline" \
            || grep -Fq "$token" <<<"$cmdline_file"; then
            ok "Kernel arg $token is set"
        else
            fail "Kernel arg $token is missing"
        fi
    done
    if grep -Eq '(^|[[:space:]])nvidia-drm\.modeset=1([[:space:]]|$)' <<<"$live_cmdline"; then
        fail "nvidia-drm.modeset=1 is on the kernel command line (fights Fedora simpledrm)"
    else
        ok "nvidia-drm.modeset=1 is not set"
    fi
fi

# --- nvidia -----------------------------------------------------------------

if [[ $HAS_NVIDIA -eq 1 ]]; then
    section "NVIDIA"

    if have_cmd mokutil; then
        sb="$(mokutil --sb-state 2>/dev/null || true)"
        if grep -qi 'enabled' <<<"$sb"; then
            warn "Secure Boot is enabled — unsigned nvidia.ko will not load ($sb)"
        else
            ok "Secure Boot is not blocking the NVIDIA module"
        fi
    fi

    if ver="$(modinfo -F version nvidia 2>/dev/null)"; then
        if [[ "$ver" == 580.* ]]; then
            ok "nvidia module version $ver"
        else
            warn "nvidia module version is $ver (playbook installs 580xx for Pascal)"
        fi
        if lsmod | grep -q '^nvidia'; then
            ok "nvidia kernel module is loaded"
        else
            warn "nvidia.ko is built but not loaded — reboot before using the GPU"
        fi
    else
        fail "modinfo nvidia failed — wait for akmods, then reboot"
    fi
fi

# --- dotfiles ---------------------------------------------------------------

section "Dotfiles"

if [[ -d "$DOTFILES_DEST/.git" ]]; then
    ok "Dotfiles checkout at $DOTFILES_DEST"
    remote="$(git -C "$DOTFILES_DEST" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote" == "$DOTFILES_REPO" ]]; then
        ok "origin is $DOTFILES_REPO"
    else
        warn "origin is '${remote:-unset}', expected $DOTFILES_REPO"
    fi
    branch="$(git -C "$DOTFILES_DEST" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [[ "$branch" == "$DOTFILES_VERSION" ]]; then
        ok "Branch is $DOTFILES_VERSION"
    else
        warn "Branch is '${branch:-unset}', expected $DOTFILES_VERSION"
    fi
else
    fail "Dotfiles checkout missing at $DOTFILES_DEST"
fi

MANIFEST="$DOTFILES_DEST/links.conf"
if [[ -f "$MANIFEST" ]]; then
    ok "links.conf is present"
    linked=0
    dangling=0
    wrong=0
    skipped=0
    while read -r scope src dest; do
        [[ -z "${scope:-}" ]] && continue
        in_scope=0
        for s in "${DOTFILES_SCOPES[@]}"; do
            if [[ "$s" == "$scope" ]]; then
                in_scope=1
                break
            fi
        done
        if [[ $in_scope -eq 0 ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        dest_path="$TARGET_HOME/$dest"
        src_path="$DOTFILES_DEST/$src"
        if [[ ! -e "$src_path" && ! -L "$src_path" ]]; then
            fail "Manifest source missing: $src"
            continue
        fi
        if [[ -L "$dest_path" ]]; then
            actual="$(readlink -f "$dest_path" 2>/dev/null || readlink "$dest_path")"
            expected="$(readlink -f "$src_path" 2>/dev/null || printf '%s' "$src_path")"
            if [[ "$actual" == "$expected" ]]; then
                linked=$((linked + 1))
            else
                fail "$dest_path points at $actual, expected $expected"
                wrong=$((wrong + 1))
            fi
        elif [[ ! -e "$dest_path" ]]; then
            fail "$dest_path is not linked"
            dangling=$((dangling + 1))
        else
            fail "$dest_path exists but is not a symlink"
            wrong=$((wrong + 1))
        fi
    done < <(grep -vE '^\s*(#|$)' "$MANIFEST")
    if [[ $wrong -eq 0 && $dangling -eq 0 ]]; then
        ok "Linked $linked configs for scopes: ${DOTFILES_SCOPES[*]} ($skipped out of scope)"
    fi
else
    fail "links.conf missing at $MANIFEST"
fi

if printf '%s\n' "${DOTFILES_SCOPES[@]}" | grep -qx wayland; then
    if [[ -d "$TARGET_HOME/.config/sway-local" ]]; then
        ok "$TARGET_HOME/.config/sway-local exists"
    else
        fail "$TARGET_HOME/.config/sway-local is missing"
    fi
fi

if [[ -d "$TARGET_HOME/.tmux/plugins/tpm" ]]; then
    ok "tmux plugin manager is installed"
else
    fail "tpm is missing at $TARGET_HOME/.tmux/plugins/tpm"
fi

# --- flatpak / optional extras ----------------------------------------------

section "Flatpak and extras"

if have_cmd flatpak; then
    remotes="$(flatpak remotes --system --columns=name 2>/dev/null || true)"
    if grep -qx flathub <<<"$remotes"; then
        ok "Flathub remote is configured"
    else
        fail "Flathub remote is missing"
    fi
    installed="$(flatpak list --system --app --columns=application 2>/dev/null || true)"
    for app in "${FLATPAK_APPS[@]}"; do
        if grep -qx "$app" <<<"$installed"; then
            ok "Flatpak $app"
        else
            fail "Flatpak $app is not installed"
        fi
    done
else
    fail "flatpak is not installed"
fi

if [[ -x /opt/resolve/bin/resolve ]]; then
    ok "DaVinci Resolve is installed at /opt/resolve"
else
    warn "DaVinci Resolve is not at /opt/resolve — download the Linux zip and run davinci-helper after the first Sway login"
fi

# pipewire user units need a user D-Bus session
if [[ "$(id -un)" == "$PROVISION_USER" ]] && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    if systemctl --user is-enabled pipewire.socket >/dev/null 2>&1 \
        && systemctl --user is-enabled wireplumber.service >/dev/null 2>&1; then
        ok "pipewire.socket and wireplumber.service are enabled for $PROVISION_USER"
    else
        warn "pipewire/wireplumber user units are not enabled — after the first Sway login: systemctl --user enable --now pipewire.socket wireplumber.service"
    fi
else
    warn "Not in $PROVISION_USER's session — skipped pipewire user-unit check"
fi

# --- summary ----------------------------------------------------------------

echo
echo -e "${BOLD}Summary${RESET}  ${GREEN}${PASS} ok${RESET}  ${YELLOW}${WARN} warn${RESET}  ${RED}${FAIL} fail${RESET}"
if [[ $FAIL -gt 0 ]]; then
    echo "Something the playbook should have configured is missing. Re-run:"
    echo "  sudo ansible-playbook $REPO_ROOT/ansible/site.yml"
    exit 1
fi
if [[ $WARN -gt 0 ]]; then
    echo "No hard failures. Warnings are expected for NVIDIA reboot, DaVinci Resolve, and first-login user units."
fi
echo "Looks good."
exit 0
