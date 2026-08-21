# heimora

Heimora is my personal flavor of Fedora. Heim refers to Heimdall (guardian of Bifrost).

Install a **minimal Fedora Everything** system yourself (disk, user, network). Then pull this repo and let Ansible build the Sway environment.

```
Minimal Fedora Everything install (Anaconda, by hand)
        │  sudo dnf install -y ansible-core git
        │  sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git …
        ▼
ansible/site.yml
        │  base → bootloader → nvidia → sway → apps → dotfiles → services
        ▼
greetd (tuigreet) → Sway, dotfiles linked
```

| Layer | Tool | Responsibility |
|-------|------|----------------|
| OS install | Fedora Everything ISO + Anaconda | Disk, user, network, a bootable base |
| Environment | Ansible (`ansible-pull` / `ansible-playbook`) | Sway, apps, dotfiles, greetd, GRUB — idempotent and re-runnable |

This stops short of a custom ISO. Package and config changes are git commits, not a rebuilt image.

## Repo layout

```
heimora/
├── ansible.cfg              # picked up from the checkout root (ansible-pull)
├── ansible/
│   ├── inventory.ini        # localhost, for ansible-playbook re-runs
│   ├── site.yml             # entry point
│   ├── group_vars/
│   │   └── all.yml          # package lists — edit this most
│   └── roles/
│       ├── base/            # repos, shell, firewall, core CLI
│       ├── bootloader/      # GRUB menu, theme, kernel args (drops rhgb quiet)
│       ├── sway/            # sway + Wayland companions
│       ├── nvidia/          # GTX 1060 / Pascal 580xx driver + Steam (skipped without a GPU)
│       ├── apps/            # general + devops packages
│       ├── dotfiles/        # clone dotfiles repo, symlink per its links.conf
│       └── services/        # greetd
├── README.md
├── DEPLOY-VM.md             # first test in a VM
└── APPS-INVENTORY.md        # app categories to decide on
```

## First-time setup (per machine)

1. Install Fedora from the [Everything netinst ISO](https://fedoraproject.org/misc/). Choose the **Fedora Server** package set. Create user **`mathias`** (must match `provision_user` in `ansible/group_vars/all.yml`) and put that user in **wheel**.
2. Log in, get network, then:

```bash
sudo systemctl disable --now cockpit.socket
sudo dnf remove cockpit*
sudo hostnamectl set-hostname --static <hostname>
hostnamectl
sudo dnf update
sudo dnf install -y ansible-core git
sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git \
  -C main \
  -d /opt/heimora \
  ansible/site.yml
```

`ansible-pull` clones the repo to `/opt/heimora` and runs `ansible/site.yml` against the local machine. That takes a while (RPM Fusion, Sway, apps).

3. Reboot or log out. **tuigreet** should start **Sway**. How to move around (Sway, tmux, Ghostty, zsh, lf, nvim) lives in the [dotfiles cheat sheet](https://github.com/mathiaswouters/dotfiles/blob/master/CHEATSHEET.md).
4. DaVinci Resolve is not fully automated — finish it by hand after the first Sway login. See [DaVinci Resolve](#davinci-resolve).

Create the GitHub repo and push **before** you run this on a machine. The pull URL must be cloneable. The dotfiles role also clones `dotfiles_repo` from `group_vars/all.yml`.

Full VM walkthrough: [DEPLOY-VM.md](DEPLOY-VM.md).

## How dotfiles are wired

This repo does not decide what gets linked where. The [dotfiles repo](https://github.com/mathiaswouters/dotfiles) owns that, in a `links.conf` manifest mapping a source to a destination under `$HOME`, tagged with a scope. The `dotfiles` role reads that file and links every entry whose scope appears in `dotfiles_scopes`:

```yaml
dotfiles_scopes:
  - common     # linked everywhere
  - wayland    # sway, waybar, mako
  - ghostty    # pick exactly one terminal
```

The same manifest is read by `scripts/setup.sh` in the dotfiles repo, which is how a Mac set up by hand and a Fedora box provisioned here stay in agreement. To add a config, add it in the dotfiles repo and append one line to `links.conf` — nothing here changes.

The role **fails** if a manifest source does not exist in the checkout. That matters: `ansible.builtin.file` with `state: link` and `force: true` will cheerfully create a dangling symlink, so without the check a layout mismatch produced a green playbook and a machine with no working `~/.zshrc`.

## Iterating afterwards

```bash
cd /opt/heimora
sudo git pull
sudo ansible-playbook ansible/site.yml
```

Or pull and run in one step again:

```bash
sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git -C main -d /opt/heimora ansible/site.yml
```

Useful flags (after `--` for `ansible-pull`, or on `ansible-playbook`):

- `--tags sway` — only the sway role
- `--tags bootloader` — only GRUB timeout, theme, and kernel args
- `--tags nvidia` — only the 580xx driver and gaming packages
- `--check` — dry run
- `-vv` — verbose

## GRUB

The `bootloader` role restyles Fedora's GRUB (timeout, a colour-only Heimora theme, distributor name) and edits kernel args **without** rewriting the `root=` / `rd.luks` line Anaconda wrote.

Defaults in `ansible/group_vars/all.yml`:

- `grub_timeout: 5` and `grub_timeout_style: menu` — the menu is visible, not hidden.
- `grub_remove_kernel_args: [rhgb, quiet]` — a broken greetd then prints kernel messages instead of freezing on GRUB's last line.
- `grub_theme: true` — set `false` if gfxterm misbehaves (unusual; GRUB runs before the NVIDIA driver).
- `grub_extra_kernel_args: []` — add tokens here if you need them. Do **not** add `nvidia-drm.modeset=1`.

`--tags bootloader` re-runs only this role. A change to `/etc/default/grub` or the theme rebuilds `grub.cfg` via a handler.

## Adding a new app

1. Pick a category in `APPS-INVENTORY.md`.
2. Add the package name to the matching list in `ansible/group_vars/all.yml`.
3. Re-run the playbook (or `--tags apps` / `--tags sway`).

## DaVinci Resolve

Blackmagic does not let us redistribute the installer, so Ansible cannot put Resolve on the machine. The playbook only prepares Fedora: it enables the `herzen/davinci-helper` COPR and installs `davinci-helper`, `libxcrypt-compat`, and `mesa-libGLU`. You still have to download Resolve yourself and run it through that helper.

Do this **after** the first Sway login, not during `ansible-pull`.

1. Create a free account at [Blackmagic Design](https://www.blackmagicdesign.com/products/davinciresolve) if you do not already have one.
2. Download the **Linux** zip (free DaVinci Resolve, or Studio if you have a licence). Save it somewhere convenient, e.g. `~/Downloads`. Do not extract it; the helper wants the zip.
3. Launch **DaVinci Helper** from the app launcher (wofi).
4. In the helper, run the steps in order:
   1. **Install missing dependencies** — extra Fedora packages the stock installer will not pull in.
   2. **Launch DaVinci Resolve installer** — pick the zip from step 2. The helper starts the `.run` with `SKIP_PACKAGE_CHECK=1`, which Fedora needs because Resolve only officially supports Rocky/RHEL.
   3. **Apply post-install fixes** — Resolve ships old `libglib` / `libgio` copies that crash against Fedora's libraries. The helper moves those aside under `/opt/resolve`.
5. Start Resolve from the launcher, or `/opt/resolve/bin/resolve`.

Linux Resolve is picky about GPUs. This machine is a **GTX 1060 (Pascal)**; the playbook installs RPM Fusion's **580xx** driver plus CUDA, not current `akmod-nvidia` (595+ dropped Pascal). AMD/Intel can open the UI but hardware encode/decode is limited or missing. On Wayland it runs through XWayland; if it fails to start, try `QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve`.

Updating Resolve later is the same loop: download a new zip from Blackmagic, then use the helper's installer step again.

## NVIDIA and gaming

The GTX 1060 is Pascal. Fedora 44's default `akmod-nvidia` is 595+, which does not support that card. The `nvidia` role therefore installs [RPM Fusion's 580xx legacy branch](https://rpmfusion.org/Howto/NVIDIA) (`akmod-nvidia-580xx`, CUDA, 32-bit libs for Proton) plus Steam, Lutris, GameMode, MangoHud, and gamescope.

That role is a no-op when `lspci` sees no NVIDIA adapter, so a VM without GPU passthrough still provisions. On the real PC:

1. Run the playbook, then wait until `modinfo nvidia` prints a **580.x** version (akmods can take a few minutes).
2. **Reboot.** The module is not used until the next boot.
3. Disable **Secure Boot**, or enrol a MOK and sign the kmod. An unsigned module with Secure Boot on means nouveau or a black screen.
4. Do **not** add `nvidia-drm.modeset=1` to the kernel command line. RPM Fusion already enables KMS; that flag fights Fedora's simpledrm patch.

greetd starts `/usr/local/bin/heimora-sway` instead of bare `sway`. If the nvidia module is loaded, that wrapper sets `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `LIBVA_DRIVER_NAME`, and `WLR_NO_HARDWARE_CURSORS` before the compositor starts.

Steam launch options that usually help on this GPU:

```
gamemoderun mangohud %command%
```

If a title will not start under Sway, wrap it in gamescope:

```
gamemoderun gamescope -f -- %command%
```

## Design decisions

- **Why not a custom ISO?** Worth it for distributing to other people or offline installs. For rebuilding your own machine, Ansible + git is less to maintain.
- **Why `ansible-pull` instead of Kickstart?** You already walk through Anaconda once; Kickstart was another file to keep in sync with disks and secrets. `ansible-pull` is the whole automation after a stock minimal install.
- **Why Ansible over a bash script?** Idempotency. Re-running `site.yml` is safe; dnf/file modules no-op when the system is already in the desired state.
- **Why not chezmoi/stow?** The `dotfiles` role uses `file` symlinks driven by the dotfiles repo's own `links.conf`, so the dotfiles stay usable on macOS and WSL without Ansible. Swap the role for `chezmoi apply` later if you need per-device templating rather than per-device includes.
- **Why is the terminal Ghostty but `foot` still installed?** Ghostty is not in the Fedora repos and comes from a COPR, and it has a track record of startup crashes on brand-new Fedora releases. `foot` is small, in Fedora proper, and guarantees a way back into a shell if Ghostty will not start.

## Known gotchas

- Run `ansible-pull` with **sudo**. The playbook uses `become` with `become_ask_pass = False`.
- A minimal Fedora install boots to `multi-user.target`. Enabling greetd is not enough on its own, because greetd is `WantedBy=graphical.target` — you would reboot straight back into a TTY. The `services` role runs `systemctl set-default graphical.target` to fix that. Verify with `systemctl get-default`.
- greetd's unit is `Conflicts=getty@tty1.service`, so a greetd that fails to start also takes down the only getty you would have used to debug it. Fedora's default `rhgb quiet` plus no plymouth on a minimal install used to freeze GRUB's `Booting …` message on screen. The `bootloader` role strips those args so kernel and systemd messages print; `Ctrl+Alt+F3` or SSH still gets you in. See [DEPLOY-VM.md](DEPLOY-VM.md#recovering-a-machine-with-no-login-prompt).
- Fedora's `greetd` package does not create the `greeter` user that `/etc/greetd/config.toml` points at, and greetd exits immediately without it. The `services` role creates it and asserts it resolves before switching the default target, because that combination is exactly how you get a green playbook and an unbootable-looking machine.
- `pipewire` / `wireplumber` user units need a user D-Bus session. That usually is not there during `ansible-pull`. The tasks use `ignore_errors`. After the first Sway login:

  ```bash
  systemctl --user enable --now pipewire.socket wireplumber.service
  ```

- RPM Fusion URLs in the `base` role use `ansible_distribution_major_version`. Check they exist on a very new Fedora.
- Four packages come from COPRs listed in `copr_repos`: `starship`, `lf`, `ghostty`, and `davinci-helper`. On Fedora 43 and older, `cliphist` is pulled from `alternateved/cliphist` as well. COPRs lag new Fedora releases, so if the playbook fails on one, check that a build exists for your Fedora version before assuming the package name is wrong.
- NVIDIA/gaming packages install only when `lspci` reports an NVIDIA device. On a VM you will see a skip message; that is expected.
- The dotfiles' `.zshrc` runs `eval "$(zoxide init zsh)"` unconditionally, so `zoxide` must stay in `app_packages` — without it every new shell opens with an error.
- On first login zsh clones its own plugins into `~/.config/zsh/plugins`, so the first shell needs network. tmux plugins are installed by pressing `prefix + I` (prefix is `Ctrl+A`) once.
- Per-machine Sway output settings go in `~/.config/sway-local/*.conf`, created by the dotfiles role. `~/.config/sway` itself is a symlink into the dotfiles repo, so do not edit it in place on a machine.
