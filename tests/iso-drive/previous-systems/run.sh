# A driven check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/previous-systems make iso-test.
# Sourced by the guest's live-boot-test (as root). The host's target disk holds an EFI System
# Partition whose stub names a filesystem that no longer exists (as after a reinstall of this
# distro), a 25 GiB system os-prober recognizes, and a 1 GiB separate /boot of another
# Ubuntu-family system with a GRUB menu titled "Test Ubuntu GNU/Linux". keep-previous-loader runs
# against a fake target with that EFI System Partition mounted at boot/efi, the way the installer
# runs it, and must keep the separate /boot (found by its scan, not by the stub), exit 0, and
# write a GRUB script whose output grub-script-check accepts. A second run with the stub in the
# fallback form naming that /boot must keep it once, not twice.
fake=$(mktemp -d); mkdir -p "$fake/boot/efi" "$fake/etc"
esp=$(blkid -L ESP 2>/dev/null)
mount -o ro "$esp" "$fake/boot/efi"
/usr/libexec/$id/keep-previous-loader "$fake" > /tmp/kpl.out 2>&1; rc=$?
umount "$fake/boot/efi"
sed 's/^/drive kpl: /' /tmp/kpl.out | grep -v unshare
echo "drive: keep-previous-loader exit $rc"
if [[ -x $fake/etc/grub.d/45_${id}_previous ]]; then
  (cd "$fake/etc/grub.d" && menuentry_id_option=--id sh "./45_${id}_previous") > /tmp/kpl-menu.cfg
  echo "drive: entries: $(grep -c '^menuentry' /tmp/kpl-menu.cfg) [$(sed -n "s/^menuentry '\([^']*\)'.*/\1/p" /tmp/kpl-menu.cfg | paste -sd';')]"
  grub-script-check /tmp/kpl-menu.cfg && echo "drive: grub-script-check ok"
fi
# The fallback form, naming the separate /boot found above.
tb=$(blkid -L test_boot -s UUID -o value 2>/dev/null || blkid -s UUID -o value "$(blkid -L test_boot)")
mkdir -p /tmp/esp2/EFI/ubuntu "$fake/boot/efi"
printf "if search --no-floppy --fs-uuid --set=root 11111111-2222-3333-4444-555555555555; then\n    set prefix=(\$root)'/grub'\n    configfile \$prefix/grub.cfg\nfi\nsearch --no-floppy --fs-uuid --set=root %s\nset prefix=(\$root)'/grub'\nconfigfile \$prefix/grub.cfg\n" "$tb" > /tmp/esp2/EFI/ubuntu/grub.cfg
rm -rf "$fake/etc/grub.d"; mount --bind /tmp/esp2 "$fake/boot/efi"
/usr/libexec/$id/keep-previous-loader "$fake" > /tmp/kpl2.out 2>&1; rc2=$?
umount "$fake/boot/efi"
echo "drive: fallback form exit $rc2, entries $(grep -c '^menuentry' "$fake/etc/grub.d/45_${id}_previous" 2>/dev/null)"
rm -rf "$fake" /tmp/esp2
