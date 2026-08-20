# heimora

Heimora is my personal flavor of Fedora. Heim refers to Heimdall (guardian of Bifrost).

Install a **minimal Fedora Everything** system yourself (disk, user, network). Then pull this repo and let Ansible build the Sway environment.

```
Minimal Fedora Everything install (Anaconda, by hand)
        │  sudo dnf install -y ansible-core git
        │  sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git …
        ▼
ansible/site.yml
        │  base → sway → apps → dotfiles → services
        ▼
greetd (tuigreet) → Sway, dotfiles linked
```

| Layer | Tool | Responsibility |
|-------|------|----------------|
| OS install | Fedora Everything ISO + Anaconda | Disk, user, network, a bootable base |
| Environment | Ansible (`ansible-pull` / `ansible-playbook`) | Sway, apps, dotfiles, greetd — idempotent and re-runnable |

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
│       ├── sway/            # sway + Wayland companions
│       ├── apps/            # general + devops packages
│       ├── dotfiles/        # clone dotfiles repo, symlink per its links.conf
│       └── services/        # greetd
├── README.md
├── DEPLOY-VM.md             # first test in a VM
└── APPS-INVENTORY.md        # app categories to decide on
```

## First-time setup (per machine)

1. Install Fedora from the [Everything netinst ISO](https://fedoraproject.org/misc/). Choose a **minimal** package set. Create user **`mathias`** (must match `provision_user` in `ansible/group_vars/all.yml`) and put that user in **wheel**.
2. Log in, get network, then:

```bash
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

3. Reboot or log out. **tuigreet** should start **Sway**.

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
- `--check` — dry run
- `-vv` — verbose

## Adding a new app

1. Pick a category in `APPS-INVENTORY.md`.
2. Add the package name to the matching list in `ansible/group_vars/all.yml`.
3. Re-run the playbook (or `--tags apps` / `--tags sway`).

## Design decisions

- **Why not a custom ISO?** Worth it for distributing to other people or offline installs. For rebuilding your own machine, Ansible + git is less to maintain.
- **Why `ansible-pull` instead of Kickstart?** You already walk through Anaconda once; Kickstart was another file to keep in sync with disks and secrets. `ansible-pull` is the whole automation after a stock minimal install.
- **Why Ansible over a bash script?** Idempotency. Re-running `site.yml` is safe; dnf/file modules no-op when the system is already in the desired state.
- **Why not chezmoi/stow?** The `dotfiles` role uses `file` symlinks driven by the dotfiles repo's own `links.conf`, so the dotfiles stay usable on macOS and WSL without Ansible. Swap the role for `chezmoi apply` later if you need per-device templating rather than per-device includes.
- **Why is the terminal Ghostty but `foot` still installed?** Ghostty is not in the Fedora repos and comes from a COPR, and it has a track record of startup crashes on brand-new Fedora releases. `foot` is small, in Fedora proper, and guarantees a way back into a shell if Ghostty will not start.

## Known gotchas

- Run `ansible-pull` with **sudo**. The playbook uses `become` with `become_ask_pass = False`.
- A minimal Fedora install boots to `multi-user.target`. Enabling greetd is not enough on its own, because greetd is `WantedBy=graphical.target` — you would reboot straight back into a TTY. The `services` role runs `systemctl set-default graphical.target` to fix that. Verify with `systemctl get-default`.
- `pipewire` / `wireplumber` user units need a user D-Bus session. That usually is not there during `ansible-pull`. The tasks use `ignore_errors`. After the first Sway login:

  ```bash
  systemctl --user enable --now pipewire.socket wireplumber.service
  ```

- RPM Fusion URLs in the `base` role use `ansible_distribution_major_version`. Check they exist on a very new Fedora.
- Three packages come from COPRs listed in `copr_repos`: `starship`, `lf`, and `ghostty`. COPRs lag new Fedora releases, so if the playbook fails on one, check that a build exists for your Fedora version before assuming the package name is wrong.
- The dotfiles' `.zshrc` runs `eval "$(zoxide init zsh)"` unconditionally, so `zoxide` must stay in `app_packages` — without it every new shell opens with an error.
- On first login zsh clones its own plugins into `~/.config/zsh/plugins`, so the first shell needs network. tmux plugins are installed by pressing `prefix + I` (prefix is `Ctrl+A`) once.
- Per-machine Sway output settings go in `~/.config/sway-local/*.conf`, created by the dotfiles role. `~/.config/sway` itself is a symlink into the dotfiles repo, so do not edit it in place on a machine.
