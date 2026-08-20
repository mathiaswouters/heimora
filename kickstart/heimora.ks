#version=F44
# ---------------------------------------------------------------------------
# Kickstart file for a minimal, unattended Fedora install (Everything ISO)
# that hands off to Ansible for Sway + dotfiles provisioning on first boot.
#
# Boot the Everything ISO netinst with:
#   inst.ks=https://raw.githubusercontent.com/mathiaswouters/heimora/main/kickstart/heimora.ks
# or from a local USB / PXE server, e.g. inst.ks=hd:LABEL=KS:/heimora.ks
#
# Validate before use:  ksvalidator kickstart/heimora.ks
# ---------------------------------------------------------------------------

text

# --- Install source -----------------------------------------------------
# Everything ISO ships repo metadata on the media itself; url pulls fresh
# packages over the network instead so you're never stuck on stale mirrors.
url --url="https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/"
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f44&arch=x86_64

# --- Language / keyboard / timezone -------------------------------------
lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us'
timezone Europe/Brussels --utc

# --- Network ---------------------------------------------------------
network --bootproto=dhcp --device=link --activate --onboot=yes
network --hostname=heimora

# --- Root / user -------------------------------------------------------
# No password hashes in this file. Root stays locked. The admin user is
# created locked; %post then removes the password so a local console login
# works with an empty password. Set one immediately after first login:
#   passwd
# sshd is not enabled, so this is local-console only.
rootpw --lock
user --name=mathias --groups=wheel --lock --shell=/bin/bash

# --- Disk layout ---------------------------------------------------------
# Unencrypted LVM. LUKS is omitted on purpose: encrypting an already-installed
# root filesystem later is a migration, not a one-liner, so do it at install
# time on the next rebuild if you want it.
#
# Pin the install disk so extra NVMe/USB/SD devices are not wiped.
# Change nvme0n1 to sda (SATA) or vda (VM) to match the target machine.
ignoredisk --only-use=sata0
zerombr
clearpart --all --initlabel --drives=sata0
autopart --type=lvm
bootloader --timeout=5 --boot-drive=sata0

# --- Package selection ---------------------------------------------------
# Keep this genuinely minimal — Sway, apps, and everything else are Ansible's
# job. This just needs a bootable base with the tools to pull the playbook.
%packages --exclude-weakdeps
@core
NetworkManager
git
python3
ansible-core
sudo
firewalld
%end

# --- Services --------------------------------------------------------
# No sshd: the first-boot account has no password, so remote login stays off
# until you add a key or password yourself.
services --enabled=NetworkManager,firewalld
firstboot --disable

# --- Post-install: hand off to Ansible ------------------------------------
%post --erroronfail --log=/var/log/ks-post.log

# Local console can log in with an empty password; change it on first login.
passwd -d mathias
usermod -U mathias

mkdir -p /usr/local/sbin
cat > /usr/local/sbin/heimora-first-boot.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

REPO="https://github.com/mathiaswouters/heimora.git"
DEST="/opt/heimora"

if [[ ! -d "${DEST}/.git" ]]; then
  git clone "${REPO}" "${DEST}"
fi

cd "${DEST}/ansible"
/usr/bin/ansible-playbook -i inventory.ini site.yml
touch /etc/first-boot-provision.done
SCRIPT
chmod 0755 /usr/local/sbin/heimora-first-boot.sh

# Clone and playbook run on first real boot (full networking/DNS), not in the
# install chroot. The done-file is only created after a successful playbook.
cat > /etc/systemd/system/first-boot-provision.service << 'UNIT'
[Unit]
Description=First boot Heimora Ansible provisioning
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/first-boot-provision.done

[Service]
Type=oneshot
TimeoutStartSec=infinity
ExecStart=/usr/local/sbin/heimora-first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable NetworkManager-wait-online.service
systemctl enable first-boot-provision.service

%end

reboot
