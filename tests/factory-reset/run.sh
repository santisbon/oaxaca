# Boot A of scripts/factory-reset-test.sh: install the distro from the live session onto the blank
# target disk, the way the installer's settings lay it out, and leave the installed system ready for
# boot B. Sourced as root by the live session's boot test (packages/live's live-boot-test) from the
# disk labelled OAXTEST, after its own checks; $id is the distro's ID.
#
# Not the installer itself: Calamares has no unattended mode, so this script does what its exec
# sequence does (/etc/calamares/settings.conf) with the values its module files set, and runs the
# installer's own scripts where it has them. The layout is the encrypted btrfs one: an EFI System
# Partition, a 4 GiB ext4 /boot, and LUKS2 holding btrfs with the subvolumes of mount.conf (@,
# @home, @cache, @log, @swap) mounted with its options; fstab and crypttab as the fstab module
# writes them ("luks" in crypttab); the user "seller" with users.conf's groups; the installed
# system's layer of the medium (casper/filesystem.squashfs, without the live session's packages,
# as unpackfs.conf copies it); then filesystem-setup, <id>-apply-system, keep-previous-loader,
# GRUB on the EFI System Partition under the "ubuntu" ID, loader-fallback, sddm-last-user, the
# initramfs, and factory-snapshot, last, as shellprocess@factory runs it. Two departures, both for
# the test: the kernel command line sends the console to the serial port without the splash, so
# the host can type the disk encryption passphrase, and there is no hardware or drivers step
# (QEMU has neither an NVIDIA GPU nor a known model).
#
# After the install, the owner "uses" the machine (what a factory reset must remove): a file in
# their home, one in /etc and one in /usr/local, a saved network connection and a Timeshift
# snapshot. Then boot B's unit (stage.sh) goes in.
fr_pass=factorytest1
fr_disk=$(lsblk -dnpo NAME,SIZE,TYPE | awk '$2 == "40G" && $3 == "disk" { print $1; exit }')
echo "factory install: target disk ${fr_disk:-none}"
if [[ -z $fr_disk ]]; then echo "factory install: FAILED (no 40 GiB disk)"; return 0; fi
fr_log=/tmp/factory-install.log
fr_step() { echo "factory install: $1"; }
fr_fail() { echo "factory install: FAILED at $1"; tail -n 15 "$fr_log" | sed 's/^/factory install log: /'; }

fr_install() {
  set -e
  printf 'label: gpt\nsize=512MiB, type=U, name=EFI\nsize=4GiB, type=L, name=oaxaca_boot\ntype=L, name=oaxaca_root\n' | sfdisk -q "$fr_disk"
  udevadm settle
  local esp=${fr_disk}1 boot=${fr_disk}2 root=${fr_disk}3
  mkfs.vfat -F 32 -n EFI "$esp" >/dev/null
  mkfs.ext4 -q -F -L oaxaca_boot "$boot"
  printf '%s' "$fr_pass" | cryptsetup luksFormat --type luks2 --batch-mode "$root" -
  local uuid
  uuid=$(cryptsetup luksUUID "$root")
  printf '%s' "$fr_pass" | cryptsetup open "$root" "luks-$uuid" --key-file -
  local dev=/dev/mapper/luks-$uuid
  mkfs.btrfs -q -L oaxaca_root "$dev"
  mkdir -p /tmp/fr-top && mount "$dev" /tmp/fr-top
  local sv
  for sv in @ @home @cache @log @swap; do btrfs subvolume create "/tmp/fr-top/$sv" >/dev/null; done
  umount /tmp/fr-top

  T=/tmp/fr-target
  mkdir -p "$T"
  mount -o subvol=@,compress=zstd:1 "$dev" "$T"
  mkdir -p "$T/home" "$T/var/cache" "$T/var/log" "$T/swap" "$T/boot"
  mount -o subvol=@home,compress=zstd:1 "$dev" "$T/home"
  mount -o subvol=@cache,compress=zstd:1 "$dev" "$T/var/cache"
  mount -o subvol=@log,compress=zstd:1 "$dev" "$T/var/log"
  mount -o subvol=@swap,noatime "$dev" "$T/swap"
  mount "$boot" "$T/boot"
  mkdir -p "$T/boot/efi" && mount -o umask=0077 "$esp" "$T/boot/efi"
  fr_step "partitions and subvolumes made"

  unsquashfs -q -f -d "$T" /cdrom/casper/filesystem.squashfs >/dev/null
  fr_step "image unpacked"
  btrfs filesystem mkswapfile --size 1g "$T/swap/swapfile" >/dev/null

  local fs_uuid boot_uuid esp_uuid
  fs_uuid=$(blkid -s UUID -o value "$dev")
  boot_uuid=$(blkid -s UUID -o value "$boot")
  esp_uuid=$(blkid -s UUID -o value "$esp")
  cat > "$T/etc/fstab" <<FSTAB
UUID=$fs_uuid / btrfs subvol=/@,defaults,compress=zstd:1 0 0
UUID=$fs_uuid /home btrfs subvol=/@home,defaults,compress=zstd:1 0 0
UUID=$fs_uuid /var/cache btrfs subvol=/@cache,defaults,compress=zstd:1 0 0
UUID=$fs_uuid /var/log btrfs subvol=/@log,defaults,compress=zstd:1 0 0
UUID=$fs_uuid /swap btrfs subvol=/@swap,defaults,noatime 0 0
UUID=$boot_uuid /boot ext4 defaults 0 2
UUID=$esp_uuid /boot/efi vfat defaults,umask=0077 0 2
/swap/swapfile swap swap defaults 0 0
FSTAB
  printf 'luks-%s UUID=%s none luks\n' "$uuid" "$uuid" > "$T/etc/crypttab"
  rm -f "$T/etc/machine-id"
  systemd-machine-id-setup --root="$T" >/dev/null
  echo resetfrom > "$T/etc/hostname"
  printf 'XKBMODEL="pc105"\nXKBLAYOUT="us"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' > "$T/etc/default/keyboard"
  # The serial console for the host, without the splash (see the header).
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/; s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="console=tty1 console=ttyS0,115200"/; s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$T/etc/default/grub"

  # Everything that runs inside the target, in a mount namespace of its own.
  T="$T" id="$id" unshare --mount --propagation private bash -euo pipefail -c '
    mount --rbind /dev "$T/dev"; mount -t proc proc "$T/proc"; mount --rbind /sys "$T/sys"
    mount -t tmpfs tmpfs "$T/run"; mkdir -p "$T/run/systemd/resolve" "$T/cdrom"
    mount --bind /run/systemd/resolve "$T/run/systemd/resolve"; mount --bind /cdrom "$T/cdrom"
    tgt() { chroot "$T" "$@"; }
    tgt useradd -m -G adm,cdrom,dip,lpadmin,plugdev,sudo,video -s /bin/bash -c Seller seller
    printf "seller:%s\n" sellerpass1 | tgt chpasswd
    /usr/libexec/$id/filesystem-setup "$T"
    tgt env OMARCHY_LOG_TO_STDOUT=1 $id-apply-system --install-user seller --first-install
    /usr/libexec/$id/keep-previous-loader "$T"
    tgt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --uefi-secure-boot
    tgt update-grub
    /usr/libexec/$id/loader-fallback "$T"
    /usr/libexec/$id/sddm-last-user "$T" seller
    tgt update-initramfs -u -k all
  '
  fr_step "installed"
  /usr/libexec/$id/factory-snapshot "$T"
  fr_step "factory snapshot step done"

  # The owner uses the machine.
  echo "the seller's own file" > "$T/home/seller/secret.txt"
  chroot "$T" chown seller:seller /home/seller/secret.txt
  echo drift > "$T/etc/seller-drift"
  printf '#!/bin/sh\necho seller\n' > "$T/usr/local/bin/seller-tool"; chmod +x "$T/usr/local/bin/seller-tool"
  printf '[connection]\nid=seller-wifi\ntype=wifi\n' > "$T/etc/NetworkManager/system-connections/seller-wifi.nmconnection"
  chmod 600 "$T/etc/NetworkManager/system-connections/seller-wifi.nmconnection"
  mount "$dev" /tmp/fr-top
  mkdir -p /tmp/fr-top/timeshift-btrfs/snapshots/2026-10-17_00-00-00
  btrfs subvolume snapshot /tmp/fr-top/@ /tmp/fr-top/timeshift-btrfs/snapshots/2026-10-17_00-00-00/@ >/dev/null
  echo "factory snapshot: $([ -d /tmp/fr-top/@factory ] && echo present || echo missing) ro=$(btrfs property get -ts /tmp/fr-top/@factory ro 2>/dev/null | cut -d= -f2)"
  echo "factory boot copy in running root: $([ -e "$T/var/lib/$id/factory" ] && echo yes || echo no)"
  echo "factory boot copy in snapshot: $(ls /tmp/fr-top/@factory/var/lib/$id/factory/boot 2>/dev/null | grep -c '^vmlinuz-')"
  echo "factory users: $(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' /tmp/fr-top/@factory/etc/passwd | paste -sd' ')"
  umount /tmp/fr-top

  # Boot B: stage.sh runs the reset with gum answered from a file (the gum stand-in).
  install -d "$T/usr/local/lib/factory-test"
  install -m 0755 /run/oaxtest/gum /run/oaxtest/stage.sh /run/oaxtest/check.sh "$T/usr/local/lib/factory-test/"
  cat > "$T/etc/systemd/system/factory-test-stage.service" <<UNIT
[Unit]
Description=factory reset test: boot B, run the reset
After=multi-user.target

[Service]
Type=oneshot
Environment=id=$id
ExecStart=/usr/local/lib/factory-test/stage.sh
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyS0

[Install]
WantedBy=multi-user.target
UNIT
  ln -s /etc/systemd/system/factory-test-stage.service "$T/etc/systemd/system/multi-user.target.wants/factory-test-stage.service"
  # No login prompt on the serial port: a getty there hangs up the test's output (boot B's
  # first run lost the reset's last lines to it).
  ln -sf /dev/null "$T/etc/systemd/system/serial-getty@ttyS0.service"

  umount -R "$T"
  cryptsetup close "luks-$uuid"
  fr_step "done"
}
# Its own statement, not the left side of && or ||, where bash would ignore the set -e inside.
( fr_install ) >"$fr_log" 2>&1
fr_rc=$?
grep -E '^factory (install|snapshot|boot|users)' "$fr_log"
(( fr_rc == 0 )) || fr_fail "the install, exit $fr_rc"
