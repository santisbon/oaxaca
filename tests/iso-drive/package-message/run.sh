# A driven installer check for scripts/iso-boot-test.sh: DRIVE=tests/iso-drive/package-message
# make iso-test. Sourced by the guest's live-boot-test at its end (helpers: as_user, shot, $uid,
# $id); "=== KEYS" lines are turned into key presses by the host.
#
# The check: the installer's progress message for removing packages must read "Removing 5
# packages."; on the laptop (2026-10-17) and in QEMU it read "Removing 5 p<box>ckages." until
# Calamares 3.3.14-0ubuntu30oaxaca3 (keep-python-results-alive.patch, docs/7 choice 54). The
# message is the packages step's (Calamares's packages module, a Python job). A test installer
# runs only that step, against the live system itself (dont-chroot), removing five packages built
# on the spot, one of which pauses 20 seconds in its prerm so the message stays up; a
# full-resolution screenshot (pkg-2-removing) is taken while it shows. The installer is started
# as installer 0.1.9's launcher starts it, through Hyprland.
pkill -x calamares; sleep 2
work=/tmp/pkgmsg; rm -rf "$work"; mkdir -p "$work"
for n in 1 2 3 4 5; do
  d=$work/frt$n; mkdir -p "$d/DEBIAN"
  printf 'Package: frt%s\nVersion: 1.0\nArchitecture: all\nMaintainer: test <test@example.invalid>\nDescription: package-message test %s\n' $n $n > "$d/DEBIAN/control"
  if [[ $n == 1 ]]; then printf '#!/bin/sh\nsleep 20\n' > "$d/DEBIAN/prerm"; chmod 0755 "$d/DEBIAN/prerm"; fi
  dpkg-deb --build "$d" "$work/frt$n.deb" >/dev/null
done
dpkg -i "$work"/frt*.deb >/dev/null 2>&1
echo "drive: calamares $(dpkg-query -W -f='${Version}' calamares); test packages installed: $(dpkg-query -W -f='${db:Status-Status}\n' frt1 frt2 frt3 frt4 frt5 2>/dev/null | grep -cx installed)"

rm -rf /tmp/caldrive; cp -a /etc/calamares /tmp/caldrive; ln -s /usr/share/calamares/qml /tmp/caldrive/qml
printf -- '---\nshowSupportUrl: false\nshowKnownIssuesUrl: false\nshowReleaseNotesUrl: false\nrequirements:\n    requiredStorage: 0\n    requiredRam: 0\n    check: [ ]\n    required: []\ngeoip:\n    style: "none"\n' > /tmp/caldrive/modules/welcome.conf
printf -- '---\nbackend: apt\nupdate_db: false\nupdate_system: false\nskip_if_no_internet: false\noperations:\n  - try_remove:\n    - frt1\n    - frt2\n    - frt3\n    - frt4\n    - frt5\n' > /tmp/caldrive/modules/packages.conf
cat > /tmp/caldrive/settings.conf <<CONF
modules-search: [ local ]
sequence:
- show:
  - welcome
  - summary
- exec:
  - packages
- show:
  - finished
branding: $id
prompt-install: false
dont-chroot: true
CONF
as_user hyprctl dispatch "hl.dsp.exec_cmd(\"env -u QT_IM_MODULE -u QT_IM_MODULES -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=wayland sudo -E calamares -c /tmp/caldrive -D8 >/tmp/caldrive-pkg.log 2>&1\")" >/dev/null
for _ in $(seq 1 30); do as_user hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.class | test("calamares"; "i"))' >/dev/null && break; sleep 2; done
sleep 8
as_user hyprctl dispatch "hl.dsp.focus({ window = \"class:io.calamares.calamares\" })" >/dev/null 2>&1; sleep 1
echo "=== KEYS alt-n"; sleep 4        # to Summary
echo "=== KEYS alt-s"; sleep 8        # "Set Up" (the branding's name for Install): the packages step starts
# Full resolution, for the letters: grim without -s.
wl=$(ls /run/user/$uid | grep '^wayland-[0-9]*$' | head -1)
if as_user env WAYLAND_DISPLAY="$wl" grim -t png /tmp/pkg-full.png 2>/tmp/grim.err; then
  echo "=== SCREENSHOT pkg-2-removing BEGIN"; base64 -w 0 /tmp/pkg-full.png; echo; echo "=== SCREENSHOT pkg-2-removing END"
fi
sleep 20
pkill -x calamares
dpkg --purge frt1 frt2 frt3 frt4 frt5 >/dev/null 2>&1 || true
