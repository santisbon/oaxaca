#!/bin/bash
# Boots C and D of scripts/factory-reset-test.sh. Boot C (no flag file yet) follows the reset's
# wipe and the owner form: it prints what the reset left, then sets the flag and reboots. Boot D
# follows a normal boot, unlocked with the new owner's password: it prints the login state and
# powers off. Every line goes to the serial console for the host to compare.
L=/usr/local/lib/factory-test
flag=/var/lib/factory-test-phase
luks=$(lsblk -nslpo NAME,FSTYPE "$(findmnt -no SOURCE / | sed 's/\[.*//')" | awk '$2 == "crypto_LUKS" { print $1; exit }')
owner_sessions() { loginctl list-sessions --no-legend 2>/dev/null | awk '$3 == "newowner"' | grep -c .; }

if [[ ! -f $flag ]]; then
  echo "=== FACTORY-C BEGIN"
  echo "c owner unit: $(systemctl show -p Result --value "$id-provision-owner.service") $(systemctl is-active "$id-provision-owner.service")"
  echo "c finish unit: $(systemctl show -p Result --value "$id-system-factory-reset-finish.service")"
  echo "c provisioning dir: [$(ls "/var/lib/$id/provisioning" 2>/dev/null | paste -sd' ')]"
  echo "c machine-id: $(cat /etc/machine-id)"
  echo "c users: $(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' /etc/passwd | paste -sd' ')"
  echo "c homes: $(ls /home | paste -sd' ')"
  echo "c owner groups: $(id -nG newowner 2>/dev/null | tr ' ' '\n' | LC_ALL=C sort | paste -sd' ')"
  echo "c owner name: $(getent passwd newowner | cut -d: -f5)"
  echo "c root password: $(passwd -S root | awk '{ print $2 }')"
  echo "c seller drift: etc=$([ -e /etc/seller-drift ] && echo yes || echo no) usr-local=$([ -e /usr/local/bin/seller-tool ] && echo yes || echo no) wifi=$(ls /etc/NetworkManager/system-connections | grep -c seller)"
  echo "c hostname: $(cat /etc/hostname)"
  echo "c timezone: $(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
  echo "c keyboard: $(grep '^XKBLAYOUT=' /etc/default/keyboard)"
  echo "c luks slots: $(cryptsetup luksDump "$luks" | grep -cE '^ +[0-9]+: luks2')"
  echo "c luks owner password: $(printf ownerpass1 | cryptsetup open --test-passphrase --key-file - "$luks" 2>/dev/null && echo unlocks || echo refused)"
  echo "c luks seller passphrase: $(printf factorytest1 | cryptsetup open --test-passphrase --key-file - "$luks" 2>/dev/null && echo unlocks || echo refused)"
  echo "c crypttab: $(grep -v '^#' /etc/crypttab | awk '{ print $3, $4 }')"
  echo "c conf-hook changed: $(dpkg --verify cryptsetup-initramfs 2>&1 | grep -c conf-hook)"
  echo "c initramfs keyfiles: $(lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -c 'cryptroot/keyfiles/')"
  echo "c staged key files: $(ls "/etc/$id/provisioning.key" "/var/lib/$id/provisioning/luks-key" /etc/initramfs-tools/conf.d/"$id"-provisioning 2>/dev/null | grep -c .)"
  top=$(mktemp -d)
  mount -o subvolid=5 "$(findmnt -no SOURCE / | sed 's/\[.*//')" "$top"
  echo "c subvolumes: $(btrfs subvolume list "$top" | awk '{ print $NF }' | LC_ALL=C sort | paste -sd' ')"
  echo "c top level: $(ls -A "$top" | LC_ALL=C sort | paste -sd' ')"
  echo "c factory users: [$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' "$top/@factory/etc/passwd" | paste -sd' ')] ro=$(btrfs property get -ts "$top/@factory" ro | cut -d= -f2)"
  umount "$top"
  echo "c swap: $(swapon --show=NAME --noheadings | paste -sd' ')"
  echo "c ssh host keys: $(ls /etc/ssh/ssh_host_*_key 2>/dev/null | grep -c .) sshd=$([ -x /usr/sbin/sshd ] && echo yes || echo no)"
  echo "c autologin: $(grep -h '^User=' /etc/sddm.conf.d/autologin.conf 2>/dev/null)"
  for i in $(seq 90); do (( $(owner_sessions) > 0 )) && break; sleep 1; done
  echo "c owner session: $(owner_sessions)"
  grep -iE 'error|fail' "/var/log/$id-provision-owner.log" 2>/dev/null | tail -n 5 | sed 's/^/c owner log: /'
  journalctl -b -o cat -u "$id-system-factory-reset-finish.service" | tail -n 12 | sed 's/^/c finish log: /'
  rm -rf "/etc/systemd/system/$id-provision-owner.service.d"
  touch "$flag"
  echo "=== FACTORY-C END"
  systemctl reboot
else
  echo "=== FACTORY-D BEGIN"
  echo "d autologin file: $([ -e /etc/sddm.conf.d/autologin.conf ] && echo present || echo absent)"
  sleep 30
  echo "d owner session: $(owner_sessions)"
  echo "d display manager: $(systemctl is-active display-manager.service)"
  echo "d luks slots: $(cryptsetup luksDump "$luks" | grep -cE '^ +[0-9]+: luks2')"
  echo "=== FACTORY-D END"
  systemctl poweroff
fi
