#!/usr/bin/env bash
# rootfs-boot-test.sh: boot the root filesystem tarball in QEMU and check that the base
# system (roadmap step 3), for the session profile the graphical session (roadmap step 4),
# and for the desktop profile the ported Omarchy desktop (roadmap step 6) come up.
#
# Anatomy: three programs run in turn.
#   1. tar, to pull the kernel (vmlinuz) and initramfs (initrd.img) out of the tarball.
#   2. mke2fs -d, inside an unprivileged user namespace (unshare), to turn the tarball's
#      contents into a raw ext4 disk image, after a oneshot systemd unit is dropped into
#      the tree. That unit runs the checks below and powers the machine off. For the
#      session profile a test user and an SDDM autologin file for that user go in too.
#   3. qemu-system-x86_64 with KVM, booting that kernel and initramfs directly with the
#      ext4 image as /dev/vda. No bootloader, no UEFI, no partition table: those belong to
#      the image step (roadmap step 7). The guest's serial console goes to a log file.
#      For the session profile the guest gets a virtio GPU: with virgl (3D through the
#      host's GPU, "-display egl-headless") when a render node is writable, plain
#      virtio-vga otherwise (Mesa's software renderer in the guest).
# This script then prints the checks' output from the log and exits non-zero if any
# check failed.
#
# Checks, run as root inside the guest once systemd finishes startup:
#   base: systemd reached "running" (no failed units), os-release identifies the distro, the
#   apparmor, NetworkManager, systemd-resolved and timesyncd units are active, NetworkManager
#   reports a connected state on QEMU's user-mode network, and "apt-get update" succeeds
#   against both the Ubuntu archive and our apt repository through the installed keyring.
#   session: sddm is active, logind shows a wayland session for the test user, uwsm's
#   wayland-wm@Hyprland.service and graphical-session.target are active in that user's
#   systemd user manager, Hyprland reports the virtual monitor, an X11 client (xeyes,
#   installed with apt inside the guest) shows up in "hyprctl clients" as an Xwayland
#   window, the three portal services answer on the user's bus, gnome-keyring-daemon's user
#   unit is active and the Secret Service (org.freedesktop.secrets) answers a call on that
#   bus, Omarchy's own shell (shell/ and config/omarchy from the omacom/omarchy tag in
#   distro.conf, fetched into build/omarchy/ with a sparse git clone and copied to
#   /usr/share/omarchy in the test image) starts on our Quickshell and answers an IPC ping
#   with its bar on screen as a layer surface (roadmap step 5), ubuntu-drivers runs, and
#   <id>-drivers-install --show runs (choosing nothing: QEMU shows no NVIDIA GPU).
#   desktop: the session checks, with the session started through the port's own session file
#   (<id>.desktop) and the test user's home seeded from /etc/skel like a real user's; before
#   SDDM starts, a oneshot unit runs "<id>-apply-system --install-user tester --first-install",
#   the root-side setup the installer will run (install/config, hardware, post-install scripts;
#   log in /var/log/<id>-install.log). Then: Hyprland loaded the ported configuration (the
#   session has <ID>_PATH), the shell the port's autostart launched answers "<id>-shell shell
#   ping" and has its bar and background layers on screen, first-run finished (the done marker,
#   the theme name file, the user units it enables), the lock-screen PAM files exist, a theme
#   switch with "<id>-theme-set" takes effect live, the menu opens as a layer surface on
#   "<id>-menu toggle", the fonts and the third-party packages are installed, "<id>-version"
#   and "<id>-update-available" run, and the shell's journal has no error lines. The bar has
#   visible widgets (the shell's debugBarGeometry call), not only a layer surface. The
#   keybindings: Lua (lua5.4, installed with apt inside the guest) runs the user's hyprland.lua
#   through scripts/boot-test-bindings.lua, which lists every binding and the command it runs;
#   scripts/boot-test-bindings.py, started through Hyprland so that it sees a key press's
#   environment, checks that every program those commands run is on PATH; and every binding that
#   opens a menu or a shell panel is run the way a key press runs it (hyprctl dispatch with
#   hl.dsp.exec_cmd), exits 0, and for a menu puts the menu's layer on screen.
#   UPGRADE=1 (desktop profile): the tarball is the published system (rootfs-create.sh with
#   SOURCE=published), and build/'s newest packages go into the image as a flat apt archive.
#   Once the session is up, the guest runs "<id>-update -y" as the test user in the session's
#   environment from login, as a terminal opened before the update would, and with apt's source
#   for build/ added, so the update installs build/. The update must exit 0 with no shell
#   errors in its output and restart the shell; all the desktop checks then run against the
#   upgraded system in the session that began before it. Found missing on 2026-10-17: an update
#   that renamed a variable left the running session's bar empty and Super+Space dead, and every
#   test booted a fresh image.
#
# Usage: scripts/rootfs-boot-test.sh [tarball]   default: build/rootfs/<id>-<version>-amd64-<profile>.tar
#                                                (with UPGRADE=1: ...-desktop-published.tar)
# Env:   PROFILE (base | session | desktop | live, default live; the live tarball is the desktop plus
#        casper and the installer, so live runs the desktop checks with casper's medium check masked
#        and the installer's autostart removed), QEMU_MEM (MiB, default 2048 base /
#        3072 session / 4096 desktop and live),
#        QEMU_TIMEOUT (seconds, default 600), QEMU_RENDERNODE (default: the first non-NVIDIA render node),
#        KEEP=1 keeps the work dir, UPGRADE=1 (see above; QEMU_TIMEOUT default 900)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"

profile=${PROFILE:-live}
case $profile in base|session|desktop|live) ;; *) echo "unknown PROFILE '$profile' (base, session, desktop or live)" >&2; exit 1 ;; esac
upgrade=${UPGRADE:-0}
[[ $upgrade == 0 || $profile == desktop ]] || { echo "UPGRADE=1 needs PROFILE=desktop" >&2; exit 1; }
suffix=""; [[ $upgrade == 1 ]] && suffix=-published
tarball=${1:-"$here/build/rootfs/$DISTRO_ID-$BASE_VERSION-amd64-$profile$suffix.tar"}
[[ -f $tarball ]] || { echo "no root filesystem tarball at $tarball: run 'make rootfs PROFILE=$profile${suffix:+ SOURCE=published}' first" >&2; exit 1; }
# The live tarball is the desktop tarball plus casper, the live-session package and the installer
# (scripts/rootfs-create.sh), so the desktop checks are the right ones for it. Two of its parts do
# act when the tarball boots from a disk instead of the ISO, and the image preparation below
# neutralises them: casper-md5check.service (verifies /cdrom/md5sum.txt, which only the ISO has;
# failed on 2026-10-11) is masked, and the installer's autostart entry (sudo calamares, which the
# test user cannot run) is removed. From here on the profile names the check set.
echo "tarball: $tarball"
live=0
[[ $profile == live ]] && { profile=desktop; live=1; }
[[ -r /dev/kvm && -w /dev/kvm ]] || { echo "/dev/kvm is not accessible; the test needs KVM" >&2; exit 1; }
work="$here/build/rootfs/boot-test"
rm -rf "$work"; mkdir -p "$work"
image="$work/root.ext4"
serial="$work/serial.log"
case $profile in desktop) default_mem=4096 ;; session) default_mem=3072 ;; *) default_mem=2048 ;; esac
mem=${QEMU_MEM:-$default_mem}
timeout_s=${QEMU_TIMEOUT:-600}
[[ $upgrade == 1 ]] && timeout_s=${QEMU_TIMEOUT:-900}

upgrade_dir=""
if [[ $upgrade == 1 ]]; then
  # build/'s newest .deb of each package (dpkg's version order), with a Packages index for apt's
  # flat-archive format (dpkg-scanpackages), as upgrade-test.sh stages them.
  upgrade_dir="$work/upgrade"
  mkdir -p "$upgrade_dir"
  declare -A up_ver up_deb
  for deb in "$here"/build/*.deb; do
    [[ -f $deb ]] || continue
    base=$(basename "$deb"); n=${base%%_*}; rest=${base#*_}; v=${rest%%_*}
    if [[ -z ${up_ver[$n]:-} ]] || dpkg --compare-versions "$v" gt "${up_ver[$n]}"; then
      up_ver[$n]=$v; up_deb[$n]=$deb
    fi
  done
  for n in "${!up_deb[@]}"; do cp "${up_deb[$n]}" "$upgrade_dir/"; done
  (cd "$upgrade_dir" && dpkg-scanpackages . /dev/null > Packages 2>/dev/null)
  echo "== upgrade: $(grep -c '^Package:' "$upgrade_dir/Packages") packages from build/ staged for the update inside the session"
fi

echo "== kernel and initramfs out of $tarball"
kver=$(tar -tf "$tarball" | sed -n 's|^\./boot/vmlinuz-\(.*\)$|\1|p' | sort -V | tail -1)
[[ -n $kver ]] || { echo "no /boot/vmlinuz-* in the tarball" >&2; exit 1; }
tar -xOf "$tarball" "./boot/vmlinuz-$kver" > "$work/vmlinuz"
tar -xOf "$tarball" "./boot/initrd.img-$kver" > "$work/initrd.img"
echo "   kernel $kver"

omarchy_dir=""
if [[ $profile == session ]]; then
  # Omarchy's shell, for the Quickshell check: only shell/ and config/omarchy/ (2 MB) out of
  # the 133 MB tree, through git's partial clone. Cached per tag under build/omarchy/.
  omarchy_dir="$here/build/omarchy/$OMARCHY_TAG"
  if [[ ! -f $omarchy_dir/shell/shell.qml ]]; then
    echo "== fetching omacom/omarchy $OMARCHY_TAG (shell/ and config/omarchy/) into $omarchy_dir"
    rm -rf "$omarchy_dir"; mkdir -p "$(dirname "$omarchy_dir")"
    git clone -q --depth 1 --filter=blob:none --sparse --branch "$OMARCHY_TAG" https://github.com/omacom/omarchy.git "$omarchy_dir"
    git -C "$omarchy_dir" sparse-checkout set --no-cone shell config/omarchy
  fi
  echo "   omarchy $OMARCHY_TAG at $(git -C "$omarchy_dir" rev-parse HEAD)"
fi

echo "== ext4 image from the tarball (unprivileged user namespace)"
# Everything in this heredoc runs as the root user inside the namespace, so the tarball's
# root-owned files extract with their real ownership and mke2fs records it.
unshare --user --map-root-user --map-auto bash -eu -s "$tarball" "$work" "$image" "$DISTRO_ID" "$profile" "$omarchy_dir" "$live" "$upgrade_dir" "$here/scripts" <<'INNER'
tarball=$1 work=$2 image=$3 id=$4 profile=$5 omarchy_dir=$6 live=$7 upgrade_dir=$8 scripts=$9
upgrade=0; [ -n "$upgrade_dir" ] && upgrade=1
root="$work/root"
mkdir "$root"
# Device nodes cannot be created in a user namespace, and the guest kernel mounts devtmpfs
# over /dev anyway, so the tarball's ./dev entries are skipped.
tar -xf "$tarball" -C "$root" --exclude='./dev/*'
if [ "$live" = 1 ]; then
  # The live tarball booted from a disk (see the comment above the unshare call).
  ln -sf /dev/null "$root/etc/systemd/system/casper-md5check.service"
  rm -f "$root/etc/xdg/autostart/$id-installer.desktop"
  echo "   live tarball: casper-md5check.service masked, the installer's autostart entry removed"
fi

# The oneshot unit that runs the checks and powers off. StandardOutput=tty with the console
# puts its output on the serial line that QEMU logs.
cat > "$root/usr/local/sbin/$id-boot-test" <<EOF
#!/bin/sh
# Kernel messages share the serial console with these lines; keep them off it from here on.
dmesg -n 1
echo "=== BOOT-TEST BEGIN"
echo "profile: $profile"
echo "kernel: \$(uname -r)"
. /etc/os-release
echo "os-release: PRETTY_NAME=\$PRETTY_NAME ID=\$ID ID_LIKE=\$ID_LIKE VERSION_CODENAME=\$VERSION_CODENAME"
echo "hostname: \$(hostname)"
# Not "is-system-running --wait": systemd counts startup as finished only once its job queue
# first drains, and this very unit's job sits in that queue, so --wait would never return.
# Instead wait until no job other than this unit's is pending.
for i in \$(seq 120); do
    pending=\$(systemctl list-jobs --no-legend --plain | grep -v '$id-boot-test' | awk '{print \$2}' | paste -sd' ')
    [ -z "\$pending" ] && break
    sleep 1
done
echo "pending jobs: [\$pending]"
echo "system: \$(systemctl is-system-running)"
echo "failed units: [\$(systemctl --failed --no-legend --plain | awk '{print \$1}' | paste -sd' ')]"
# Plymouth under the desktop's script theme (splash plymouth.debug on the command line): the
# crash seen on the Legion laptop (docs/7, choice 14) printed "backtrace:" from plymouthd and
# would show as a kernel segfault line; both counts must be 0. The log lines are information.
echo "plymouth crash: \$(( \$(journalctl -b -o cat _COMM=plymouthd 2>/dev/null | grep -c '^backtrace:') + \$(journalctl -b -k -o cat 2>/dev/null | grep -c 'plymouthd.*segfault') ))"
grep -h -i -o 'Using console viewer[^"]*\\|Not using console viewer[^"]*\\|starting boot animation\\|no pixel displays\\|loading theme [^"]*\\|using [a-z]* renderer[^"]*' /var/log/plymouth*.log 2>/dev/null | sort -u | head -6 | sed 's/^/plymouth log: /'
for u in apparmor NetworkManager systemd-resolved systemd-timesyncd dbus-broker; do
    echo "unit \$u: \$(systemctl is-active \$u)"
done
echo "apparmor profiles: \$(aa-status --profiled 2>/dev/null || echo 'aa-status failed')"
echo "network: \$(nmcli -t -f STATE general)"
nmcli -t -f DEVICE,TYPE,STATE device | sed 's/^/device: /'
echo "resolv.conf: \$(readlink /etc/resolv.conf)"
echo "apt sources: \$(ls /etc/apt/sources.list.d/ | paste -sd' ')"
if apt-get -q update >/tmp/apt-update.log 2>&1; then echo "apt update: ok"; else echo "apt update: FAILED"; cat /tmp/apt-update.log; fi
apt-cache policy $id-base | sed -n 's/^  Candidate: /$id-base candidate: /p'
apt-cache policy snapd | sed -n 's/^  Candidate: /snapd candidate: /p'
# Step 8: lsb_release on the base series reads the diverted os-release, so unattended-upgrades'
# \${distro_id} origins would name the distro; the base package's apt.conf.d file replaces them.
if command -v lsb_release >/dev/null; then echo "lsb_release: \$(lsb_release -is 2>/dev/null) \$(lsb_release -cs 2>/dev/null)"; else echo "lsb_release: not installed (base profile: lsb-release is not in the base set)"; fi
echo "unattended origins: \$(apt-config dump Unattended-Upgrade::Allowed-Origins 2>/dev/null | sed -n 's/^.*:: "\(.*\)";$/\1/p' | paste -sd' ')"
if command -v unattended-upgrade >/dev/null; then
  echo "unattended dry-run origins: \$(unattended-upgrade --dry-run --debug 2>&1 | sed -n 's/^Allowed origins are: //p' | head -1)"
fi
EOF
if [ "$profile" = session ] || [ "$profile" = desktop ]; then
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
echo "--- session"
echo "display-manager: \$(basename "\$(readlink /etc/systemd/system/display-manager.service)")"
echo "unit sddm: \$(systemctl is-active sddm)"
echo "gpu-manager result: \$(systemctl show -p Result --value gpu-manager)"
echo "drm devices: \$(ls /dev/dri/ | paste -sd' ')"
# SDDM logs the test user in (autologin file below); wait for logind to show that session.
sid=
for i in \$(seq 90); do
    sid=\$(loginctl list-sessions --no-legend | awk '\$3=="tester"{print \$1; exit}')
    [ -n "\$sid" ] && [ "\$(loginctl show-session "\$sid" -p Type --value)" = wayland ] && break
    sleep 1
done
echo "session: user=tester id=\${sid:-none} type=\$(loginctl show-session "\$sid" -p Type --value 2>/dev/null) desktop=\$(loginctl show-session "\$sid" -p Desktop --value 2>/dev/null)"
# uwsm runs the compositor as a unit of the user's systemd manager. Talk to that manager as
# the user through its runtime directory and bus (runuser, not "systemctl -M user@": every -M
# call opens a logind session of its own and prints a status line on the console).
as_user() { runuser -u tester -- env XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus "\$@"; }
for i in \$(seq 60); do
    as_user systemctl --user is-active graphical-session.target >/dev/null 2>&1 && break
    sleep 1
done
as_user systemctl --user list-units --no-legend --plain 'wayland-wm@*' 'wayland-session@*' 'graphical-session.target' 2>&1 | awk '{print "user unit " \$1 ": " \$3 " " \$4}'
# Commands in the user's session environment (HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY):
# Hyprland imports those into the user manager, and systemd-run --user inherits them.
run_user() { as_user systemd-run --user --pipe --wait --collect -q "\$@"; }
echo "hyprland: \$(run_user hyprctl version 2>/dev/null | sed -n 1p)"
echo "monitors: \$(run_user hyprctl -j monitors 2>/dev/null | python3 -c 'import json,sys; print(" ".join(m["name"]+"@"+m.get("description","").replace(" ","_") for m in json.load(sys.stdin)))' 2>/dev/null)"
run_user hyprctl systeminfo 2>/dev/null | sed -n '/^GPU information/{n;p;}' | sed 's/^/hyprland gpu: /'
if apt-get install -y -q x11-apps >/tmp/apt-install.log 2>&1; then echo "apt install x11-apps: ok"; else echo "apt install x11-apps: FAILED"; tail -5 /tmp/apt-install.log; fi
as_user systemd-run --user --collect -q -u $id-boot-test-xeyes xeyes 2>&1 | sed 's/^/xeyes start: /'
sleep 4
run_user hyprctl -j clients 2>/dev/null | python3 -c '
import json, sys
cs = json.load(sys.stdin)
x = [c for c in cs if c.get("class", "").lower() == "xeyes"]
print("xeyes client: class=%s xwayland=%s" % (x[0]["class"], str(x[0]["xwayland"]).lower()) if x else "xeyes client: none (%d clients)" % len(cs))'
# The portals start on demand: asking for an interface version on the user's bus starts
# xdg-desktop-portal and the backend that implements it.
echo "portal ScreenCast: \$(run_user busctl --user get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.ScreenCast version 2>&1)"
echo "portal FileChooser: \$(run_user busctl --user get-property org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop org.freedesktop.portal.FileChooser version 2>&1)"
sleep 2
for u in xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk; do
    echo "user unit \$u: \$(as_user systemctl --user is-active \$u 2>&1)"
done
echo "user unit gnome-keyring-daemon: \$(as_user systemctl --user is-active gnome-keyring-daemon.service 2>&1)"
# ReadAlias returns the object path of the collection named "default", or "/" when there is
# none yet: either answer proves the Secret Service is up (and the call opens no prompt).
echo "secret service ReadAlias default: \$(as_user busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service ReadAlias s default 2>&1 | paste -sd'|')"
EOF
fi
if [ "$profile" = session ]; then
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
# Omarchy's shell on the installed Quickshell (step 5). Started the way omarchy-launch-shell
# does (quickshell -n -p <shell dir>, file watcher and reload popup off), as a user unit so
# its output lands in the journal. The shell's omarchy-* helper scripts are not installed,
# so their calls fail; what is checked is that Quickshell loads the shell, answers the
# shell's own IPC ping, and the bar is on screen (a layer surface named omarchy-bar).
echo "quickshell: \$(quickshell --version 2>&1 | sed -n 1p)"
as_user systemd-run --user --collect -q -u $id-boot-test-omarchy-shell -p Environment=QS_DISABLE_FILE_WATCHER=1 -p Environment=QS_NO_RELOAD_POPUP=1 quickshell -n -p /usr/share/omarchy/shell 2>&1 | sed 's/^/omarchy shell start: /'
sleep 12
echo "omarchy shell unit: \$(as_user systemctl --user is-active $id-boot-test-omarchy-shell.service 2>&1)"
echo "omarchy shell ping: \$(run_user quickshell ipc -p /usr/share/omarchy/shell call shell ping 2>&1 | paste -sd'|')"
echo "omarchy shell layers: [\$(run_user hyprctl -j layers 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
ns = sorted({l["namespace"] for m in d.values() for lv in m["levels"].values() for l in lv if l["namespace"].startswith("omarchy-")})
print(" ".join(ns))' 2>/dev/null)]"
log=\$(journalctl -b _SYSTEMD_USER_UNIT=$id-boot-test-omarchy-shell.service --no-pager -o cat)
echo "omarchy shell log: \$(echo "\$log" | grep -c .) lines, \$(echo "\$log" | grep -ciE 'error|cannot|not a type|is not defined|no such file') matching error patterns"
echo "\$log" | grep -iE 'error|cannot|not a type|is not defined|no such file' | sed -E 's/^[^ ]+ [0-9:.]+ //' | cut -c1-150 | sort | uniq -c | sort -rn | head -n 10 | sed 's/^/omarchy shell log: /'
EOF
fi
if [ "$upgrade" = 1 ]; then
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
echo "--- upgrade in the running session"
# The visible widgets of the bar on screen, by id (the shell's debugBarGeometry IPC call).
bar_widgets() {
    run_user $id-shell shell debugBarGeometry 2>/dev/null | python3 -c '
import json, sys
v = [w["id"] for w in json.load(sys.stdin) if w.get("visible")]
print("%d visible: %s" % (len(v), " ".join(v)))' 2>/dev/null || echo "0 visible: (no answer)"
}
# The session as an installed system has it before its update: first-run done, the shell up.
for i in \$(seq 120); do
    [ -f /home/tester/.local/state/$id/done/first-run-user ] && run_user $id-shell shell ping >/dev/null 2>&1 && break
    sleep 1
done
from=\$(dpkg-query -W -f='\${Version}' $id-desktop)
echo "bar widgets before upgrade: \$(bar_widgets)"
shell_before=\$(pgrep -u tester -f 'quickshell.*-p /usr/share/$id/shell' | head -1)
# build/ as a flat archive (copied into the image), and the sudo rule an administrator's own
# password would stand for. verifypw=any: the update's stay-awake step runs "sudo -v" when its
# input is a terminal (the update runs itself under script(1), so it is), and with sudo's default
# verifypw=all that asks for a password whenever any matching entry lacks NOPASSWD, as
# /etc/sudoers' %sudo line does; the first try hung the update on that prompt (2026-10-17).
printf 'Types: deb\nURIs: file:/var/lib/$id-upgrade-test\nSuites: ./\nTrusted: yes\n' > /etc/apt/sources.list.d/$id-upgrade-test.sources
printf 'Defaults:tester verifypw=any\ntester ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/90-$id-boot-test
chmod 0440 /etc/sudoers.d/90-$id-boot-test
# The user's update in the environment the user manager got at login, which a terminal opened
# before the update also has.
# A prompt nobody answers would hang it: after 8 minutes the test goes on with exit 124 and the log.
timeout 480 runuser -u tester -- env XDG_RUNTIME_DIR=/run/user/1001 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemd-run --user --pipe --wait --collect -q -u $id-boot-test-update $id-update -y > /tmp/update.log 2>&1
echo "update exit: \$?"
to=\$(dpkg-query -W -f='\${Version}' $id-desktop)
echo "upgrade: \$from -> \$to"
echo "upgrade changed: \$([ "\$from" != "\$to" ] && echo yes || echo no)"
errors=\$(sed 's/\x1b\[[0-9;]*m//g' /tmp/update.log | grep -E 'unbound variable|config not found|command not found|Something went wrong|No such file or directory|did not become ready')
echo "update log errors: \$(printf '%s' "\$errors" | grep -c .)"
printf '%s\n' "\$errors" | grep . | head -n 10 | sed 's/^/update log: /'
sed 's/\x1b\[[0-9;]*m//g' /tmp/update.log | tail -n 8 | sed 's/^/update log tail: /'
sleep 3
shell_after=\$(pgrep -u tester -f 'quickshell.*-p /usr/share/$id/shell' | head -1)
echo "shell restarted: \$([ -n "\$shell_after" ] && [ "\$shell_after" != "\$shell_before" ] && echo yes || echo no)"
EOF
fi
if [ "$profile" = desktop ]; then
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
echo "--- desktop"
echo "apply-system unit: \$(systemctl show -p Result --value $id-boot-test-prepare.service)"
journalctl -b -u $id-boot-test-prepare.service --no-pager -o cat | grep -iE 'fail|error|not found|no such' | head -n 8 | sed 's/^/apply-system journal: /'
grep -c 'Completed:' /var/log/$id-install.log | sed 's/^/apply-system completed scripts: /'
grep 'Failed:' /var/log/$id-install.log | sed 's/^/apply-system: /'
echo "version: \$($id-version 2>&1)"
echo "packages: \$(dpkg-query -W -f='\${Package} \${Version}\n' $id-fonts asdcontrol hyprland-preview-share-picker nwg-displays 2>&1 | paste -sd'|')"
# The icon font keeps Omarchy's family name, "omarchy", for plugins written for Omarchy (docs/6, choice 86).
echo "fonts: jetbrains=\$(fc-list | grep -c JetBrainsMonoNerdFont) icon=\$(fc-list : family | grep -cx omarchy)"
echo "pam lock files: \$(ls /etc/pam.d/ | grep "^$id-lock" | paste -sd' ')"
# ufw on from the next boot, with LocalSend's port (step 6, choice 40): apply-system's firewall.sh
# adds two rules to user.rules and sets ENABLED=yes; ufw.service already ran this boot, so the
# rules load at the next one.
# Wi-Fi power save off (step 6, choice 42): the port's conf.d file overrides Ubuntu's
# default-wifi-powersave-on.conf in NetworkManager's merged configuration.
echo "wifi powersave: \$(NetworkManager --print-config 2>/dev/null | grep -o '^wifi.powersave *= *[0-9]' | tail -n1 | tr -d ' ')"
echo "ufw: \$(systemctl is-enabled ufw 2>/dev/null) \$(grep -o '^ENABLED=.*' /etc/ufw/ufw.conf) localsend=\$(grep -c '^-A ufw-user-input -p [a-z]* --dport 53317 -j ACCEPT' /etc/ufw/user.rules)"
# Ubuntu's configuration where the port once carried Omarchy's (step 6, "Ubuntu's configuration"):
# bash's own skel .bashrc with our .bash_aliases beside it, no zram device, no sysctl file of
# ours, and unattended-upgrades enabled by its own postinst.
echo "ubuntu defaults: bashrc=\$(dpkg -S /etc/skel/.bashrc | cut -d: -f1) aliases=\$([ -f /etc/skel/.bash_aliases ] && echo yes || echo no) zram=\$([ -e /dev/zram0 ] && echo yes || echo no) sysctl=\$(ls /etc/sysctl.d | grep -c $id) auto-upgrades=\$(grep -c 'Unattended-Upgrade \"1\"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null)"
# systemd-oomd's scope (step 6, choice 45): the user manager is not a kill candidate, the user's
# app.slice is.
echo "oomd scope: user@=\$(systemctl show "user@\$(id -u tester).service" -p ManagedOOMMemoryPressure --value) app.slice=\$(as_user systemctl --user show app.slice -p ManagedOOMMemoryPressure --value)"
# SSH keepalive (step 6, choice 46): the effective client options for any host.
echo "ssh keepalive: \$(as_user ssh -G example.invalid 2>/dev/null | grep -E '^(serveraliveinterval|serveralivecountmax|connecttimeout) ' | sort | paste -sd' ')"
echo "inotify watches: \$(sysctl -n fs.inotify.max_user_watches)"
echo "tcp mtu probing: \$(sysctl -n net.ipv4.tcp_mtu_probing)"
echo "font switch: \$(as_user sh -c 'mkdir -p /home/tester/.config/fontconfig && printf "%s\n" "<?xml version=\"1.0\"?><fontconfig><match target=\"pattern\"><test name=\"family\" qual=\"any\"><string>monospace</string></test><edit name=\"family\" mode=\"prepend_first\" binding=\"strong\"><string>Noto Mono</string></edit></match></fontconfig>" > /home/tester/.config/fontconfig/fonts.conf && fc-match monospace -f "%{family[0]}"; rm -f /home/tester/.config/fontconfig/fonts.conf')"
echo "font list icon fonts: \$($id-font-list | grep -c -i -E 'material icons|font awesome')"
echo "mise source: \$(apt-cache policy mise 2>/dev/null | awk '/\*\*\*/{getline; print \$2; exit}')"
echo "fingerprint profile: \$(sed -n 's/^\t\[success=1 default=ignore\]\t\(pam_exec.so quiet .*\)/\1/p' /usr/share/pam-configs/$id-fprintd 2>/dev/null)"
# The user's session environment, as the ported session file and uwsm set it up.
echo "session env: \$(as_user systemctl --user show-environment 2>/dev/null | grep -E '^(OMARCHY_PATH|XDG_CURRENT_DESKTOP)=' | paste -sd' ')"
echo "hyprland config: \$(run_user hyprctl -j getoption general:border_size 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("border_size=%s" % d.get("int"))' 2>/dev/null)"
# The shell the port's autostart launched: its process, its IPC ping, its layers.
echo "shell process: \$(pgrep -u tester -f 'quickshell.*-p /usr/share/$id/shell' | head -1 | sed 's/.*/running/')"
echo "shell ping: \$(run_user $id-shell shell ping 2>&1 | paste -sd'|')"
echo "shell layers: [\$(run_user hyprctl -j layers 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
ns = sorted({l["namespace"] for m in d.values() for lv in m["levels"].values() for l in lv if l["namespace"].startswith("$id-")})
print(" ".join(ns))' 2>/dev/null)]"
# First-run: the done marker, the theme it set, the user units it enabled.
for i in \$(seq 60); do [ -f /home/tester/.local/state/$id/done/first-run-user ] && break; sleep 1; done
echo "first-run done: \$([ -f /home/tester/.local/state/$id/done/first-run-user ] && echo yes || echo no)"
echo "first-run log: \$(grep -c 'Failed' /home/tester/.local/state/$id/first-run.log 2>/dev/null) failed steps"
grep 'Failed' /home/tester/.local/state/$id/first-run.log 2>/dev/null | sed 's/^/first-run: /'
echo "theme: \$(cat /home/tester/.local/state/$id/current/theme.name 2>/dev/null)"
# A new user has no migrations to run: first-run marks the shipped ones done (2026-10-17: a new
# install offered all 12, twice). Then the login screen's input method (SDDM's default would show
# Qt's on-screen keyboard), the packages that brought that keyboard, and the user's failed units.
echo "pending migrations: \$(runuser -u tester -- env HOME=/home/tester $id-migrate --pending 2>/dev/null | grep -c .)"
echo "sddm input method: [\$(grep -h '^InputMethod=' /etc/sddm.conf.d/*.conf 2>/dev/null | tail -n 1)]"
echo "virtual keyboard packages: \$(dpkg-query -W -f='\${db:Status-Status}\n' budgie-sddm-theme qml6-module-qtquick-virtualkeyboard 2>/dev/null | grep -cx installed)"
echo "user failed units: [\$(as_user systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print \$1}' | paste -sd' ')]"
echo "background: \$(readlink /home/tester/.local/state/$id/current/background 2>/dev/null | sed 's|.*/themes/||')"
for u in $id-sleep-lock $id-migrate-notify $id-crash-watch; do
    echo "user unit \$u: \$(as_user systemctl --user is-enabled \$u.service 2>&1) \$(as_user systemctl --user is-active \$u.service 2>&1)"
done
# A live theme switch, then the menu.
run_user $id-theme-set Nord >/tmp/theme-set.log 2>&1; echo "theme-set exit: \$?"
# The DNS helper the network panel and the menu call runs as the user, through nmcli and
# NetworkManager's polkit rule for members of the sudo group: no sudoers rule, no root.
run_user $id-dns Cloudflare >/tmp/dns.log 2>&1; echo "dns set exit: \$?"
echo "dns provider: \$(run_user $id-dns)"
run_user $id-dns DHCP >>/tmp/dns.log 2>&1; echo "dns reset: \$(run_user $id-dns)"
echo "dns sudoers rule: \$(ls /etc/sudoers.d | grep -c dns)"
# The core/apps split (step 6, "Core and apps"): none of the removed preinstalls, Docker or the
# command-line preferences in the image (tmux and Neovim came back, choices 25 and 26, and btop,
# choice 43, so they are not in the list); only the three launchers Omarchy's own apps need.
# The tools restored by choices 43 and 47, each by the command its callers run.
echo "restored tools missing: [\$(for c in btop eza inxi lazygit starship zoxide ttfx swappy unzip gnome-calculator gnome-disks whois mise dua; do command -v \$c >/dev/null || printf '%s ' \$c; done)]"
# Both stores preconfigured (step 6, choice 17): snapd's socket enabled by its package, Flathub added
# system-wide at install from the repository file Ubuntu's flatpak package ships.
echo "stores: snapd=\$(systemctl is-enabled snapd.socket 2>/dev/null) flathub=\$(flatpak remotes --system --columns=name 2>/dev/null | grep -cx flathub)"
# dpkg-query -W prints a line for a package it merely knows of, so the status field is tested exactly.
echo "apps split: removed=\$(dpkg-query -W -f='\${db:Status-Status}\n' libreoffice kdenlive obs-studio xournalpp docker.io 2>/dev/null | grep -cx installed) launchers=\$(ls /usr/share/$id/applications | wc -l)"
sleep 3
echo "theme after switch: \$(cat /home/tester/.local/state/$id/current/theme.name 2>/dev/null)"
echo "shell ping after switch: \$(run_user $id-shell shell ping 2>&1 | paste -sd'|')"
echo "shell layers after switch: [\$(run_user hyprctl -j layers 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
ns = sorted({l["namespace"] for m in d.values() for lv in m["levels"].values() for l in lv if l["namespace"].startswith("$id-")})
print(" ".join(ns))' 2>/dev/null)]"
run_user $id-menu toggle >/dev/null 2>&1; sleep 3
echo "menu layer: \$(run_user hyprctl -j layers 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("yes" if any(l["namespace"] == "$id-menu" for m in d.values() for lv in m["levels"].values() for l in lv) else "no")' 2>/dev/null)"
run_user $id-menu toggle >/dev/null 2>&1
echo "update-available: \$(run_user $id-update-available 2>&1 | paste -sd'|') (exit \$?)"
# The bar's widgets on screen: a bar whose plugins failed to load still has its layer surface.
bar=\$(run_user $id-shell shell debugBarGeometry 2>/dev/null | python3 -c '
import json, sys
v = [w["id"] for w in json.load(sys.stdin) if w.get("visible")]
print("%d visible: %s" % (len(v), " ".join(v)))' 2>/dev/null || echo "0 visible: (no answer)")
echo "bar widgets: \$bar"
# The keybindings, as the user's hyprland.lua makes them (scripts/boot-test-bindings.lua).
if apt-get install -y -q lua5.4 >/tmp/apt-lua.log 2>&1; then echo "apt install lua5.4: ok"; else echo "apt install lua5.4: FAILED"; tail -5 /tmp/apt-lua.log; fi
as_user env HOME=/home/tester OMARCHY_PATH=/usr/share/$id lua5.4 /usr/local/share/$id-boot-test/bindings.lua /home/tester/.config/hypr/hyprland.lua > /tmp/bindings.tsv 2>/tmp/bindings.err
echo "bindings: \$(grep -c . /tmp/bindings.tsv) total, \$(awk -F'\t' '\$3 != ""' /tmp/bindings.tsv | grep -c .) run a command"
head -n 3 /tmp/bindings.err | sed 's/^/bindings error: /'
# Every program those commands run, looked up in Hyprland's own environment: the checker is
# started the way a key press starts a command.
rm -f /tmp/binding-check.out
run_user hyprctl dispatch 'hl.dsp.exec_cmd("python3 /usr/local/share/$id-boot-test/bindings.py /tmp/bindings.tsv /tmp/binding-check.out")' >/dev/null 2>&1
for i in \$(seq 50); do [ -s /tmp/binding-check.out ] && break; sleep 0.2; done
cat /tmp/binding-check.out 2>/dev/null || echo "binding programs: no report"
# Each binding that opens a menu or a shell panel, run through Hyprland as a key press runs it:
# it must exit 0 and put something new on screen, a layer surface (L:<namespace>) or a window
# (C:<class>). A menu route can name an entry that runs an action (Background, Theme, Set a
# reminder), which opens its own picker instead of the menu. Each is closed before the next. A
# panel whose widget is not in the bar (the power panel, with no battery in QEMU) has nothing to
# open from, so its binding is reported as skipped.
surfaces() {
    { run_user hyprctl -j layers 2>/dev/null | python3 -c '
import json, sys
for m in json.load(sys.stdin).values():
    for lv in m["levels"].values():
        for l in lv: print("L:" + l["namespace"])' 2>/dev/null
      run_user hyprctl -j clients 2>/dev/null | python3 -c '
import json, sys
for c in json.load(sys.stdin): print("C:%s:%s" % (c.get("class", ""), c.get("pid", "")))' 2>/dev/null
    } | sort -u
}
run_binding() {
    rm -f /tmp/bind-rc
    { printf '%s\n' "\$1"; echo 'echo \$? > /tmp/bind-rc'; } > /tmp/bind-run.sh
    run_user hyprctl dispatch 'hl.dsp.exec_cmd("sh /tmp/bind-run.sh")' >/dev/null 2>&1
    for i in \$(seq 50); do [ -f /tmp/bind-rc ] && break; sleep 0.1; done
    cat /tmp/bind-rc 2>/dev/null || echo none
}
tab=\$(printf '\t')
# Keys and command only: read treats a tab as whitespace, so an empty description would vanish.
awk -F'\t' -v id=$id '\$3 ~ "^" id "-menu toggle" || \$3 ~ "^" id "-shell shell toggle " { print \$1 "\t" \$3 }' /tmp/bindings.tsv > /tmp/bindings-run.tsv
while IFS="\$tab" read -r keys cmd; do
    surfaces > /tmp/surfaces-before
    rc=\$(run_binding "\$cmd")
    sleep 1.5
    surfaces > /tmp/surfaces-after
    opened=\$(comm -13 /tmp/surfaces-before /tmp/surfaces-after | sed 's/^\(C:[^:]*\):.*/\1/' | paste -sd' ')
    # Closed through the shell: the menu's close call, the image selector's cancel call (the
    # Background picker) and the reminder flow's hide; then the same binding again (a toggle),
    # and a window the binding opened is ended by its process id.
    run_user $id-menu close >/dev/null 2>&1
    run_user $id-shell -q image-selector cancel "" >/dev/null 2>&1
    run_user $id-shell -q shell hide omarchy.reminders >/dev/null 2>&1
    sleep 0.5
    surfaces > /tmp/surfaces-now
    if ! cmp -s /tmp/surfaces-before /tmp/surfaces-now; then run_binding "\$cmd" >/dev/null; sleep 1; fi
    for c in \$(comm -13 /tmp/surfaces-before /tmp/surfaces-after | sed -n 's/^C:[^:]*:\([0-9][0-9]*\)\$/\1/p'); do kill \$c 2>/dev/null; done
    sleep 0.5
    surfaces > /tmp/surfaces-now
    closed=\$(cmp -s /tmp/surfaces-before /tmp/surfaces-now && echo yes || echo no)
    note=""
    case "\$cmd" in
        "$id-shell shell toggle "*)
            panel=\${cmd##* }
            case " \${bar#*: } " in *" \$panel "*) ;; *) [ -z "\$opened" ] && note=" skipped=not-in-bar" ;; esac ;;
    esac
    echo "binding run: \$keys: exit=\$rc opened=[\$opened] closed=\$closed\$note"
done < /tmp/bindings-run.tsv
echo "shell ping after bindings: \$(run_user $id-shell shell ping 2>&1 | paste -sd'|')"
# The shell's journal: Quickshell's WARN lines are listed, its ERROR/CRIT lines and QML
# failures (a type that failed to load, an undefined reference) are counted.
log=\$(journalctl -b -t $id-shell --no-pager -o cat | sed 's/\x1b\[[0-9;]*m//g')
echo "shell log: \$(echo "\$log" | grep -c .) lines, \$(echo "\$log" | grep -cE 'ERROR|CRIT|FATAL|not a type|is not defined|failed to load') errors, \$(echo "\$log" | grep -c ' WARN') warnings"
echo "\$log" | grep -E 'ERROR|CRIT|FATAL|not a type|is not defined|failed to load|WARN' | cut -c1-150 | sort | uniq -c | sort -rn | head -n 10 | sed 's/^/shell log: /'
journalctl -b _UID=1001 --no-pager -o cat -p err | tail -n 12 | sed 's/^/journal tester (errors): /'
EOF
fi
if [ "$profile" = session ] || [ "$profile" = desktop ]; then
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
ud=\$(ubuntu-drivers devices 2>&1); udrc=\$?
echo "ubuntu-drivers devices: [\$(echo "\$ud" | paste -sd'|')]"
echo "ubuntu-drivers exit: \$udrc"
di=\$($id-drivers-install --show 2>&1 | grep -v aplay); dirc=\$?
echo "drivers-install show: [\$(echo "\$di" | paste -sd'|')]"
echo "drivers-install exit: \$dirc"
echo "--- journal excerpts"
journalctl -b -u sddm --no-pager -o cat -n 12 | sed 's/^/journal sddm: /'
journalctl -b _UID=1001 --no-pager -o cat -p warning | tail -n 12 | sed 's/^/journal tester (warnings): /'
EOF
fi
cat >> "$root/usr/local/sbin/$id-boot-test" <<EOF
echo "=== BOOT-TEST END"
systemctl poweroff
EOF
chmod 0755 "$root/usr/local/sbin/$id-boot-test"
# A timer starts the service, not multi-user.target.wants: a unit inside the boot transaction
# cannot wait for that transaction to finish ("systemctl is-system-running --wait" would hang).
cat > "$root/etc/systemd/system/$id-boot-test.service" <<EOF
[Unit]
Description=$id root filesystem boot test
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/$id-boot-test
StandardOutput=tty
StandardError=tty
TTYPath=/dev/console
EOF
cat > "$root/etc/systemd/system/$id-boot-test.timer" <<EOF
[Unit]
Description=$id root filesystem boot test trigger

[Timer]
OnBootSec=1s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
mkdir -p "$root/etc/systemd/system/timers.target.wants"
ln -s "../$id-boot-test.timer" "$root/etc/systemd/system/timers.target.wants/$id-boot-test.timer"
# No login prompt on the serial line: the getty would write its banner over the test output.
ln -s /dev/null "$root/etc/systemd/system/serial-getty@ttyS0.service"

if [ "$profile" = session ] || [ "$profile" = desktop ]; then
    # A test user for SDDM to log in automatically. Written straight into the account files
    # (no useradd: the tree is not booted), with a locked password: the autologin PAM stack
    # (/etc/pam.d/sddm-autologin) asks for none.
    echo "tester:x:1001:1001:boot test user:/home/tester:/bin/bash" >> "$root/etc/passwd"
    echo "tester:!:20000:0:99999:7:::" >> "$root/etc/shadow"
    echo "tester:x:1001:" >> "$root/etc/group"
    echo "tester:!::" >> "$root/etc/gshadow"
    # An installed user is an administrator: the sudo group, which the port's sudoers rules
    # (passwordless theme and DNS actions from the menu) are written for.
    sed -i 's/^sudo:x:27:$/sudo:x:27:tester/' "$root/etc/group"
    sed -i 's/^sudo:\*::$/sudo:*::tester/' "$root/etc/gshadow"
    mkdir -p "$root/home/tester"
    chown 1001:1001 "$root/home/tester"
    chmod 0750 "$root/home/tester"
    # SDDM reads every file in /etc/sddm.conf.d/; this one adds autologin to the packaged
    # Wayland settings. hyprland-uwsm.desktop is the session file Ubuntu's hyprland package
    # ships under /usr/share/wayland-sessions/.
    if [ "$profile" = desktop ]; then session_file="$id.desktop"; else session_file=hyprland-uwsm.desktop; fi
    cat > "$root/etc/sddm.conf.d/90-$id-boot-test.conf" <<EOF
[Autologin]
User=tester
Session=$session_file
EOF
fi
if [ "$profile" = session ]; then
    # Omarchy's shell at the path its default/hypr/paths.lua assumes when OMARCHY_PATH is
    # unset (/usr/share/omarchy), so the shell finds config/omarchy/shell.json by itself.
    mkdir -p "$root/usr/share/omarchy/config"
    cp -a "$omarchy_dir/shell" "$root/usr/share/omarchy/shell"
    cp -a "$omarchy_dir/config/omarchy" "$root/usr/share/omarchy/config/omarchy"
fi
if [ "$profile" = desktop ]; then
    # The keybinding lister and checker the desktop checks run (see the header).
    mkdir -p "$root/usr/local/share/$id-boot-test"
    cp "$scripts/boot-test-bindings.lua" "$root/usr/local/share/$id-boot-test/bindings.lua"
    cp "$scripts/boot-test-bindings.py" "$root/usr/local/share/$id-boot-test/bindings.py"
    # build/'s packages for the update inside the session (UPGRADE=1); apt's source for them is
    # added by the guest just before the update, so first-run cannot install from them.
    [ "$upgrade" = 1 ] && cp -a "$upgrade_dir" "$root/var/lib/$id-upgrade-test"
    # What useradd -m does: the user's home seeded from /etc/skel, which the config package
    # populated (.bashrc, .config, launchers, toggles, branding).
    cp -a "$root/etc/skel/." "$root/home/tester/"
    chown -R 1001:1001 "$root/home/tester"
    # The root-side setup the installer runs on a new system, before the display manager starts.
    cat > "$root/etc/systemd/system/$id-boot-test-prepare.service" <<EOF
[Unit]
Description=$id boot test: apply-system before the display manager
Before=display-manager.service
After=local-fs.target systemd-tmpfiles-setup.service

[Service]
Type=oneshot
ExecStart=/usr/bin/$id-apply-system --install-user tester --first-install
StandardOutput=journal
StandardError=journal
EOF
    mkdir -p "$root/etc/systemd/system/display-manager.service.wants"
    ln -s "../$id-boot-test-prepare.service" "$root/etc/systemd/system/display-manager.service.wants/$id-boot-test-prepare.service"
fi

# Sparse file; mke2fs -d copies the tree in. The test root mounts rw from the kernel
# command line, so no fstab is needed.
# The update inside the session (UPGRADE=1) refuses to start with less than 10 GiB free
# (<id>-update-requires-free-space), so that image is twice the size.
size=16G; [ "$upgrade" = 1 ] && size=32G
truncate -s "$size" "$image"
mke2fs -q -F -t ext4 -L "$id-test" -d "$root" "$image"
rm -rf "$root"
INNER
echo "   $(du -h "$image" | cut -f1) used in $image"

gpu=()
if [[ $profile == session || $profile == desktop ]]; then
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
    gpu=(-device virtio-vga-gl -display "egl-headless,rendernode=$rendernode")
    echo "== GPU: virtio-vga-gl with virgl through $rendernode"
  else
    gpu=(-device virtio-vga -display none)
    echo "== GPU: virtio-vga without virgl ($rendernode not writable); Mesa renders in software"
  fi
else
  gpu=(-display none)
fi

echo "== booting in QEMU (serial log: $serial, timeout ${timeout_s}s, ${mem} MiB)"
set +e
timeout "$timeout_s" qemu-system-x86_64 \
  -enable-kvm -cpu host -machine q35 -smp 2 -m "$mem" \
  -kernel "$work/vmlinuz" -initrd "$work/initrd.img" \
  -append "root=/dev/vda rw console=ttyS0 systemd.show_status=true splash plymouth.debug" \
  -drive "file=$image,if=virtio,format=raw" \
  -nic user,model=virtio-net-pci \
  "${gpu[@]}" -serial "file:$serial" -no-reboot
qemu_rc=$?
set -e
if (( qemu_rc == 124 )); then
  echo "!! QEMU hit the ${timeout_s}s timeout; last lines of the serial log:" >&2
  tail -n 30 "$serial" >&2; exit 1
fi

echo "== results"
if ! grep -q "=== BOOT-TEST END" "$serial"; then
  echo "!! the boot test never finished; last lines of the serial log:" >&2
  tail -n 30 "$serial" >&2; exit 1
fi
# systemd's own status lines on the console carry colour escapes; the checks' lines never do.
report=$(sed -n '/=== BOOT-TEST BEGIN/,/=== BOOT-TEST END/p' "$serial" | tr -d '\r' | grep -av $'\e\\[')
echo "$report"

fail=0
check() { grep -q -- "$1" <<< "$report" || { echo "!! expected: $1" >&2; fail=1; }; }
check "^pending jobs: \[\]$"
check "^system: \(running\|starting\)$"
check "^failed units: \[\]$"
check "^os-release: PRETTY_NAME=$DISTRO_NAME $BASE_VERSION ID=$DISTRO_ID ID_LIKE=ubuntu debian VERSION_CODENAME=$BASE_SERIES$"
check "^unit apparmor: active$"
check "^unit NetworkManager: active$"
check "^unit systemd-resolved: active$"
check "^network: connected$"
check "^apt update: ok$"
check "^lsb_release: \($DISTRO_NAME $BASE_SERIES\|not installed\)"
check "^unattended origins: Ubuntu:$BASE_SERIES Ubuntu:$BASE_SERIES-security UbuntuESMApps:$BASE_SERIES-apps-security UbuntuESM:$BASE_SERIES-infra-security$"
check "^$DISTRO_ID-base candidate: "
check "^snapd candidate: [0-9]"   # snapd is part of the desktop (step 6, choice 17)
if [[ $profile == session || $profile == desktop ]]; then
  check "^display-manager: sddm.service$"
  check "^unit sddm: active$"
  check "^session: user=tester id=[0-9]* type=wayland"
  check "^user unit wayland-wm@.*\.service: active running$"
  check "^user unit wayland-session@.*\.target: active active$"
  check "^user unit graphical-session.target: active active$"
  check "^monitors: .*Virtual-1"
  check "^apt install x11-apps: ok$"
  check "^xeyes client: class=.* xwayland=true$"
  check "^portal ScreenCast: u [0-9]"
  check "^portal FileChooser: u [0-9]"
  check "^user unit xdg-desktop-portal: active$"
  check "^user unit xdg-desktop-portal-hyprland: active$"
  check "^user unit xdg-desktop-portal-gtk: active$"
  check "^user unit gnome-keyring-daemon: active$"
  check "^secret service ReadAlias default: o \"/.*\"$"
  check "^ubuntu-drivers exit: 0$"
  check "^drivers-install show: \[driver: ubuntu-drivers default .*|packages: \]$"
fi
if [[ $profile == session ]]; then
  check "^quickshell: .*0\\.3\\.2"
  check "^omarchy shell unit: active$"
  check "^omarchy shell ping: ok$"
  check "^omarchy shell layers: \\[.*omarchy-bar"
fi
if [[ $profile == desktop ]]; then
  check "^plymouth crash: 0$"
  check "^apply-system unit: success$"
  check "^version: $(dpkg-parsechangelog -l "$here/packages/desktop/debian/changelog" -S Version | sed 's/[.]/\\&/g')$"
  check "^fonts: jetbrains=[4-9] icon=1$"
  check "^pam lock files: $DISTRO_ID-lock-password$"
  check "^ufw: enabled ENABLED=yes localsend=2$"
  check "^wifi powersave: wifi.powersave=2$"
  check "^oomd scope: user@=auto app.slice=kill$"
  check "^ssh keepalive: connecttimeout 10 serveralivecountmax 3 serveraliveinterval 15$"
  check "^inotify watches: 524288$"
  check "^tcp mtu probing: 1$"
  check "^font switch: Noto Mono$"
  check "^font list icon fonts: 0$"
  check "^mise source: https://mise.jdx.dev/deb$"
  check "^fingerprint profile: pam_exec.so quiet /usr/bin/$DISTRO_ID-hw-laptop-closed$"
  check "^ubuntu defaults: bashrc=bash aliases=yes zram=no sysctl=2 auto-upgrades=1$"
  # OMARCHY_PATH keeps Omarchy's name, for plugins written for Omarchy (docs/6, choice 86).
  check "^session env: .*OMARCHY_PATH=/usr/share/$DISTRO_ID"
  check "^shell process: running$"
  check "^shell ping: ok$"
  check "^shell layers: \\[.*$DISTRO_ID-bar"
  check "^first-run done: yes$"
  check "^first-run log: 0 failed steps$"
  check "^pending migrations: 0$"
  check "^sddm input method: \[InputMethod=\]$"
  # A fresh image only: a system updated from an older release keeps budgie-sddm-theme and the
  # virtual keyboard it brought (apt removes nothing a new Provides makes unneeded); there
  # InputMethod= keeps the keyboard off the login screen (docs/4, choice 15).
  [[ $upgrade == 1 ]] || check "^virtual keyboard packages: 0$"
  check "^user failed units: \[\]$"
  check "^theme: tokyo-night$"
  check "^user unit $DISTRO_ID-sleep-lock: enabled active$"
  check "^theme-set exit: 0$"
  check "^dns set exit: 0$"
  check "^dns provider: Cloudflare$"
  check "^dns reset: DHCP$"
  check "^dns sudoers rule: 0$"
  # Five launcher files: Omarchy's four, plus the one that hides NVIDIA's settings launcher.
  check "^apps split: removed=0 launchers=5$"
  check "^restored tools missing: \[\]$"
  check "^stores: snapd=enabled flathub=1$"
  check "^theme after switch: nord$"
  check "^shell ping after switch: ok$"
  check "^shell layers after switch: \\[.*$DISTRO_ID-background.*$DISTRO_ID-bar"
  check "^menu layer: yes$"
  # Omarchy's bar layout (config/omarchy/shell.json) has 14 widgets; some hide when what they show
  # is absent (Bluetooth, a battery, a second keyboard layout), so at least 4, the clock among them.
  check "^bar widgets: \([4-9]\|[1-9][0-9]\) visible: .*omarchy\.clock"
  check "^apt install lua5.4: ok$"
  check "^bindings: [1-9][0-9][0-9] total, [1-9][0-9]* run a command$"
  check "^binding programs: [1-9][0-9]* checked, 0 missing$"
  runs=$(grep -c '^binding run: ' <<< "$report" || true)
  (( runs >= 10 )) || { echo "!! expected at least 10 menu and panel bindings run, got $runs" >&2; fail=1; }
  if grep -E '^binding run: ' <<< "$report" | grep -Ev ': exit=0 (opened=\[[^]]+\] closed=yes|opened=\[\] closed=yes skipped=not-in-bar)$' >&2; then
    echo "!! expected: every menu and panel binding above exits 0, opens something and closes again" >&2; fail=1
  fi
  check "^binding run: SUPER + SPACE: exit=0 opened=\[.*L:$DISTRO_ID-menu"
  check "^shell ping after bindings: ok$"
  check "^shell log: [0-9]* lines, 0 errors, "
fi
if [[ $upgrade == 1 ]]; then
  check "^update exit: 0$"
  check "^upgrade changed: yes$"
  check "^update log errors: 0$"
  check "^shell restarted: yes$"
fi
[[ ${KEEP:-0} == 1 ]] || rm -rf "$work"
if (( fail )); then echo "!! boot test FAILED"; exit 1; fi
echo "== boot test passed"
