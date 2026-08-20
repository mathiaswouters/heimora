# Heimora — first VM deployment

End-to-end path from this repo to a running Fedora 44 VM: Kickstart installs a minimal OS, first boot clones Heimora, Ansible installs Sway and your apps.

Do this in a VM before any real machine. Kickstart **wipes the pinned disk**.

```
Fedora Everything ISO
        │  inst.ks=…/kickstart/heimora.ks
        ▼
Anaconda (unattended, text mode)
        │  reboot
        ▼
First boot: first-boot-provision.service
        │  git clone → /opt/heimora
        │  ansible-playbook site.yml
        ▼
greetd (tuigreet) → Sway
```

Two layers:

| Layer | What runs | What it does |
|-------|-----------|----------------|
| OS | Anaconda + `kickstart/heimora.ks` | Disk, user `mathias`, network, `@core` + git/ansible |
| Environment | `ansible/site.yml` on first boot | RPM Fusion, zsh, Sway, apps, dotfiles, greetd |

---

## 0. Checklist before you create the VM

- [ ] `mathiaswouters/heimora` is on GitHub, **public**, default branch **`main`**, with this Kickstart and `ansible/` committed. First boot clones `https://github.com/mathiaswouters/heimora.git`.
- [ ] `https://github.com/mathiaswouters/dotfiles.git` exists and is cloneable (see `ansible/group_vars/all.yml`). If the playbook cannot clone it, first-boot Ansible fails.
- [ ] Kickstart disk name matches the VM (see step 1). Committed file currently uses `nvme0n1` (laptop). A typical KVM/QEMU disk is **`vda`**. VirtualBox SATA is often **`sda`**.
- [ ] VM has **network** (NAT is fine). Kickstart and Ansible both pull packages from Fedora mirrors and GitHub.
- [ ] VM is **UEFI** (OVMF / “UEFI firmware”). Match a modern laptop; BIOS + `--location=mbr` is not what this file assumes.
- [ ] Disk **≥ 40 GiB**, RAM **≥ 4 GiB**, **2+ vCPUs**. Everything netinst is small; the install and Ansible pull a lot over the network.
- [ ] You can use the **VM console**. `sshd` is not enabled. First login is local, empty password.

---

## 1. Point Kickstart at the VM disk

In `kickstart/heimora.ks`, replace every `nvme0n1` with the guest disk name. For libvirt/QEMU:

```kickstart
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=lvm
bootloader --timeout=5 --boot-drive=vda
```

Commit and push that change **before** you boot, if you load Kickstart from GitHub. If you inject a local copy instead (step 4), the file on disk is enough.

After the VM test, switch those lines back to `nvme0n1` (or keep a `heimora-vm.ks` copy) so a laptop install does not look for `vda`.

---

## 2. Download Fedora Everything 44

Network-install ISO (x86_64), from [Fedora miscellaneous downloads](https://fedoraproject.org/misc/) or a mirror, for example:

`Fedora-Everything-netinst-x86_64-44-1.7.iso`

Verify the checksum from the same directory as the ISO. You do not need the full Everything DVD; netinst plus `url=` in Kickstart is enough.

---

## 3. Create the VM

Use any hypervisor. Requirements: UEFI, one virtual disk, NIC with DHCP, ISO attached, console.

### Example: libvirt (`virt-install`)

`--location` plus `inst.ks=` is more reliable than attaching the ISO as a CD and hoping GRUB extra args stick.

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
  --location /path/to/Fedora-Everything-netinst-x86_64-44-1.7.iso \
  --extra-args "inst.ks=https://raw.githubusercontent.com/mathiaswouters/heimora/main/kickstart/heimora.ks inst.text"
```

If `fedora42` is unknown, `osinfo-query os | grep -i fedora` and pick the newest Fedora variant you have.

### Example: virt-manager GUI

1. Create a VM, firmware **UEFI**, disk ≥ 40 GiB, attach the Everything ISO.
2. Boot once into the Fedora installer menu (do not start a graphical install yet).
3. Highlight **Install Fedora**, press `e`, append to the linux line:

   ```
   inst.ks=https://raw.githubusercontent.com/mathiaswouters/heimora/main/kickstart/heimora.ks inst.text
   ```

4. Boot with Ctrl-X (or whatever the editor shows).

### Kickstart not on GitHub yet

Serve the file from the host and point `inst.ks` at it, for example:

```text
inst.ks=http://192.168.122.1:8000/heimora.ks inst.text
```

From the repo: `python3 -m http.server 8000 --directory kickstart`. The guest must reach that IP.

You can also inject the file with virt-install `--initrd-inject=kickstart/heimora.ks` and `inst.ks=file:/heimora.ks`.

---

## 4. Watch Anaconda

Text-mode Kickstart should not ask questions if the disk name, network, and `url=` repo are valid.

- Wrong disk (`nvme0n1` in a `vda` VM) → storage error; install stops.
- No network → cannot fetch packages from `download.fedoraproject.org`.
- `%post` failure → install fails (`--erroronfail`). Check `/var/log/ks-post.log` from a live/rescue boot if needed.

When Anaconda finishes, Kickstart issues `reboot`. Remove or unmount the ISO if the VM boots the installer again.

---

## 5. First real boot (console)

You land on a **text login**, not greetd yet. Ansible is probably still running.

1. Login: user **`mathias`**, **empty password**.
2. Set a password immediately:

   ```bash
   passwd
   ```

3. Follow provisioning (this can take a long time: RPM Fusion, Sway, apps):

   ```bash
   journalctl -u first-boot-provision.service -f
   ```

Success looks like:

- Clone of `heimora` into `/opt/heimora`
- `ansible-playbook` finishing without a fatal error
- `/etc/first-boot-provision.done` exists

If the unit failed, it will run again on the next reboot (`ConditionPathExists=!/etc/first-boot-provision.done`). Fix the cause, reboot, or run by hand:

```bash
sudo /usr/local/sbin/heimora-first-boot.sh
```

Useful logs:

| Where | What |
|-------|------|
| `journalctl -u first-boot-provision.service` | Clone + Ansible |
| `/var/log/ks-post.log` | Kickstart `%post` (unit file, empty password) |

---

## 6. What “done” looks like

After a successful playbook:

1. Reboot (or log out) so **greetd** can take the TTY.
2. **tuigreet** should ask you to log in, then start **Sway** (`tuigreet --time --cmd sway`).
3. Shell for `mathias` should be **zsh** (set in the `base` role).
4. Configs should be under `/home/mathias` from the dotfiles role, owned by `mathias`, not root.

Pipewire user units often do not enable on this first-boot run (no user D-Bus yet). After you are in Sway:

```bash
systemctl --user enable --now pipewire.socket wireplumber.service
```

---

## 7. Iterate without reinstalling

Kickstart is one-shot. After the VM exists, change Ansible and re-run:

```bash
cd /opt/heimora
sudo git pull
cd ansible
sudo ansible-playbook -i inventory.ini site.yml
```

Useful flags: `--tags sway`, `--tags apps`, `--check`, `-vv`.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Anaconda asks for a disk / fails storage | Disk still `nvme0n1`; guest is `vda` or `sda` |
| Installer menu, no unattended run | `inst.ks=` missing or URL 404 (repo/branch/path) |
| Hang fetching packages | No DHCP, or Fedora mirror/`url=` unreachable |
| Login rejected with empty password | PAM blocked empty passwords; boot a live ISO, chroot, `passwd mathias` |
| Unit loops / never creates `.done` | GitHub clone failed, or Ansible failed (dotfiles repo, missing RPM, RPM Fusion on a too-new Fedora) |
| Playbook OK, still no GUI | greetd not on VT1; `systemctl status greetd`; reboot once |
| Sway but no audio | Enable pipewire user units after first graphical login |
| Dotfiles owned by root | Playbook was run without `become_user` on the dotfiles role; current `site.yml` should set that |

---

## 8. After the VM works

- Revert Kickstart disk names to the laptop (`nvme0n1`) before a bare-metal run.
- Keep using the same first-boot flow: Everything ISO + `inst.ks=` + Ethernet (or any link with DHCP).
- Add packages in `ansible/group_vars/all.yml` (see `APPS-INVENTORY.md`); re-run the playbook instead of rebuilding the ISO.
