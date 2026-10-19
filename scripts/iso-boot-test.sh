#!/usr/bin/env bash
# iso-boot-test.sh: boot the test ISO in QEMU under UEFI firmware and check the live session.
#
# Anatomy: QEMU boots build/iso/<id>-<version>-amd64-test.iso (scripts/iso-create.sh) with
# OVMF, the UEFI firmware Ubuntu's ovmf package ships. With SECURE_BOOT=on (the default) the
# firmware is OVMF_CODE_4M.secboot.fd with a copy of OVMF_VARS_4M.ms.fd, Microsoft's keys
# enrolled, so shim, GRUB and the kernel pass the same signature checks as on real hardware;
# with SECURE_BOOT=off it is the same firmware with OVMF_VARS_4M.fd, no keys enrolled. The policy asks
# for both runs. The test ISO's GRUB entry adds console=ttyS0 and <id>.boottest to the kernel
# command line, which wakes the live package's boot test unit in the guest; that unit prints
# one line per check on the serial console, which QEMU logs to a file, and powers off. This
# script waits for the end marker and compares the lines with what the live session must
# show: Secure Boot state as configured, casper, the live user with passwordless sudo, the
# session with the shell up, and the installer running with its window on screen.
#
# Usage: scripts/iso-boot-test.sh                 (make iso-test [SECURE_BOOT=on|off])
# Env:   SECURE_BOOT=on|off   QEMU_TIMEOUT=<s> (default 900)   QEMU_RENDERNODE=<path>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
id=$DISTRO_ID
arch=amd64
secure=${SECURE_BOOT:-on}
iso="$here/build/iso/$id-$BASE_VERSION-$arch-test.iso"
[[ -f $iso ]] || { echo "no test ISO at $iso: run 'make iso' first" >&2; exit 1; }
work="$here/build/iso/test-$secure"
rm -rf "$work"; mkdir -p "$work"
serial="$work/serial.log"

case $secure in
  on)  code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd; vars_src=/usr/share/OVMF/OVMF_VARS_4M.ms.fd ;;
  # off: the same Secure Boot capable firmware with the variable file that has no keys
  # enrolled, so the firmware reports Secure Boot disabled, as a laptop with the setting
  # turned off does. The plain OVMF_CODE_4M.fd has no Secure Boot support compiled in and
  # mokutil says "This system doesn't support Secure Boot" there, a different case.
  off) code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd; vars_src=/usr/share/OVMF/OVMF_VARS_4M.fd ;;
  *) echo "SECURE_BOOT must be on or off" >&2; exit 1 ;;
esac
[[ -f $code && -f $vars_src ]] || { echo "OVMF firmware missing under /usr/share/OVMF (package ovmf)" >&2; exit 1; }
cp "$vars_src" "$work/vars.fd"

# GPU as in rootfs-boot-test.sh: virgl through the host's render node when writable.
# The render node for virgl: QEMU_RENDERNODE, else the first /dev/dri/renderD* whose kernel
# driver is not nvidia (NVIDIA's EGL does not serve QEMU's egl-headless display; on 2026-10-11
# the nodes renumbered on this workstation and renderD128 became the NVIDIA GPU, so a fixed
# default failed with "egl: render node init failed").
rendernode=${QEMU_RENDERNODE:-}
if [[ -z $rendernode ]]; then
  for r in /dev/dri/renderD*; do
    drv=$(basename "$(readlink -f "/sys/class/drm/$(basename "$r")/device/driver" 2>/dev/null)" 2>/dev/null)
    [[ $drv == nvidia ]] && continue
    rendernode=$r; break
  done
  rendernode=${rendernode:-/dev/dri/renderD128}
fi
if [[ -w $rendernode ]]; then
  # 2560x1600, the Legion laptop's panel, so the installer's window is tested at the laptop's
  # logical size when the guest switches the monitor to scale 1.6 (docs/7, choice 22).
  gpu=(-device virtio-vga-gl,xres=2560,yres=1600 -display "egl-headless,rendernode=$rendernode")
  echo "== GPU: virtio-vga-gl with virgl through $rendernode"
else
  gpu=(-device virtio-vga -display none)
  echo "== GPU: virtio-vga without virgl; Mesa renders in software"
fi
accel=(); [[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)

# DRIVE=<directory>: an interactive check driven by a script. The directory's files go onto a small
# ext4 disk labelled OAXTEST, whose run.sh the guest test sources at its end (packages/live's
# live-boot-test), and a 60 GiB target disk (300 MiB EFI System Partition, 25 GiB ext4, the rest free) is
# attached for the installer's partition page. Used to reproduce installer bugs (docs/7, choice
# 26) without rebuilding the ISO for each change to the script.
drive_args=()
if [[ -n ${DRIVE:-} ]]; then
  [[ -f $DRIVE/run.sh ]] || { echo "DRIVE=$DRIVE has no run.sh" >&2; exit 1; }
  truncate -s 0 "$work/drive.img"; truncate -s 256M "$work/drive.img"
  mkfs.ext4 -q -F -L OAXTEST -d "$DRIVE" "$work/drive.img"
  truncate -s 0 "$work/target.img"; truncate -s 60G "$work/target.img"
  # An EFI System Partition first: on a UEFI machine Calamares disables Replace and Alongside
  # when it finds none ("System is EFI but there's no EFI system partition").
  # Then a 1 GiB separate /boot of another Ubuntu-family system (a GRUB menu at grub/grub.cfg,
  # what keep-previous-loader scans for), and on the EFI System Partition a stub naming a
  # filesystem that no longer exists, as after a reinstall (docs/7, choice 38).
  printf 'label: gpt\nsize=300MiB, type=U\nsize=25GiB, type=L\nsize=1GiB, type=L\n' | sfdisk -q "$work/target.img"
  truncate -s 300M "$work/target-esp.img"; mkfs.vfat -n ESP "$work/target-esp.img" >/dev/null
  mmd -i "$work/target-esp.img" ::/EFI ::/EFI/ubuntu
  printf "search.fs_uuid 11111111-2222-3333-4444-555555555555 root \nset prefix=(\$root)'/grub'\nconfigfile \$prefix/grub.cfg\n" > "$work/stub.cfg"
  mcopy -i "$work/target-esp.img" "$work/stub.cfg" ::/EFI/ubuntu/grub.cfg
  rm -rf "$work/target-p3"; mkdir -p "$work/target-p3/grub"
  printf "menuentry 'Test Ubuntu GNU/Linux' {\n\techo test\n}\n" > "$work/target-p3/grub/grub.cfg"
  truncate -s 1G "$work/target-p3.img"; mkfs.ext4 -q -F -L test_boot -d "$work/target-p3" "$work/target-p3.img"
  dd if="$work/target-esp.img" of="$work/target.img" bs=1M seek=1 conv=notrunc status=none; rm -f "$work/target-esp.img"
  # A system os-prober recognizes (its Linux test wants a dynamic loader under lib*/ and reads
  # /etc/os-release); Calamares offers "Replace a partition" only on a disk with one.
  rm -rf "$work/target-p1"; mkdir -p "$work/target-p1/etc" "$work/target-p1/lib64" "$work/target-p1/boot"
  printf 'NAME="Test Linux"\nID=testlinux\nPRETTY_NAME="Test Linux 1.0"\nVERSION_ID=1.0\n' > "$work/target-p1/etc/os-release"
  : > "$work/target-p1/lib64/ld-linux-x86-64.so.2"
  truncate -s 25G "$work/target-p1.img"; mkfs.ext4 -q -F -L existing -d "$work/target-p1" "$work/target-p1.img"
  dd if="$work/target-p1.img" of="$work/target.img" bs=1M seek=301 conv=notrunc,sparse status=none
  dd if="$work/target-p3.img" of="$work/target.img" bs=1M seek=$((301 + 25 * 1024)) conv=notrunc,sparse status=none; rm -f "$work/target-p3.img"
  rm -f "$work/target-p1.img"
  drive_args=(-drive "file=$work/target.img,format=raw,if=virtio" -drive "file=$work/drive.img,format=raw,if=virtio"
              -device qemu-xhci -device usb-tablet)
  # A file named smbios in the directory: its one line is QEMU's -smbios value, so the guest's
  # firmware strings (/sys/class/dmi/id) name another machine, such as the Legion laptop for the
  # installer's hardware step (docs/7, choice 41).
  if [[ -f $DRIVE/smbios ]]; then
    drive_args+=(-smbios "$(head -n 1 "$DRIVE/smbios")")
    echo "== DRIVE: SMBIOS $(head -n 1 "$DRIVE/smbios")"
  fi
  echo "== DRIVE: $DRIVE (run.sh), target disk 60 GiB"
fi

# Keystrokes for the guest: the guest prints "=== KEYS <qemu key> ..." on the serial console when
# it wants keys pressed (driving a test installer through its pages, docs/7 choice 24), and this
# watcher sends each through QEMU's monitor ("sendkey"), then writes "keys-sent <n>" to its log.
monitor="$work/monitor.sock"
rm -f "$monitor"
: > "$serial"
qmp="$work/qmp.sock"
rm -f "$qmp"
python3 -I - "$serial" "$monitor" "$qmp" > "$work/keys.log" 2>&1 <<'PYKEYS' &
import json, os, socket, sys, time
serial, sock_path, qmp_path = sys.argv[1], sys.argv[2], sys.argv[3]
for _ in range(600):
    if os.path.exists(sock_path):
        break
    time.sleep(1)
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(sock_path)
sock.settimeout(0.5)
# QMP for absolute pointer events (a USB tablet in the guest): "=== CLICK <x> <y>" in physical
# pixels of the 2560x1600 display, scaled to QEMU's 0..32767 axis range.
qmp = None
def qmp_cmd(obj):
    global qmp
    if qmp is None:
        qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        qmp.connect(qmp_path)
        qmp.settimeout(2)
        qmp.recv(65536)
        qmp.sendall(json.dumps({"execute": "qmp_capabilities"}).encode()); qmp.recv(65536)
    qmp.sendall(json.dumps(obj).encode())
    try:
        qmp.recv(65536)
    except socket.timeout:
        pass
def click(x, y):
    ax, ay = int(x * 32767 / 2560), int(y * 32767 / 1600)
    qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}}]}})
    time.sleep(0.3)
    for down in (True, False):
        qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
            {"type": "btn", "data": {"down": down, "button": "left"}}]}})
        time.sleep(0.15)
pos, n = 0, 0
while True:
    try:
        with open(serial, "rb") as f:
            f.seek(pos)
            data = f.read()
    except FileNotFoundError:
        data = b""
    if data:
        last_nl = data.rfind(b"\n")
        if last_nl >= 0:
            pos += last_nl + 1
            for line in data[: last_nl + 1].decode("utf-8", "replace").splitlines():
                line = line.strip("\r")
                if line.startswith("=== MOVE "):
                    parts = line.split()
                    ax, ay = int(float(parts[2]) * 32767 / 2560), int(float(parts[3]) * 32767 / 1600)
                    qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
                        {"type": "abs", "data": {"axis": "x", "value": ax}},
                        {"type": "abs", "data": {"axis": "y", "value": ay}}]}})
                    n += 1
                    print("move", n, parts[2], parts[3], flush=True)
                elif line.startswith("=== CLICK "):
                    parts = line.split()
                    click(float(parts[2]), float(parts[3]))
                    n += 1
                    print("click", n, parts[2], parts[3], flush=True)
                elif line.startswith("=== KEYS "):
                    for key in line.split()[2:]:
                        sock.sendall(("sendkey %s\n" % key).encode())
                        time.sleep(0.3)
                    n += 1
                    print("keys-sent", n, line[9:], flush=True)
                elif line.startswith("=== LIVE-TEST END"):
                    sys.exit(0)
    try:
        sock.recv(4096)
    except (socket.timeout, OSError):
        pass
    time.sleep(0.5)
PYKEYS
keys_pid=$!

echo "== booting $iso in QEMU (Secure Boot $secure, serial log: $serial, timeout ${QEMU_TIMEOUT:-900}s)"
timeout --foreground "${QEMU_TIMEOUT:-900}" qemu-system-x86_64 \
  "${accel[@]}" -machine q35 -smp 4 -m 4096 \
  -drive "if=pflash,format=raw,readonly=on,file=$code" \
  -drive "if=pflash,format=raw,file=$work/vars.fd" \
  -cdrom "$iso" -boot d \
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
  "${drive_args[@]}" \
  "${gpu[@]}" -serial "file:$serial" -monitor "unix:$monitor,server,nowait" -qmp "unix:$qmp,server,nowait" -no-reboot || true
kill "$keys_pid" 2>/dev/null || true

report=$(sed -n '/=== LIVE-TEST BEGIN/,/=== LIVE-TEST END/p' "$serial" | tr -d '\r')
if [[ -z $report ]]; then
  echo "!! no test report on the serial console; last lines of $serial:" >&2
  tail -n 30 "$serial" >&2
  exit 2
fi
# Screenshots travel inside the report as one base64 line between "=== SCREENSHOT <name> BEGIN"
# and "=== SCREENSHOT <name> END" (live-boot-test's shot), and are decoded into PNG files below;
# the printed report shows each one as a single line instead of its base64 text.
awk '/^=== SCREENSHOT .* BEGIN$/ {print "=== SCREENSHOT " $3 " (saved as " $3 ".png)"; skip=1; next}
     /^=== SCREENSHOT .* END$/ {skip=0; next}
     !skip' <<< "$report"

fail=0
check() { grep -q -- "$1" <<< "$report" || { echo "!! expected: $1" >&2; fail=1; }; }
check "^cmdline casper: 1$"
if [[ $secure == on ]]; then check "^secure boot: SecureBoot enabled$"; else check "^secure boot: SecureBoot disabled"; fi
check "^live user: $id:[0-9]"
check "^live sudo: ok$"
check "^flatpak: yes$"
check "^snapd: enabled$"
check "^hyprland signature: yes$"
check "^shell ping: ok$"
check "^shell layers: \[.*$id-bar.*\]$"
check "^installer process: yes$"
check "^installer window: 1$"
check "^installer config: [1-9][0-9]* module files$"
check "^installer default file system: btrfs first offered: btrfs$"
check "^installer log: 0$"
check "^failed units: \[\]$"
check "^live groups: \[.*\bvideo\b.*\]$"
check "^installer tools missing: \[\]$"
check "^live packages: installed layer 0 live view 4$"
check "^chroot steps on live-only packages: \[\]$"
check "^installer scripts exit: keep-previous-loader stale=0 none=0 loader-fallback=0$"
check "^desktop tools missing: \[\]$"
check "^live pending migrations: 0$"
check "^live welcome step: 0$"
check "^terminal window: [1-9]"
check "^hyprland gpu env: AQ_DRM_DEVICES=/dev/dri/"
check "^volume monitors unit: success enabled=enabled$"
check "^named recommends missing: \[\]$"
check "^volume monitors: udisks2=active gphoto2=active mtp=active afc=active usbmuxd=installed$"
check "^menu launch window: [1-9]"
check "^launch decision: the display GPU (not a hybrid-graphics session)$"
check "^awk match: 1$"
check "^installer floating: true "
check "^pool: branch=[0-9]* debs=[1-9]"
check "^pool simulate: ok, [1-9]"
check "^pool modules choice: linux-modules-nvidia-[0-9]*-open-generic$"
check "^plymouth crash: 0$"
# Screenshots the guest printed as base64 between marker lines (installer window at two scales).
for name in $(sed -n 's/^=== SCREENSHOT \(.*\) BEGIN.*/\1/p' "$serial" | tr -d '\r'); do
  sed -n "/^=== SCREENSHOT $name BEGIN/,/^=== SCREENSHOT $name END/p" "$serial" | sed '1d;$d' | tr -d '\r\n' | base64 -d > "$work/$name.png" 2>/dev/null \
    && echo "== screenshot: $work/$name.png" || rm -f "$work/$name.png"
done
if (( fail )); then echo "!! ISO boot test FAILED (Secure Boot $secure)"; exit 2; fi
echo "== ISO boot test passed (Secure Boot $secure)"
