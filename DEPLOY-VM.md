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
- [ ] `https://github.com/mathiaswouters/dotfiles.git` is cloneable (`ansible/group_vars/all.yml`). If that clone fails, the playbook fails.
- [ ] VM has **network** (NAT is fine). Ansible pulls Fedora packages, RPM Fusion, and GitHub.
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
  --graphics virtio \
  --cdrom /path/to/Fedora-Everything-netinst-x86_64-44-1.7.iso
```

If `fedora42` is unknown: `osinfo-query os | grep -i fedora`.

### In Anaconda

1. Install Fedora as usual (language, disk, network).
2. Keep the package set **minimal** (no Workstation/GNOME desktop).
3. Create user **`mathias`**, administrator / wheel, with a password you choose.
4. Reboot, detach the ISO if the VM boots the installer again.

---

## 3. Trigger Heimora

Log in as `mathias` on the console. Confirm network (`ping -c1 github.com`). Then:

```bash
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
2. **tuigreet** logs you in and starts **Sway**.
3. User shell is **zsh** (`base` role).
4. Dotfiles under `/home/mathias` are owned by `mathias`, not root.

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
| `become` / sudo errors | Ran `ansible-pull` without sudo, or user not in wheel |
| `hosts` skipped / no hosts matched | Use the command above (`hosts: all`, connection local) |
| Missing RPM / dnf error | Package name wrong in `group_vars/all.yml`; RPM Fusion not ready on this Fedora |
| Playbook OK, boots to a TTY | Default target is still `multi-user.target`, so greetd (`WantedBy=graphical.target`) never starts. Check `systemctl get-default`; the `services` role now sets it to `graphical.target` |
| Playbook OK, still no GUI | `systemctl status greetd`; reboot once |
| Sway but no audio | Enable pipewire user units after first graphical login |
| Dotfiles owned by root | Dotfiles role must use `become_user: mathias` (current `site.yml` does) |

---

## 6. After the VM works

Same two commands on a laptop after a minimal Everything install. Add packages in `ansible/group_vars/all.yml` (see `APPS-INVENTORY.md`); re-run the playbook instead of rebuilding an image.
