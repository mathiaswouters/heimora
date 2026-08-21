# Heimora — first VM deployment

Install **minimal Fedora Everything** in a VM by hand, then trigger Heimora with `ansible-pull`. Do this before a real machine.

```
Fedora Everything ISO → Anaconda (minimal, you click through)
        │
        ▼
sudo dnf install -y ansible-core git
sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git …
        │  clones to /opt/heimora
        │  runs ansible/site.yml
        ▼
greetd (tuigreet) → Sway
```

---

## 0. Checklist

- [ ] `https://github.com/mathiaswouters/heimora.git` is public, branch **`main`**, with `ansible/` pushed. `ansible-pull` clones this URL.
- [ ] `https://github.com/mathiaswouters/dotfiles.git` is cloneable, branch **`master`** (`dotfiles_version` in `ansible/group_vars/all.yml`). If that clone fails, the playbook fails.
- [ ] That dotfiles branch contains `links.conf`, and every source it lists exists. The `dotfiles` role asserts this and **fails** rather than leaving dangling symlinks. Check locally first with `./scripts/setup.sh --dry-run`.
- [ ] VM has **network** (NAT is fine). Ansible pulls Fedora packages, RPM Fusion, and GitHub. NVIDIA 580xx and Steam are skipped unless the VM has an NVIDIA GPU.
- [ ] Disk **≥ 40 GiB**, RAM **≥ 4 GiB**, **2+ vCPUs**. UEFI is a good match for a laptop later.
- [ ] The Fedora user you create is **`mathias`** and in **wheel** (`provision_user` in group_vars).

---

## 1. Download Fedora Everything 44

Network-install ISO (x86_64) from [Fedora miscellaneous downloads](https://fedoraproject.org/misc/), for example:

`Fedora-Everything-netinst-x86_64-44-1.7.iso`

Verify the checksum from the same directory as the ISO.

---

## 2. Create the VM and install Fedora

Use any hypervisor. Attach the ISO, give the VM a disk, NIC, and a console.

### Example: libvirt (`virt-install`)

```bash
virt-install \
  --name heimora \
  --memory 4096 \
  --vcpus 2 \
  --disk size=40,format=qcow2 \
  --os-variant fedora42 \
  --network network=default \
  --boot uefi \
  --graphics spice \
  --video virtio \
  --cdrom /path/to/Fedora-Everything-netinst-x86_64-44-1.7.iso
```

If `fedora42` is unknown: `osinfo-query os | grep -i fedora`.

Whatever the hypervisor, the guest needs a video device that gives Linux a DRM node — Sway will not start without one. `virtio` and plain `std`/VGA both do; check with `ls /dev/dri` (expect `card0`). On Proxmox the default display is fine.

### In Anaconda

1. Install Fedora as usual (language, disk, network).
2. Keep the package set **minimal** (no Workstation/GNOME desktop).
3. Create user **`mathias`**, administrator / wheel, with a password you choose.
4. Reboot, detach the ISO if the VM boots the installer again.

---

## 3. Trigger Heimora

Log in as `mathias` on the console. Confirm network (`ping -c1 github.com`). Then:

```bash
sudo hostnamctl hostname --static <hostname>
hostnamectl
sudo dnf update
sudo dnf install -y ansible-core git
sudo ansible-pull -U https://github.com/mathiaswouters/heimora.git \
  -C main \
  -d /opt/heimora \
  ansible/site.yml
```

This clones the repo to `/opt/heimora` and runs `ansible/site.yml` locally. It can take a long time.

Success: playbook finishes without a fatal error, `/opt/heimora` exists.

If it fails, fix the cause (GitHub URL, package name, RPM Fusion) and run the same `ansible-pull` command again, or:

```bash
sudo ansible-playbook /opt/heimora/ansible/site.yml -vv
```

---

## 4. What “done” looks like

1. Reboot or log out so **greetd** can take the TTY.
2. **tuigreet** logs you in and starts **Sway**, with **waybar** across the top.
3. User shell is **zsh** (`base` role), with the starship prompt and no startup errors.
4. Dotfiles under `/home/mathias` are owned by `mathias`, not root.
5. Every link resolves — this should print nothing:

```bash
find -L ~/.config ~/.zshrc ~/.gitconfig -maxdepth 2 -type l ! -exec test -e {} \; -print
```

6. `Super+Return` opens Ghostty, `Super+D` opens the wofi launcher.

Pipewire user units often do not enable during `ansible-pull` (no user D-Bus). After you are in Sway:

```bash
systemctl --user enable --now pipewire.socket wireplumber.service
```

---

## 5. Iterate without reinstalling

Fedora is already installed. Change Ansible, push, then:

```bash
cd /opt/heimora
sudo git pull
sudo ansible-playbook ansible/site.yml
```

Or `ansible-pull` again (pulls `main` and re-runs). Useful flags: `--tags sway`, `--tags apps`, `--check`, `-vv`.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| `ansible-pull` cannot clone | Repo private, wrong URL, or no network |
| Playbook fails in `dotfiles` | `dotfiles_repo` missing or `dotfiles_version` does not match the remote branch |
| `dotfiles` fails on "listed in links.conf but missing" | The manifest references a config that is not in the dotfiles repo. Add the file or drop the line — this check is what stops a broken `~/.zshrc` shipping silently |
| `dotfiles` fails on "Malformed line" | A `links.conf` line does not have exactly three whitespace-separated columns |
| New shell prints a `zoxide`/`starship` error | Those packages are missing; `.zshrc` initialises both unconditionally |
| Playbook fails enabling a COPR | No build for this Fedora version yet in `starship`, `lf` or `ghostty`'s COPR |
| Sway starts but Ghostty will not open | Known COPR/Fedora issue. `foot` is installed for exactly this case — start it, then debug |
| Boxes instead of glyphs in waybar | `jetbrains-mono-fonts` missing, or the font cache is stale (`fc-cache -f`) |
| `become` / sudo errors | Ran `ansible-pull` without sudo, or user not in wheel |
| `hosts` skipped / no hosts matched | Use the command above (`hosts: all`, connection local) |
| Missing RPM / dnf error | Package name wrong in `group_vars/all.yml`; RPM Fusion not ready on this Fedora |
| Playbook OK, boots to a TTY | Default target is still `multi-user.target`, so greetd (`WantedBy=graphical.target`) never starts. Check `systemctl get-default`; the `services` role now sets it to `graphical.target` |
| Boot appears to hang on GRUB's `Booting 'Fedora Linux …'` line, no login prompt | Almost never a real hang. greetd is `Conflicts=getty@tty1.service`, so if greetd fails to start it takes the getty down with it and nothing redraws the console — leaving GRUB's last message frozen on screen. Fedora boots `rhgb quiet` and a minimal install has no plymouth, so there is nothing else to overwrite it. See "Recovering a machine with no login prompt" below |
| greetd fails with `configured default session user 'greeter' not found` | The Fedora `greetd` package does not create the `greeter` account that `/etc/greetd/config.toml` names. The `services` role now creates it (system user, home `/var/lib/greetd`, in `video` and `input`) |
| Playbook OK, still no GUI | `systemctl status greetd`; reboot once |
| Sway but no audio | Enable pipewire user units after first graphical login |
| Dotfiles owned by root | Dotfiles role must use `become_user: mathias` (current `site.yml` does) |

### Recovering a machine with no login prompt

Because greetd owns VT1 and stops the getty there, a broken greetd leaves no way in on the default VT. In order of effort:

1. `Ctrl+Alt+F3` — greetd only claims VT1, so another VT still gives a getty.
2. SSH in. Fedora enables `sshd` and firewalld's default zone permits port 22.
3. Boot once without greetd: hold `Esc`/`Shift` for the GRUB menu, press `e`, and on the `linux` line delete `rhgb quiet` and append `systemd.unit=multi-user.target`, then `Ctrl+X`. Dropping `quiet` shows whether the kernel is genuinely stuck; `multi-user.target` keeps greetd out of the way. Neither is written to disk.

Then read the actual error — `journalctl -b -1 -u greetd` covers the failed boot rather than the current one:

```bash
systemctl status greetd
journalctl -b -1 -u greetd --no-pager
ls -l /dev/dri          # Sway needs a DRM node; empty means the VM has no usable video device
systemctl get-default
```

The `bootloader` role already drops `rhgb` and `quiet` from GRUB and the Boot Loader Spec entries, so a failed boot prints kernel messages instead of freezing on GRUB's last line. Tune timeout, theme, and extra args in `ansible/group_vars/all.yml`.

---

## 6. After the VM works

Same two commands on a laptop after a minimal Everything install. Add packages in `ansible/group_vars/all.yml` (see `APPS-INVENTORY.md`); re-run the playbook instead of rebuilding an image.
