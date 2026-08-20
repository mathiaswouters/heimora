# heimora

Heimora is my personal flavor of Fedora

It will use ansible playbooks for the automated install.

Heim refers to Heimdall (guardian of Bifrost)

- Use Fedora Everythin ISO and just install base OS and nothing else
- Install ZSH and remove bash
- Install sway
- ...

---

# fedora-sway-bootstrap

Automated, repeatable setup for a minimal Fedora (Everything ISO) + Sway environment.
Goal: go from bare metal to your full daily-driver desktop with as close to zero manual steps as possible, on any new device.

This intentionally stops short of building a custom Fedora ISO. For a single-user setup that changes over time, a kickstart file + Ansible gets you the same outcome with far less to maintain — no image pipeline, no rebuild-and-reburn-USB loop every time you tweak a config.

## How it fits together

```
┌───────────────────┐     inst.ks=...      ┌────────────────────────┐
│ Fedora Everything │ ───────────────────► │ Anaconda unattended    │
│ ISO (USB/PXE)     │                      │ install (kickstart.ks) │
└───────────────────┘                      └───────────┬────────────┘
                                                       │ %post
                                                       ▼
                                          systemd oneshot unit enabled,
                                          clones this repo to /opt
                                                       │
                                                       │ first real boot
                                                       ▼
                                          ┌────────────────────────┐
                                          │ ansible-playbook       │
                                          │ site.yml runs roles:   │
                                          │ base → sway → apps →   │
                                          │ dotfiles → services    │
                                          └───────────┬────────────┘
                                                       ▼
                                          Fully configured Sway session,
                                          your dotfiles symlinked in,
                                          greetd boots straight to it
```

Two layers, two tools, each doing the thing it's actually good at:

| Layer       | Tool                               | Responsibility |
|-------------|------------------------------------|----------------|
| OS install  | Kickstart (`kickstart/heimora.ks`) | Disk layout, user creation, network, minimal base packages, hands off to Ansible |
| Environment | Ansible (`ansible/`)               | Sway + apps + dotfiles + services, idempotent and re-runnable any time |

## Repo layout

```
fedora-sway-bootstrap/
├── kickstart/
│   └── heimora.ks       # Anaconda kickstart file
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini    # localhost only, by design
│   ├── site.yml         # entry point, orchestrates roles
│   ├── group_vars/
│   │   └── all.yml      # ALL package lists live here — edit this file most
│   └── roles/
│       ├── base/        # repos, shell, firewall, core CLI tools
│       ├── sway/        # sway + companion wayland tools
│       ├── apps/        # general + devops packages
│       ├── dotfiles/    # clone dotfiles repo, symlink configs
│       └── services/    # greetd login manager, final enablement
├── README.md
└── APPS_INVENTORY.md    # checklist of app categories to decide on
```

## Usage

### 1. First-time setup (per new device)

1. Write your own package/user secrets into `kickstart/heimora.ks`:
   - replace `REPLACE_WITH_YOUR_HASH` (generate with `python3 -c 'import crypt; print(crypt.crypt("yourpassword", crypt.mksalt(crypt.METHOD_SHA512)))'`)
   - replace `REPLACE_WITH_LUKS_PASSPHRASE`, or drop `--encrypted` entirely if you don't want disk encryption
   - point the `git clone` URL at your actual GitHub repo once you push this project
2. Validate it: `ksvalidator kickstart/heimora.ks`
3. Boot the Fedora Everything ISO on the new machine, and at the boot prompt add:
   ```
   inst.ks=https://raw.githubusercontent.com/<you>/fedora-sway-bootstrap/main/kickstart/heimora.ks
   ```
   (or serve it from a USB stick / local PXE server if you don't want it public)
4. Anaconda installs unattended, reboots.
5. On first real boot, the `first-boot-provision.service` systemd unit
   automatically clones this repo and runs `ansible-playbook site.yml`.
6. Log in via greetd → you're in Sway with your dotfiles already linked.

### 2. Iterating afterwards

Once a machine is up, you don't need the kickstart again — just edit
`ansible/group_vars/all.yml` or the roles and re-run:

```bash
cd /opt/fedora-sway-bootstrap/ansible
ansible-playbook -i inventory.ini site.yml
```

Useful flags:
- `--tags sway` — only touch the sway role
- `--check` — dry run, see what would change
- `-vv` — verbose output when debugging a task

### 3. Adding a new app

1. Decide which category it belongs to using `APPS_INVENTORY.md`.
2. Add the package name to the right list in `group_vars/all.yml`.
3. Re-run the playbook (or just `--tags apps` / `--tags sway`).

## Design decisions / why not X

- **Why not a custom ISO (Omarchy-style)?** Worth it when you're
  distributing to other people or need fully offline/airgapped installs.
  For "rebuild my own laptop," a kickstart + Ansible repo is far less to
  maintain and every change is a normal git commit instead of a rebuilt
  image.
- **Why Ansible over a plain bash script?** Idempotency and readability.
  Re-running `site.yml` on an already-provisioned machine is safe and
  fast (dnf/file modules no-op on things already in the desired state).
  It also doubles as living documentation of your whole setup.
- **Why not chezmoi/stow for dotfiles?** The `dotfiles` role currently
  hand-rolls symlinks via the `file` module, which is enough for a single
  machine profile. If you end up wanting per-device templated configs
  (e.g. different monitor layout on desktop vs laptop), swap that role's
  tasks for `chezmoi apply` — the rest of the pipeline doesn't change.

## Known gotchas

- The `pipewire`/`wireplumber` user-service enablement in the `sway` role
  needs an active user D-Bus session, which usually isn't present during
  first-boot provisioning (no one has logged in yet). It's wrapped in
  `ignore_errors: true` for that reason — if it doesn't take, just run
  `systemctl --user enable pipewire.socket wireplumber.service` once
  after your first interactive login.
- `autopart --type=lvm --encrypted` in the kickstart will prompt for a
  LUKS passphrase on every boot unless you set one non-interactively via
  `--passphrase`. Keep that value out of a public repo (use a private
  repo, or template it in via a secrets tool instead of committing it).
- RPM Fusion package URLs in `base` role are versioned by
  `ansible_distribution_major_version` — fine as long as you're on a
  release Fedora provides RPM Fusion packages for; double check on very
  new releases.
