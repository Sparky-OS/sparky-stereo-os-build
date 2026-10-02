#!/bin/sh
# Run once inside the development VM, after installing Sparky KDE:
#   sudo mount -t virtiofs sparky-os /mnt && sudo sh /mnt/vm/vm-setup.sh "$USER"
# SSH for the host's work, the shared folders mounted at every boot, and sudo
# without a password for the build user. That last one is for the development VM
# only: pack-iso removes /etc/sudoers.d/90-sparky-dev before packing.
set -e
U=${1:?usage: vm-setup.sh <user>}
DEBIAN_FRONTEND=noninteractive apt-get -y -q install openssh-server
mkdir -p /srv/sparky-os /srv/sparky-work
grep -q 'sparky-os ' /etc/fstab || cat >>/etc/fstab <<FSTAB
sparky-os /srv/sparky-os virtiofs defaults,nofail 0 0
sparky-work /srv/sparky-work virtiofs defaults,nofail 0 0
FSTAB
mount -a
H=$(getent passwd "$U" | cut -d: -f6)
install -d -m 700 -o "$U" -g "$U" "$H/.ssh"
grep -qsF "$(cat /srv/sparky-work/vm-ssh.pub)" "$H/.ssh/authorized_keys" ||
	cat /srv/sparky-work/vm-ssh.pub >>"$H/.ssh/authorized_keys"
chown "$U:$U" "$H/.ssh/authorized_keys"; chmod 600 "$H/.ssh/authorized_keys"
echo "$U ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-sparky-dev
chmod 440 /etc/sudoers.d/90-sparky-dev
systemctl enable --now ssh
echo "ready: the host reaches this VM with sparky-vm.sh ssh"
