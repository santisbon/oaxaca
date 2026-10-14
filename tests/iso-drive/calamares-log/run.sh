# A driven check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/calamares-log make iso-test.
# Where the live session's installer (oaxaca-installer: sudo -E calamares -D8, started at login)
# writes Calamares's session log, so the docs can name the path (docs/7, choice 26).
sleep 20
echo "drive: installer running: $(pgrep -x calamares >/dev/null && echo yes || echo no)"
echo "drive: calamares HOME: $(tr '\0' '\n' < /proc/$(pgrep -x calamares | head -1)/environ 2>/dev/null | grep '^HOME=')"
find / -xdev -path '*calamares*' -name 'session.log' 2>/dev/null | sed 's/^/drive: session log: /'
find /root /home /tmp -name 'session.log' 2>/dev/null | sed 's/^/drive: any session.log: /'
