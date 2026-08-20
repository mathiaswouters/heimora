# App / Package Inventory

Checklist of categories a Sway-based daily driver typically needs, so you can spot gaps before you're mid-workday missing something. Check items off as you decide, and add the package name to `ansible/group_vars/all.yml` under the matching list (`sway_packages`, `app_packages`, `devops_packages`, or `base_packages`).

Legend: pre-filled in the playbook skeleton already · suggested alternatives in *(...)*.

## Core Wayland / Sway ecosystem (required, essentially non-optional)

- [x] Compositor: **sway**
- [x] Status bar: **waybar** *(alternative: yambar, i3status-rs)*
- [x] Application launcher: **wofi** *(alternatives: fuzzel, rofi-wayland, tofi)*
- [x] Terminal emulator: **ghostty** (configured, from COPR) with **foot** installed as a fallback *(alternatives: alacritty, kitty, wezterm)*
- [x] Notification daemon: **mako** *(alternative: swaync, dunst — mako is Wayland-native)*, configured and offset below waybar
- [x] Screen locker: **swaylock** *(alternative: gtklock)*
- [x] Idle management: **swayidle**
- [x] Wallpaper: **swaybg** *(alternative: hyprpaper works too, or waypaper as a GUI picker)*
- [x] Screenshot: **grim** + **slurp** *(alternative: sway's own `swaymsg` combined with grimshot wrapper script)*
- [x] Clipboard manager: **wl-clipboard** *(add cliphist for clipboard history)*
- [x] Desktop portal (screen-share, file pickers): **xdg-desktop-portal-wlr**
- [x] Polkit agent: **polkit-gnome** *(alternative: lxqt-policykit, or mate-polkit)*
- [x] Login manager: **greetd** + **tuigreet** *(alternative: SDDM with wayland session, or ly)*
- [x] Screen brightness control: **brightnessctl**, bound to the `XF86MonBrightness` keys in `sway/config`
- [ ] Output/monitor management: `wlr-randr`, or `kanshi` for auto profiles on dock/undock

## Audio / Bluetooth / Network

- [x] Audio stack: **pipewire**, **wireplumber**, **pipewire-pulseaudio**
- [x] Audio mixer GUI: **pavucontrol** *(alternative: pwvucontrol, native pipewire GUI)*
- [ ] Bluetooth: **bluez**, **bluez-tools**, plus a UI — `blueman` (GTK) or `bluetuith` (TUI)
- [ ] Wi-Fi: **iwd** or NetworkManager's built-in wifi backend; **nmtui**/**nmcli** for a quick TUI/CLI, or **networkmanager-applet** if you want a waybar/tray integration

## Input / device management

- [ ] Keyboard remapping: `keyd` (system-level) if you want Caps-as-Ctrl etc. outside app-specific configs
- [ ] Touchpad gestures: sway's built-in `libinput` config usually covers this — confirm before adding extra tools

## File management

- [x] Terminal file manager: **lf**, configured in the dotfiles repo and wrapped by a `lf()` shell function that follows the last directory *(alternatives: yazi, ranger, nnn)*
- [ ] GUI file manager (optional on a tiling setup): **nautilus**, **pcmanfm**, or **thunar**

## Browsers

- [x] **firefox**
- [ ] Secondary/Chromium-based browser if you need it for testing: `chromium` or `google-chrome` (RPM Fusion / vendor repo)

## Terminal / shell environment

- [x] Shell: **zsh** *(alternative: fish — you'll want to decide, they configure differently)*
- [x] Prompt: **starship**
- [x] Multiplexer: **tmux** *(alternative: zellij, which has more Sway-like tiling ergonomics)*
- [x] Fuzzy finder: **fzf**
- [x] Directory jumper: **zoxide** — required, `.zshrc` initialises it unconditionally
- [x] Better grep: **ripgrep**
- [x] Better find: **fd-find**
- [x] Better cat: **bat**
- [ ] Better ls: `eza`
- [x] System info banner: **fastfetch**
- [x] Resource monitors: **htop**, **btop**
- [x] JSON processor: **jq**
- [ ] YAML processor: `yq`

## Editors / IDE

- [x] **neovim**
- [x] Editor config framework: own Lua config in the dotfiles repo, using the Lazy plugin manager
- [ ] GUI editor/IDE if needed alongside terminal editing: VS Code (via Microsoft repo, not in Fedora repos directly)

## Media / graphics

- [ ] Image viewer: `imv` (Wayland-native) or `feh`
- [ ] PDF viewer: `zathura` (pairs well with a tiling WM) or `evince`
- [ ] Video player: `mpv`
- [ ] Screen recording: `wf-recorder`

## Fonts / theming

- [x] **jetbrains-mono-fonts**, which `ghostty/config`, `waybar/style.css` and `mako/config` all request. The waybar config uses plain Unicode rather than Nerd Font private-use glyphs, so a patched Nerd Font is optional rather than required
- [ ] GTK theme + icon theme (even in a mostly-terminal setup, file pickers/portals use GTK): pick one, e.g. `adwaita-icon-theme` as a safe baseline
- [ ] Qt theme integration if you run any Qt apps: `qt5ct`/`qt6ct` + `qt5-qtwayland`/`qt6-qtwayland`

## System / power

- [ ] Power management (laptop only): `power-profiles-daemon` or `tlp`
- [ ] Battery/status info in waybar: usually built into waybar's own modules, confirm config
- [ ] Firmware updates: `fwupd` + `fwupdmgr`

## Cloud / DevOps (your day-job stack)

- [x] **ansible-core**
- [x] **terraform** *(consider `opentofu` instead if you want to avoid the license situation)*
- [x] **kubectl**
- [x] **helm**
- [x] **awscli2**
- [ ] Container runtime: **podman** + **podman-compose** *(already in app_packages — confirm this is your preference over Docker)*
- [ ] Cloud CLIs beyond AWS: `azure-cli`, `google-cloud-cli` if you touch Azure/GCP
- [ ] Kubernetes context/namespace switching: `kubectx`/`kubens`, or `k9s` for a TUI dashboard
- [ ] Infra-as-code linting: `tflint`, `checkov`
- [ ] Secrets/credentials: `vault` CLI if you use HashiCorp Vault; `aws-vault` or `sops` as alternatives
- [ ] SSH config management: consider whether your dotfiles should template `~/.ssh/config` per device

## Security tooling (fits your Cyber Security background)

- [ ] `nmap`
- [ ] `wireshark` / `tshark`
- [ ] GPG/age for secrets: `gnupg2`, `age`
- [ ] Password manager CLI/GUI: `pass`, `gopass`, `bitwarden-cli`, or a GUI client

## Notes on filling this in

- Anything checked `[x]` is already present in `group_vars/all.yml` from
  the playbook skeleton — treat those as a reasonable Sway starter set,
  not a final answer.
- Unchecked items are genuinely optional / decision points — pick what
  you actually use rather than installing everything in this list.
- Once you decide on an item, add its package name to the relevant list
  in `group_vars/all.yml` and re-run `ansible-playbook site.yml --tags apps`
  (or `sway`/`base` depending on category).
