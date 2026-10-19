# A driven check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/hardware make iso-test.
# Sourced by the guest's live-boot-test at its end (helpers: as_user, shot, $uid, $id). The host
# boots QEMU with the firmware strings in ./smbios (vendor LENOVO, model "Legion Pro 7
# 16IAX10H"), so the guest's /sys/class/dmi/id names the Legion laptop.
#
# The check: the installed system's layer (casper's lower squashfs) is copied onto the
# target disk's 25 GiB partition as a stand-in for an installed system, the mounts Calamares's
# mount step makes are made (proc, sys, dev, a fresh /run, /cdrom), the network is turned off,
# and the installer's hardware step runs against that root exactly as shellprocess@hardware runs
# it. Expected: the model is recognized, apt reads only the medium's pool, and <id>-hw-legion
# and /etc/<id>/gpu are installed (docs/7, choice 41); the packages that serve every machine
# (fwupd, fwupd-signed, Intel's VA-API driver, the backlight hide) are in the image already
# (choice 44).
echo "drive: dmi: $(cat /sys/class/dmi/id/sys_vendor) / $(cat /sys/class/dmi/id/product_version)"
t=/mnt/hwtarget
part=$(readlink -f /dev/disk/by-label/existing)
mkfs.ext4 -q -F -L hwtarget "$part"
mkdir -p $t && mount "$part" $t
start=$(date +%s)
# casper's lower layer, the installed system's: casper moves its first squashfs mount, the
# medium's filesystem.squashfs, to /rofs (the live layer above it is not in view).
lower=/rofs
echo "drive: live root's lower layer: $lower"
rsync -aHAX "$lower/" $t/
echo "drive: copied the live root in $(( $(date +%s) - start )) s"
mount -t proc proc $t/proc; mount -t sysfs sys $t/sys; mount --bind /dev $t/dev
mount -t tmpfs tmpfs $t/run; mkdir -p $t/cdrom; mount --bind /cdrom $t/cdrom
for dev in $(ls /sys/class/net | grep -v '^lo$'); do ip link set "$dev" down; done
echo "drive: network: $(ip -brief link | grep -v '^lo' | awk '{print $1"="$2}' | paste -sd' ')"
/usr/libexec/$id/hardware-install $t; rc=$?
echo "drive: hardware-install exit: $rc"
sed 's/^/drive log: /' $t/var/log/$id/hardware-install.log | grep -E 'hardware-install|Setting up|^drive log: E:|Err:|Unable' | head -40
for p in $id-hw-legion $id-hybrid-backlight intel-media-va-driver-non-free fwupd fwupd-signed; do
  echo "drive: installed $p: $(chroot $t dpkg-query -W -f='${Status} ${Version}' $p 2>/dev/null || echo none)"
done
echo "drive: gpu file: $(grep -v '^#' $t/etc/$id/gpu 2>/dev/null || echo missing)"
echo "drive: target apt sources untouched: $(ls $t/etc/apt/sources.list.d | paste -sd' ')"
umount $t/cdrom $t/run $t/dev $t/sys $t/proc; umount $t
