#!/usr/bin/env bash
# factory-reset-test.sh: install the distro on an encrypted btrfs disk in QEMU, factory-reset it,
# and check that the reset wiped the owner and handed the machine to a new one (docs/6, choice 87).
#
# Anatomy: four QEMU runs under OVMF with Secure Boot on (the firmware and keys iso-boot-test.sh
# uses), sharing one firmware variable file and one sparse 40 GiB target disk. Each run ends when
# the guest powers off or reboots (-no-reboot); the guest's serial console goes through a socket to
# a Python watcher, which logs it, types the disk encryption passphrase when the initramfs asks
# ("Please unlock disk"), and turns "=== KEYS <key>" lines into key presses through QEMU's monitor.
# A line after which the boot cannot go on (casper finding no live medium, a kernel panic) makes
# the watcher quit QEMU, and a boot whose report never began ends the test (reached below).
#   A. The test ISO (build/iso/<id>-<version>-amd64-test.iso). Its live session runs its own boot
#      test, then tests/factory-reset/run.sh from a small disk labelled OAXTEST: a scripted install
#      that follows the installer's settings and runs its scripts, ending with factory-snapshot,
#      then the seller's use of the machine and boot B's unit (run.sh's header).
#   B. The installed system, unlocked with the seller's passphrase: tests/factory-reset/stage.sh
#      runs <id>-system-factory-reset with its prompts answered, prepares boot C and reboots.
#   C. No passphrase prompt (the reset's keyfile unlocks the disk): the reset's wipe runs, then the
#      owner form on tty1 with its prompts answered and Return pressed for its splash, then
#      tests/factory-reset/check.sh prints what the machine holds and reboots.
#   D. Unlocked with the new owner's password: check.sh prints the login state and powers off.
# The lines between each run's markers are compared with the expectations at the end.
#
# Usage: scripts/factory-reset-test.sh      (make factory-reset-test; needs make iso first)
# Env:   QEMU_RENDERNODE=<path>, KEEP=1 keeps build/factory-reset-test/
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
id=$DISTRO_ID
iso="$here/build/iso/$id-$BASE_VERSION-amd64-test.iso"
[[ -f $iso ]] || { echo "no test ISO at $iso: run 'make iso' first" >&2; exit 1; }
[[ -w /dev/kvm ]] || { echo "/dev/kvm is not accessible; the test needs KVM" >&2; exit 1; }
work="$here/build/factory-reset-test"
rm -rf "$work"; mkdir -p "$work"
# QEMU's and the watcher's sockets: a Unix socket's path must be shorter than 108 bytes, which a
# checkout under a long directory exceeds.
socks=$(mktemp -d /tmp/frt.XXXXXX)
trap 'rm -rf "$socks"' EXIT
code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd "$work/vars.fd"
truncate -s 40G "$work/target.img"
truncate -s 64M "$work/drive.img"
mkfs.ext4 -q -F -L OAXTEST -d "$here/tests/factory-reset" "$work/drive.img"

rendernode=${QEMU_RENDERNODE:-}
if [[ -z $rendernode ]]; then
  for r in /dev/dri/renderD*; do
    drv=$(basename "$(readlink -f "/sys/class/drm/$(basename "$r")/device/driver" 2>/dev/null)" 2>/dev/null)
    [[ $drv == nvidia ]] && continue
    rendernode=$r; break
  done
fi
if [[ -n $rendernode && -w $rendernode ]]; then
  gpu=(-device virtio-vga-gl,xres=2560,yres=1600 -display "egl-headless,rendernode=$rendernode")
else
  gpu=(-device virtio-vga -display none)
fi

# run <name> <timeout s> <passphrase or "none"> <qemu args...>
run() {
  local name=$1 limit=$2 pass=$3
  shift 3
  local serial="$work/$name.serial.log" sock="$socks/$name.serial" monitor="$socks/$name.monitor"
  rm -f "$sock" "$monitor"
  echo "== boot $name (timeout ${limit}s, serial log $serial)"
  python3 -I - "$sock" "$monitor" "$serial" "$pass" <<'PY' &
import os, select, socket, sys, time
sock_path, mon_path, log_path, passphrase = sys.argv[1:5]
FATAL = ("Unable to find a medium containing a live file system", "Kernel panic - not syncing")
def connect(path):
    for _ in range(300):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            return s
        except OSError:
            time.sleep(0.2)
    sys.exit(1)
ser = connect(sock_path)
mon = connect(mon_path)
log = open(log_path, "ab", buffering=0)
buf = b""
while True:
    data = ser.recv(4096)
    if not data:
        break
    log.write(data)
    buf += data
    while True:
        # A line, or the passphrase prompt, which ends without a newline.
        i = buf.find(b"\n")
        j = buf.find(b"Please unlock disk")
        if j >= 0 and (i < 0 or j < i) and b": " in buf[j:]:
            end = buf.index(b": ", j) + 2
            buf = buf[end:]
            if passphrase == "none":
                log.write(b"\n=== UNEXPECTED PASSPHRASE PROMPT\n")
            else:
                time.sleep(1)
                ser.sendall(passphrase.encode() + b"\r")
                log.write(b"\n[watcher: passphrase typed]\n")
            continue
        if i < 0:
            break
        line, buf = buf[:i].decode("utf-8", "replace").strip("\r"), buf[i + 1:]
        # A boot that cannot go on waits at a prompt nobody answers (casper's netboot question
        # after it finds no live medium, 2026-10-19: a guest starved at start-up sat there until
        # the 3000 s timeout). Such a line ends the run at once through the monitor's quit.
        if any(f in line for f in FATAL):
            log.write(("\n=== FATAL %s\n" % line.strip()).encode())
            mon.sendall(b"quit\n")
        # Anywhere in the line: systemd's status lines end in a carriage return only, so a
        # KEYS line can follow one.
        if "=== KEYS " in line:
            for key in line[line.index("=== KEYS ") + 9:].split():
                mon.sendall(("sendkey %s\n" % key).encode())
                time.sleep(0.3)
        # Empty the monitor's replies without waiting for one. A wait here, once per line, held
        # the reading at 5 lines a second (a 0.2 s recv timeout), so the socket filled, QEMU's
        # serial port held the guest's console writes, and the live boot crawled until casper
        # gave up looking for the CD-ROM (2026-10-23: 26 s for the 130 lines the kernel queued
        # before its console started).
        while select.select([mon], [], [], 0)[0]:
            try:
                if not mon.recv(4096):
                    break
            except OSError:
                break
PY
  local watcher=$!
  timeout --foreground "$limit" qemu-system-x86_64 \
    -enable-kvm -cpu host -machine q35 -smp 4 -m 6144 \
    -drive "if=pflash,format=raw,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,file=$work/vars.fd" \
    -drive "file=$work/target.img,format=raw,if=virtio" \
    -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
    "${gpu[@]}" \
    -chardev "socket,id=ser0,path=$sock,server=on,wait=off" -serial chardev:ser0 \
    -monitor "unix:$monitor,server,nowait" -no-reboot "$@" || true
  wait "$watcher" 2>/dev/null || true
}
# The guest's own output is still queued for the serial port when the kernel writes its last
# messages ("[  311.935282] reboot: Power down") straight to the port, so a kernel message can
# land inside a line of the report: on 2026-10-22 "factory install: done" came out as
# "factory install: d", the kernel's message and its newline, then "one". perl removes every
# kernel message that starts in the middle of a line, with its newline, which joins the guest's
# line up again; a kernel message on a line of its own is left alone.
section() {
  sed -n "/=== $1 BEGIN/,/=== $1 END/p" "$work/$2.serial.log" 2>/dev/null | tr -d '\r' |
    perl -0pe 's/(?<=[^\n])\[ *\d+\.\d+\] [^\n]*\n//g' | grep -av $'\e\\[' || true
}
# Each boot works on what the one before it left on the disk, so a boot whose report never began
# (casper finding no live medium, the firmware falling back to network boot) or that the watcher
# quit on a fatal line ends the test there: boot B on a disk that boot A never installed only
# waits for its own timeout. The BEGIN line is the test, not the END line: a report's last lines
# are still in the guest's serial buffer when the guest powers off or reboots, and the kernel's
# own shutdown lines can cut them (2026-10-19: "=== DRIVE END" came out as "D" after
# "reboot: Power down", in a run whose report was complete).
reached() {
  local log="$work/$1.serial.log"
  if grep -aq "=== $2 BEGIN" "$log" 2>/dev/null && ! grep -aq "=== FATAL" "$log"; then return 0; fi
  echo "!! boot $1 ended without its report (no '=== $2 BEGIN', or a FATAL line); last lines of $log:" >&2
  tr -d '\r' < "$log" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -avE '^[A-Za-z0-9+/=]{60,}$' | tail -n 15 >&2
  echo "!! factory reset test FAILED (logs in $work)"
  exit 1
}

run A 3000 none -cdrom "$iso" -boot d -drive "file=$work/drive.img,format=raw,if=virtio"
reportA=$(section DRIVE A)
echo "$reportA"
reached A DRIVE
run B 1200 factorytest1
reportB=$(section FACTORY-B B)
echo "$reportB"
reached B FACTORY-B
run C 1500 none
reportC=$(section FACTORY-C C)
echo "$reportC"
reached C FACTORY-C
run D 900 ownerpass1
reportD=$(section FACTORY-D D)
echo "$reportD"
reached D FACTORY-D

fail=0
check() { grep -q -- "$2" <<< "$1" || { echo "!! expected: $2" >&2; fail=1; }; }
# "done" is boot A's last line before it powers off, where the kernel's own messages can cut
# into it; section() above joins it up again.
check "$reportA" "^factory install: done$"
check "$reportA" "^factory install: apt lists: [1-9]"
check "$reportA" "^factory snapshot: present ro=true$"
check "$reportA" "^factory boot copy in running root: no$"
check "$reportA" "^factory boot copy in snapshot: [1-9]"
check "$reportA" "^factory users: seller$"
check "$reportB" "^b seller file: the seller's own file$"
check "$reportB" "^b reset exit: 0$"
check "$reportB" "^b subvolumes after reset: @ @cache @factory @home @log @$id-old-[0-9]* @swap timeshift-btrfs/snapshots/.*/@$"
check "$reportC" "^c owner unit: success active$"
check "$reportC" "^c finish unit: success$"
check "$reportC" "^c provisioning dir: \[\]$"
check "$reportC" "^c users: newowner$"
check "$reportC" "^c homes: newowner$"
check "$reportC" "^c owner groups: adm cdrom dip lpadmin newowner plugdev sudo video$"
check "$reportC" "^c owner name: New Owner$"
check "$reportC" "^c root password: L$"
check "$reportC" "^c seller in account files: 0$"
check "$reportC" "^c seller drift: etc=no usr-local=no wifi=0$"
check "$reportC" "^c hostname: resetbox$"
check "$reportC" "^c timezone: America/Mexico_City$"
check "$reportC" '^c keyboard: XKBLAYOUT="gb"$'
check "$reportC" "^c luks slots: 1$"
check "$reportC" "^c luks owner password: unlocks$"
check "$reportC" "^c luks seller passphrase: refused$"
check "$reportC" "^c crypttab: none luks$"
check "$reportC" "^c conf-hook changed: 0$"
check "$reportC" "^c initramfs keyfiles: 0$"
check "$reportC" "^c staged key files: 0$"
check "$reportC" "^c subvolumes: @ @cache @factory @home @log @swap$"
check "$reportC" "^c top level: @ @cache @factory @home @log @swap$"
check "$reportC" "^c factory users: \[\] ro=true$"
check "$reportC" "^c factory seller in account files: 0$"
check "$reportC" "^c swap: /swap/swapfile$"
check "$reportC" "^c ssh host keys: \([1-9] sshd=yes\|0 sshd=no\)$"
check "$reportC" "^c autologin: User=newowner$"
check "$reportC" "^c owner session: [1-9]$"
b_id=$(sed -n 's/^b machine-id: //p' <<< "$reportB")
c_id=$(sed -n 's/^c machine-id: //p' <<< "$reportC")
[[ -n $c_id && $c_id != "$b_id" ]] || { echo "!! expected: a new machine-id (b $b_id, c $c_id)" >&2; fail=1; }
grep -q "UNEXPECTED PASSPHRASE PROMPT" "$work/C.serial.log" && { echo "!! boot C asked for a passphrase" >&2; fail=1; }
check "$reportD" "^d autologin file: absent$"
check "$reportD" "^d owner session: 0$"
check "$reportD" "^d display manager: active$"
check "$reportD" "^d luks slots: 1$"
[[ ${KEEP:-0} == 1 ]] || { (( fail )) || rm -rf "$work"; }
if (( fail )); then echo "!! factory reset test FAILED (logs in $work)"; exit 1; fi
echo "== factory reset test passed"
