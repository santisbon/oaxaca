#!/usr/bin/env bash
# iso-create.sh: build the live installation ISO from the desktop and live root filesystem
# tarballs.
#
# Anatomy: the inputs are two profiles of scripts/rootfs-create.sh from the same build:
# build/rootfs/<id>-<version>-amd64-desktop.tar, the system an installation puts on the disk, and
# build/rootfs/<id>-<version>-amd64-live.tar, the same desktop plus casper, the live-session
# package and the installer. This script turns them into what a casper live medium needs and one
# thing UEFI firmware needs:
#   casper/filesystem.squashfs   the desktop tarball as a squashfs, made by mksquashfs reading
#                                the tar on standard input (no extraction, no root; file
#                                ownership comes from the tar). The installer copies this layer
#                                alone onto the disk (unpackfs.conf), so nothing of the live
#                                session reaches an installed system (docs/7, choice 55).
#   casper/filesystem.live.squashfs  the live layer: what the live tarball has on top of the
#                                desktop one, written by scripts/layer-diff.py. The boot option
#                                layerfs-path=filesystem.live.squashfs makes casper mount
#                                filesystem.squashfs and this layer above it; without that
#                                option casper would stack every *.squashfs in name order and
#                                put the live layer underneath.
#   casper/vmlinuz, casper/initrd  the kernel and the initramfs from the live tarball; the
#                                initramfs carries casper's scripts because the live profile
#                                rebuilt it after installing casper
#   boot/grub/grub.cfg           the menu: one entry booting the kernel with boot=casper
#   an EFI System Partition image (FAT) holding Ubuntu's Microsoft-signed shim as
#                                EFI/boot/bootx64.efi, Ubuntu's Canonical-signed CD GRUB
#                                (gcdx64.efi.signed, which searches the medium for
#                                /.disk/info and reads /boot/grub/grub.cfg there) as
#                                EFI/boot/grubx64.efi, and MokManager; all three taken from
#                                the tarball's shim-signed and grub-efi-amd64-signed
# xorriso then writes the ISO 9660 image with that FAT image appended as a GPT partition of
# type EFI System, the layout a UEFI firmware boots from a DVD or a USB stick. The ISO boots
# with Secure Boot on because shim, GRUB and the kernel are Ubuntu's signed ones (policy,
# "Secure Boot supported, never required"). UEFI only: no BIOS boot record is written.
#
# A second ISO, <name>-test.iso, is the same image with a grub.cfg whose default entry adds
# the serial console and the kernel parameter <id>.boottest that wakes the live package's
# boot test unit; xorriso copies the first ISO and replaces that one file, so the squashfs
# is compressed once. scripts/iso-boot-test.sh boots the test ISO.
#
# Usage: scripts/iso-create.sh        (make iso; make rootfs PROFILE=desktop and make rootfs first)
# Needs: squashfs-tools (mksquashfs 4.5 or newer for -tar), xorriso, dosfstools, mtools.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"

arch=amd64
tarball="$here/build/rootfs/$DISTRO_ID-$BASE_VERSION-$arch-live.tar"
manifest="${tarball%.tar}.manifest"
desktop="$here/build/rootfs/$DISTRO_ID-$BASE_VERSION-$arch-desktop.tar"
desktop_manifest="${desktop%.tar}.manifest"
[[ -f $tarball ]] || { echo "no live root filesystem at $tarball: run 'make rootfs PROFILE=live' first" >&2; exit 1; }
[[ -f $desktop ]] || { echo "no desktop root filesystem at $desktop: run 'make rootfs PROFILE=desktop' first" >&2; exit 1; }
# The two tarballs must come from the same packages: every package both have at the same version.
# A desktop tarball left over from an older build would otherwise become the installed system
# under a live session built from newer packages. A package only one of them has is no drift:
# with the live packages in the same install, apt satisfies plymouth's theme dependency with
# plymouth-theme-hamara instead of the desktop's plymouth-theme-ubuntu-text.
# join needs its inputs in the order its own comparison uses; under a language locale such as
# en_US.UTF-8, sort orders "cpp-15<tab>..." before "cpp<tab>...", and join stopped with "input is
# not in sorted order" (2026-10-22). Both run in the C locale, sorting on the package name alone.
drift=$(LC_ALL=C join -t $'\t' <(LC_ALL=C sort -t $'\t' -k1,1 "$desktop_manifest") <(LC_ALL=C sort -t $'\t' -k1,1 "$manifest") -o 0,1.2,2.2 | awk -F'\t' '$2 != $3')
if [[ -n $drift ]]; then
  echo "the desktop and live root filesystems differ (package, desktop version, live version):" >&2
  echo "$drift" | head -20 >&2
  echo "rebuild both: make rootfs PROFILE=desktop && make rootfs" >&2
  exit 1
fi
for t in mksquashfs xorriso mkfs.vfat mmd mcopy; do
  command -v "$t" >/dev/null || { echo "$t is not installed (squashfs-tools, xorriso, dosfstools, mtools)" >&2; exit 1; }
done

work="$here/build/iso"
tree="$work/tree"
# The ISO's version: its build time in UTC to the minute, unique per release and sorting in order.
# It goes into .disk/info and into build/iso/iso-version, which scripts/iso-publish.sh reads to name
# the uploaded ISO (docs/7, choice 59).
stamp=$(date -u +%Y%m%d.%H%M)
iso="$work/$DISTRO_ID-$BASE_VERSION-$arch.iso"
test_iso="$work/$DISTRO_ID-$BASE_VERSION-$arch-test.iso"
label="$DISTRO_NAME $BASE_VERSION $arch"
rm -rf "$tree" "$work/efi"
mkdir -p "$tree/casper" "$tree/boot/grub" "$tree/.disk" "$work/efi/EFI/boot"

echo "== kernel and initramfs from $tarball"
kver=$(tar -tf "$tarball" | sed -n 's|^\./boot/vmlinuz-||p' | sort -V | tail -1)
[[ -n $kver ]] || { echo "no kernel in the tarball" >&2; exit 1; }
tar -xOf "$tarball" "./boot/vmlinuz-$kver" > "$tree/casper/vmlinuz"
tar -xOf "$tarball" "./boot/initrd.img-$kver" > "$tree/casper/initrd"
echo "   kernel $kver, initrd $(du -h "$tree/casper/initrd" | cut -f1)"

echo "== squashfs: the installed system's layer, from $desktop"
# mmdebstrap's tarball has the right entry for "./" (drwxr-xr-x 0/0), but mksquashfs -tar skips
# it ("Empty tar filename after skipping leading /, ./, or ../, ignoring") and makes the root
# directory up: mode 0777, owned by the user running this script (mksquashfs 4.7.5 -help-all:
# "Default root mode is ugo=rwx or 0777"). Calamares copies the squashfs onto the disk, so every installed
# system got a / owned by uid 1000 and writable by everyone, and systemd-tmpfiles then refused to
# create anything under it ("Detected unsafe path transition / (owned by <user>) -> /var",
# tpm-udev's postinst, 2026-10-14). The root directory is set to root:root 0755 here, and the
# build stops if the result says otherwise.
# The live layer's root directory sets the stacked root's attributes as well (the uppermost layer
# holding a directory does), so both layers get the same options.
squash() {
  mksquashfs - "$1" -tar -comp zstd -Xcompression-level 15 -noappend -quiet \
    -root-mode 0755 -root-uid 0 -root-gid 0
  # sed reads the whole listing; head would close the pipe early and pipefail would stop the build.
  local root_entry
  root_entry=$(unsquashfs -lln -d / "$1" 2>/dev/null | sed -n 1p)
  if [[ $root_entry != "drwxr-xr-x 0/0 "* ]]; then
    echo "!! the root directory of $1 is not root:root 0755: $root_entry" >&2; exit 1
  fi
  echo "   root directory: ${root_entry%% *} 0/0, $(du -h "$1" | cut -f1)"
}
squash "$tree/casper/filesystem.squashfs" < "$desktop"
cp "$desktop_manifest" "$tree/casper/filesystem.manifest"
tar -tvf "$desktop" | awk '{s+=$3} END {print s}' > "$tree/casper/filesystem.size"
echo "== squashfs: the live layer, $tarball on top of the desktop"
python3 -I "$here/scripts/layer-diff.py" "$desktop" "$tarball" | squash "$tree/casper/filesystem.live.squashfs"
cp "$manifest" "$tree/casper/filesystem.live.manifest"

printf '%s %s "%s" - Release %s (%s)\n' "$DISTRO_NAME" "$BASE_VERSION" "$BASE_SERIES" "$arch" "$stamp" > "$tree/.disk/info"
printf '%s\n' "$stamp" > "$work/iso-version"

# The NVIDIA driver's packages, so the installer's drivers step works without a network
# (scripts/driver-pool.sh, docs/7 choice 20). DRIVER_POOL=0 leaves them out.
# The pool is resolved against the desktop tarball, the system the installer's steps install into.
if [[ ${DRIVER_POOL:-1} != 0 ]]; then
  echo "== driver pool"
  "$here/scripts/driver-pool.sh" "$desktop" "$tree/pool"
fi

# The kernel command line: casper's own parameters (username=, hostname= are read by its
# initramfs script, the live user's full name stays casper.conf's "Live session user").
cmdline="boot=casper layerfs-path=filesystem.live.squashfs username=$DISTRO_ID hostname=$DISTRO_ID quiet splash"
# The test entry keeps "splash" so that Plymouth runs the distro's script theme in QEMU as it
# does on hardware (a crash in that theme on the Legion laptop, 2026-10-11, went unseen while
# the test entry had no splash), and adds plymouth.debug so the guest test can read Plymouth's
# log (/var/log/plymouth-debug.log) for the console viewer decision. No "quiet": the serial
# log is the test's record.
# <id>.gpu=boot: the live package's GPU environment generator then sets AQ_DRM_DEVICES even
# on QEMU's single GPU, so the test exercises Hyprland's explicit-device path, the one a
# dual-GPU laptop takes in the live session (docs/7, choice 17).
test_cmdline="boot=casper layerfs-path=filesystem.live.squashfs username=$DISTRO_ID hostname=$DISTRO_ID splash plymouth.debug console=ttyS0 systemd.mask=serial-getty@ttyS0.service $DISTRO_ID.boottest $DISTRO_ID.gpu=boot"
grub_cfg() {
  local default_cmdline=$1 timeout=$2
  cat <<GRUB
set default=0
set timeout=$timeout
menuentry "Try or install $DISTRO_NAME $BASE_VERSION" {
    linux /casper/vmlinuz $default_cmdline ---
    initrd /casper/initrd
}
menuentry "$DISTRO_NAME $BASE_VERSION (safe graphics)" {
    linux /casper/vmlinuz $cmdline nomodeset ---
    initrd /casper/initrd
}
GRUB
}
grub_cfg "$cmdline" 5 > "$tree/boot/grub/grub.cfg"

# md5sum.txt at the root of the medium: one "<md5>  ./path" line per file, the layout of
# Ubuntu's own ISOs. casper's casper-md5check.service (multi-user.target, idle I/O) runs
# "casper-md5check /cdrom /cdrom/md5sum.txt" and fails when the file is missing, which is
# what the first boot of the stick on the Legion laptop showed (2026-10-11).
(cd "$tree" && find . -type f ! -name md5sum.txt -print0 | LC_ALL=C sort -z | xargs -0 md5sum > md5sum.txt)
echo "   md5sum.txt: $(wc -l < "$tree/md5sum.txt") files"

echo "== EFI System Partition image (shim, CD GRUB, MokManager from the tarball)"
tar -xOf "$tarball" ./usr/lib/shim/shimx64.efi.signed.latest > "$work/efi/EFI/boot/bootx64.efi"
tar -xOf "$tarball" ./usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed > "$work/efi/EFI/boot/grubx64.efi"
tar -xOf "$tarball" ./usr/lib/shim/mmx64.efi > "$work/efi/EFI/boot/mmx64.efi"
efi="$work/efi.img"
size_kb=$(( ($(du -sk "$work/efi" | cut -f1) + 1024) / 1024 * 1024 + 1024 ))
rm -f "$efi"
mkfs.vfat -C -n EFIBOOT "$efi" "$size_kb" >/dev/null
mmd -i "$efi" ::/EFI ::/EFI/boot
mcopy -i "$efi" "$work/efi/EFI/boot/bootx64.efi" "$work/efi/EFI/boot/grubx64.efi" "$work/efi/EFI/boot/mmx64.efi" ::/EFI/boot/

echo "== ISO"
rm -f "$iso" "$test_iso"
xorriso -as mkisofs -r -V "$label" -J -joliet-long -l -iso-level 3 \
  -o "$iso" \
  -append_partition 2 0xef "$efi" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot \
  "$tree" 2>&1 | grep -E 'ISO image produced|xorriso : FAILURE|xorriso : SORRY' || true
[[ -f $iso ]] || { echo "xorriso produced no image" >&2; exit 1; }

echo "== test ISO (same image, grub.cfg with the boot test entry as the default)"
grub_cfg "$test_cmdline" 0 > "$work/grub-test.cfg"
# The test image's md5sum.txt names the test grub.cfg, so casper's check passes there too.
sed "s|^[0-9a-f]*  ./boot/grub/grub.cfg\$|$(md5sum < "$work/grub-test.cfg" | cut -d' ' -f1)  ./boot/grub/grub.cfg|" "$tree/md5sum.txt" > "$work/md5sum-test.txt"
xorriso -indev "$iso" -outdev "$test_iso" -boot_image any replay \
  -map "$work/grub-test.cfg" /boot/grub/grub.cfg -map "$work/md5sum-test.txt" /md5sum.txt -commit 2>&1 | grep -E 'FAILURE|SORRY' || true
[[ -f $test_iso ]] || { echo "xorriso produced no test image" >&2; exit 1; }

echo "done: $(du -h "$iso" | cut -f1) $iso"
echo "      $(du -h "$test_iso" | cut -f1) $test_iso"
