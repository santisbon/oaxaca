#!/usr/bin/env bash
# drivers-check.sh: ask Ubuntu's driver detector, from inside the root filesystem tarball,
# what it would install for THIS machine's GPU, without booting anything (roadmap step 4
# verification, and the policy's question whether ubuntu-drivers still works with
# ID=<id> in os-release).
#
# Anatomy: unshare opens an unprivileged user namespace with its own mount and pid
# namespaces (no root privileges), extracts the tarball into build/rootfs/drivers-check/root,
# bind-mounts the host's /sys and /dev into that tree and mounts a fresh /proc, copies the
# host's resolv.conf in, then chroots and runs three commands as the namespace's root user:
#   apt-get update                        the tarball ships no package lists (mmdebstrap
#                                         removes them), and ubuntu-drivers reads apt's cache
#   ubuntu-drivers devices                reads the PCI ids under /sys (the host's, through
#                                         the bind mount) and prints the matching driver
#                                         packages with one marked "recommended"
#   apt-get --simulate install <list>     resolves the list "<id>-drivers-install" would pass
#                                         to apt against the tarball's apt sources, printing
#                                         what apt would install, downloading nothing
# Between the last two it runs "<id>-drivers-install --show" (from the <id>-nvidia package in
# the tarball), which prints the driver it would pass to ubuntu-drivers (the newest NVIDIA
# open branch with prebuilt modules) and the resulting package list; that list is what goes
# to the simulation. The script then checks that the chosen NVIDIA package resolves to
# Canonical's prebuilt signed modules (linux-modules-nvidia-*) and not to DKMS (nvidia-dkms-*,
# dkms). On a machine without an NVIDIA GPU the detector prints nothing to recommend and the
# script only reports.
#
# Usage: scripts/drivers-check.sh [tarball]   default: build/rootfs/<id>-<version>-amd64-<profile>.tar
# Env:   PROFILE (default live; the tarball must contain ubuntu-drivers-common: session, desktop or live), KEEP=1 keeps the tree
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
# See rootfs-create.sh: a LOCPATH in the environment breaks locale lookups inside the chroot.
unset LOCPATH

profile=${PROFILE:-live}
tarball=${1:-"$here/build/rootfs/$DISTRO_ID-$BASE_VERSION-amd64-$profile.tar"}
[[ -f $tarball ]] || { echo "no root filesystem tarball at $tarball: run 'make rootfs PROFILE=$profile' first" >&2; exit 1; }
work="$here/build/rootfs/drivers-check"
rm -rf "$work"; mkdir -p "$work"
report="$work/report.txt"

echo "== extracting $tarball into $work/root and running ubuntu-drivers in it (user namespace)"
unshare --user --map-root-user --map-auto --mount --pid --fork --propagation=private \
  bash -eu -s "$tarball" "$work" "$DISTRO_ID" "${KEEP:-0}" <<'INNER' | tee "$report"
tarball=$1 work=$2 id=$3 keep=$4
export id
root="$work/root"
mkdir "$root"
tar -xf "$tarball" -C "$root" --exclude='./dev/*'
# --rbind, not --bind: /sys carries submounts (cgroup2, securityfs, ...) that a user namespace
# may not hide, so a non-recursive bind of it is refused with EINVAL.
mount --rbind /sys "$root/sys"
mount --rbind /dev "$root/dev"
mount -t proc proc "$root/proc"
# The tarball's resolv.conf points at the stub resolver of a booted system; the host's
# works here because the chroot shares the host's network namespace.
rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf"
chroot "$root" /bin/sh -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
echo "os-release: ID=$ID PRETTY_NAME=$PRETTY_NAME"
echo "ubuntu-drivers-common: $(dpkg-query -W -f='${Version}' ubuntu-drivers-common)"
if apt-get -q update >/tmp/apt-update.log 2>&1; then echo "apt update: ok"; else echo "apt update: FAILED"; cat /tmp/apt-update.log; exit 1; fi
echo "--- ubuntu-drivers devices"
ubuntu-drivers devices 2>&1 | tee /tmp/devices.txt
echo "--- end"
# "ubuntu-drivers install" has no dry run; "<id>-drivers-install --show" prints the driver it
# chooses and the list it would hand to apt (the same library call command_install in
# /usr/bin/ubuntu-drivers makes, ubuntu-drivers-common 1:0.10.13), installing nothing.
echo "--- $id-drivers-install --show"
"/usr/sbin/$id-drivers-install" --show 2>&1 | tee /tmp/show.txt
echo "--- end"
sed -n 's/^packages: *//p' /tmp/show.txt | tr ' ' '\n' | grep . > /tmp/to-install.txt || true
echo "install list: [$(paste -sd' ' < /tmp/to-install.txt)]"
if grep -q . /tmp/to-install.txt; then
    # shellcheck disable=SC2046
    apt-get --simulate install $(cat /tmp/to-install.txt) > /tmp/simulate.txt 2>&1 || { echo "apt simulate: FAILED"; tail -5 /tmp/simulate.txt; exit 1; }
    echo "apt simulate: ok, $(grep -c '^Inst ' /tmp/simulate.txt) packages would be installed"
    echo "prebuilt modules: [$(grep -o '^Inst linux-modules-nvidia-[^ ]*' /tmp/simulate.txt | cut -d' ' -f2 | paste -sd' ')]"
    echo "dkms packages: [$(grep -o '^Inst \(nvidia-dkms-[^ ]*\|dkms\) ' /tmp/simulate.txt | cut -d' ' -f2 | paste -sd' ')]"
    echo "driver userspace: [$(grep -o '^Inst \(nvidia-driver-[^ ]*\|libnvidia-gl-[^ ]*\|nvidia-utils-[^ ]*\)' /tmp/simulate.txt | cut -d' ' -f2 | paste -sd' ')]"
else
    echo "install list: empty"
fi
CHROOT
# The extracted files belong to subordinate uids, so only this namespace can delete them,
# and only after the bind mounts are gone (or rm would walk into the host's /sys and /dev).
umount -l "$root/proc" "$root/dev" "$root/sys"
[ "$keep" = 1 ] || rm -rf "$root"
INNER

echo "== results"
fail=0
check() { grep -q -- "$1" "$report" || { echo "!! expected: $1" >&2; fail=1; }; }
check "^os-release: ID=$DISTRO_ID "
check "^apt update: ok$"
if grep -q "^install list: \[.*nvidia-" "$report"; then
  check "^driver: nvidia:[0-9]*-open (newest NVIDIA open branch with prebuilt modules)$"
  check "^apt simulate: ok"
  check "^prebuilt modules: \[linux-modules-nvidia-"
  check "^dkms packages: \[\]$"
else
  echo "   no NVIDIA driver recommended on this machine; nothing more to check"
fi
if (( fail )); then echo "!! drivers check FAILED"; exit 1; fi
echo "== drivers check passed (report in $report)"
