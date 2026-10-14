# A driven installer check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/space-then-passphrase
# make iso-test. The same pages and helpers as tests/iso-drive/replace-encrypted/run.sh, in the order
# that crashed the installer on the Legion laptop on 2026-10-13: "Replace a partition", the free
# space chosen first, then the passphrase typed and confirmed (encryption is already checked).
pkill -x calamares; sleep 2
if [[ -f /run/oaxtest/STOCK ]]; then
  echo "drive: installing Ubuntu's stock calamares 3.3.14-0ubuntu30"
  apt-get -q update >/tmp/apt.log 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get -q -y --allow-downgrades install calamares=3.3.14-0ubuntu30 calamares-data=3.3.14-0ubuntu30 libcalamares3.3=3.3.14-0ubuntu30 libcalamaresui3.3=3.3.14-0ubuntu30 >>/tmp/apt.log 2>&1 || tail -5 /tmp/apt.log
fi
echo "drive: calamares $(dpkg-query -W -f='${Version}' calamares)"
rm -rf /tmp/caldrive; cp -a /etc/calamares /tmp/caldrive; ln -s /usr/share/calamares/qml /tmp/caldrive/qml
# The welcome module publishes requiredStorageGiB, without which the partition page offers no
# "Replace a partition" (PartUtils::canBeReplaced); no requirement blocks Next.
printf -- '---\nshowSupportUrl: false\nshowKnownIssuesUrl: false\nshowReleaseNotesUrl: false\nrequirements:\n    requiredStorage: 20\n    requiredRam: 0\n    check: [ storage ]\n    required: []\ngeoip:\n    style: "none"\n' > /tmp/caldrive/modules/welcome.conf
cat > /tmp/caldrive/settings.conf <<CONF
modules-search: [ local, /usr/lib/x86_64-linux-gnu/calamares/modules ]
sequence:
- show:
  - welcome
  - partition
  - summary
branding: $id
prompt-install: true
dont-chroot: false
CONF
wl=$(ls /run/user/$uid | grep '^wayland-[0-9]*$' | head -1)
as_user env WAYLAND_DISPLAY="$wl" QT_QPA_PLATFORM=wayland sudo -E calamares -c /tmp/caldrive -D6 >/tmp/caldrive.log 2>&1 &
for _ in $(seq 1 30); do as_user hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | test("calamares"; "i"))' >/dev/null && break; sleep 2; done
sleep 8
as_user hyprctl dispatch "hl.dsp.focus({ window = \"class:io.calamares.calamares\" })" >/dev/null 2>&1; sleep 1
echo "=== KEYS alt-n"; sleep 8
shot drive-1
echo "=== CLICK 730 490"; sleep 6          # "Replace a partition"
shot drive-2
grep -q 'preCheckEncryption' /tmp/caldrive/modules/partition.conf && echo "drive: preCheckEncryption in partition.conf"
echo "=== CLICK 1760 1050"; sleep 12       # the free space on the Current bar
shot drive-3
echo "drive: calamares after choosing the space: $(pgrep -x calamares >/dev/null && echo running || echo GONE)"
echo "=== CLICK 1114 944"; sleep 2         # passphrase
echo "=== KEYS t e s t p a s s 1"; sleep 3
echo "=== CLICK 1504 944"; sleep 2         # confirmation
echo "=== KEYS t e s t p a s s 1"; sleep 10
shot drive-4
echo "drive: calamares after choosing the partition: $(pgrep -x calamares >/dev/null && echo running || echo GONE)"
grep -iE 'luks|oaxaca_root' /tmp/caldrive.log | tail -n 3 | cut -c1-160 | sed 's/^/drive log: /'
tail -n 40 /tmp/caldrive.log | cut -c1-220 | sed 's/^/drive tail: /'
dmesg | grep -i 'calamares' | tail -n 5 | sed 's/^/drive dmesg: /'
pkill -x calamares
