# A driven installer check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/timezone
# make iso-test. Sourced by the guest's live-boot-test at its end (helpers: as_user, shot, $uid,
# $id); "=== KEYS", "=== CLICK x y" and "=== MOVE x y" lines are turned into input by the host
# (x, y in physical pixels of the 2560x1600 display, which runs at scale 1.6; a screenshot pixel
# times 3.2).
#
# The check: on the Location page, choosing a time zone from a dropdown with the keyboard and
# Return must close the dropdown and set the zone (reported on the laptop, 2026-10-17: "selecting
# the time zone with the enter key no longer selects it; the dropdown stays open"). A test
# installer (a copy of /etc/calamares whose pages are welcome, locale and summary; nothing is
# installed) is taken to the Location page, the Zone list is opened with a click, "den" typed and
# Return pressed, twice: with the session's environment (QT_IM_MODULE=fcitx: the list stays open)
# and as installer 0.1.9's launcher starts it, without QT_IM_MODULE and QT_QPA_PLATFORMTHEME
# (the list closes on Denver).
# Screenshots: tz-<try>-2-open, -3-typed, -4-return.
pkill -x calamares; sleep 2
rm -rf /tmp/caldrive; cp -a /etc/calamares /tmp/caldrive; ln -s /usr/share/calamares/qml /tmp/caldrive/qml
printf -- '---\nshowSupportUrl: false\nshowKnownIssuesUrl: false\nshowReleaseNotesUrl: false\nrequirements:\n    requiredStorage: 0\n    requiredRam: 0\n    check: [ ]\n    required: []\ngeoip:\n    style: "none"\n' > /tmp/caldrive/modules/welcome.conf
cat > /tmp/caldrive/settings.conf <<CONF
modules-search: [ local, /usr/lib/x86_64-linux-gnu/calamares/modules ]
sequence:
- show:
  - welcome
  - locale
  - summary
branding: $id
prompt-install: true
dont-chroot: false
CONF
wl=$(ls /run/user/$uid | grep '^wayland-[0-9]*$' | head -1)
hypr=$(pgrep -x Hyprland | head -1)
echo "drive: session im env: $(tr '\0' '\n' < /proc/${hypr:-0}/environ 2>/dev/null | grep -E '^(QT_IM_MODULE|QT_IM_MODULES|XMODIFIERS|QT_QPA_PLATFORMTHEME)=' | paste -sd' ')"
echo "drive: fcitx5: $(pgrep -x fcitx5 >/dev/null && echo running || echo 'not running')"

# One try: start the test installer with the given environment changes (the launcher's way:
# QT_QPA_PLATFORM=wayland, sudo -E), go to the Location page, open the Zone dropdown with a click,
# type "den" to reach Denver, press Return, and record what the page and the log show.
try() {
  local name=$1; shift
  pkill -x calamares; sleep 2
  # Through Hyprland, as the live session starts the installer, so it gets the session's
  # environment (QT_IM_MODULE=fcitx, XMODIFIERS), which as_user does not carry; "$*" are env
  # arguments to apply first (the launcher's fix: -u QT_IM_MODULE -u QT_IM_MODULES).
  as_user hyprctl dispatch "hl.dsp.exec_cmd(\"env $* QT_QPA_PLATFORM=wayland sudo -E calamares -c /tmp/caldrive -D8 >/tmp/caldrive-$name.log 2>&1\")" >/dev/null
  for _ in $(seq 1 30); do as_user hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | test("calamares"; "i"))' >/dev/null && break; sleep 2; done
  sleep 8
  local cpid; cpid=$(pgrep -nx calamares)
  echo "drive: $name: installer im env: [$(tr '\0' '\n' < /proc/${cpid:-0}/environ 2>/dev/null | grep -E '^(QT_IM_MODULE|QT_IM_MODULES)=' | paste -sd' ')]"
  as_user hyprctl dispatch "hl.dsp.focus({ window = \"class:io.calamares.calamares\" })" >/dev/null 2>&1; sleep 1
  echo "=== KEYS alt-n"; sleep 6
  echo "=== MOVE 1600 900"; sleep 1           # away and back: a click where the pointer already
  echo "=== CLICK 1814 1040"; sleep 3          # rests did not reach a second installer; the Zone dropdown
  shot tz-$name-2-open
  echo "=== KEYS d e n"; sleep 3
  shot tz-$name-3-typed
  echo "=== KEYS ret"; sleep 3
  shot tz-$name-4-return
  echo "drive: $name: zone log: $(grep -oE 'Timezone[^"]*"[^"]*"|timezone [^ ]*|America/[A-Za-z_]+' /tmp/caldrive-$name.log | tail -n 3 | paste -sd' | ')"
  pkill -x calamares; sleep 2
}
try launcher -u QT_IM_MODULE -u QT_IM_MODULES -u QT_QPA_PLATFORMTHEME
try session
