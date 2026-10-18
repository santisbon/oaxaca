#!/bin/bash
# Boot B of scripts/factory-reset-test.sh: the installed system, unlocked with the seller's disk
# encryption passphrase. Records what the reset must remove, runs <id>-system-factory-reset with
# its prompts answered (type "reset", the disk encryption passphrase, "Reboot later"), then puts
# boot C's pieces into the new root (@): the answers for the owner form, a drop-in that gives
# <id>-provision-owner the gum stand-in and presses Return for its splash, and check.sh's unit.
L=/usr/local/lib/factory-test
echo "=== FACTORY-B BEGIN"
echo "b machine-id: $(cat /etc/machine-id)"
echo "b users: $(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' /etc/passwd | paste -sd' ')"
echo "b seller file: $(cat /home/seller/secret.txt 2>/dev/null)"
printf '0:reset\n0:factorytest1\n1:\n' >/run/gum-answers
rm -f /run/gum-count
PATH="$L:$PATH" GUM_ANSWERS=/run/gum-answers GUM_COUNT=/run/gum-count "$id-system-factory-reset" >/run/reset.out 2>&1
echo "b reset exit: $?"
tail -n 12 /run/reset.out | sed 's/^/b reset: /'
grep -iE 'error|fail' "/var/log/$id-system-factory-reset.log" 2>/dev/null | tail -n 5 | sed 's/^/b reset log: /'

top=$(mktemp -d)
mount -o subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*//')" "$top"
N=$top/@
echo "b subvolumes after reset: $(btrfs subvolume list "$top" | awk '{print $NF}' | LC_ALL=C sort | paste -sd' ')"
install -d "$N$L"
install -m 0755 "$L/gum" "$L/check.sh" "$N$L/"
printf '0:English (UK)\n0:newowner\n0:ownerpass1\n0:ownerpass1\n0:New Owner\n0:\n0:resetbox\n0:America/Mexico_City\n0:\n' >"$N$L/owner-answers"
install -d "$N/etc/systemd/system/$id-provision-owner.service.d"
cat >"$N/etc/systemd/system/$id-provision-owner.service.d/factory-test.conf" <<UNIT
[Service]
Environment=PATH=$L:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=GUM_ANSWERS=$L/owner-answers
Environment=GUM_COUNT=/run/gum-count
UNIT
# Return for the form's splash, which reads a line from tty1. A unit of its own: systemd kills
# whatever an ExecStartPre= of the form's unit leaves running before the form starts (the first
# try waited on the splash for the whole boot). The newline first, because systemd's status lines
# on the serial console end in a carriage return only.
cat >"$N/etc/systemd/system/factory-test-keys.service" <<UNIT
[Unit]
Description=factory reset test: press Return for the owner form's splash
After=systemd-user-sessions.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do sleep 4; printf "\\n=== KEYS ret\\n" >/dev/ttyS0; done'

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/factory-test-keys.service "$N/etc/systemd/system/multi-user.target.wants/factory-test-keys.service"
cat >"$N/etc/systemd/system/factory-test-check.service" <<UNIT
[Unit]
Description=factory reset test: boots C and D, check the result
After=$id-provision-owner.service display-manager.service

[Service]
Type=oneshot
Environment=id=$id
ExecStart=$L/check.sh
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyS0

[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/factory-test-check.service "$N/etc/systemd/system/multi-user.target.wants/factory-test-check.service"
ln -sf /dev/null "$N/etc/systemd/system/serial-getty@ttyS0.service"
umount "$top"
echo "=== FACTORY-B END"
systemctl reboot
