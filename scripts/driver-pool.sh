#!/usr/bin/env bash
# driver-pool.sh: put the NVIDIA driver packages on the installation medium, so that the
# installer's drivers step works without a network (docs/7, choice 20).
#
# Anatomy: unshare opens an unprivileged user namespace (as scripts/drivers-check.sh does),
# extracts the live root filesystem tarball into build/iso/pool-work/root, mounts /proc and
# binds /dev, copies the host's resolv.conf in, and chroots. Inside, apt-get update fetches
# Ubuntu's package lists (the tarball ships none), apt-cache finds the newest NVIDIA open
# branch that has Canonical's prebuilt signed modules for the tarball's kernel (the choice
# <id>-drivers-install makes on a machine with an NVIDIA GPU: nvidia-driver-<branch>-open with
# linux-modules-nvidia-<branch>-open-<kernel>-generic), and apt-get install --download-only
# downloads that branch's dependency closure, relative to what the tarball already has, into
# a directory. The script copies the .deb files to build/iso/tree/pool/ and writes the flat
# archive index there with dpkg-scanpackages (Packages, no signature: the medium's own
# checksum file covers it, and the installer's apt source names it trusted). The ISO then
# carries pool/ at its root; on the booted medium that is /cdrom/pool, which <id>-drivers-
# install uses when present. The packages are Ubuntu's, unmodified, from the restricted
# component; their license (the NVIDIA "License For Customer Use of NVIDIA Software") permits
# copying and redistributing the Linux build unmodified, the clause Ubuntu's own images rely
# on, and each package carries that text in its copyright file.
#
# The pool also carries nvidia-vaapi-driver, which <id>-drivers-install adds after an NVIDIA
# driver, and the hardware packages (build/<id>-hw-*.deb, such as <id>-hw-legion) with their
# dependency closure from Ubuntu's archive, resolved in the same apt call as the driver, so that the installer's
# hardware step (packages/installer/hardware-install) installs the matching one without a
# network (docs/7, choice 41).
#
# Usage: scripts/driver-pool.sh <tarball> <pool dir>
# Env:   DRIVER_POOL=0 skips the pool (an ISO without the driver, for quick test builds).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
unset LOCPATH
tarball=$1 pool=$2
[[ -f $tarball ]] || { echo "no root filesystem tarball at $tarball" >&2; exit 1; }
command -v dpkg-scanpackages >/dev/null || { echo "dpkg-scanpackages is not installed (dpkg-dev)" >&2; exit 1; }
work="$here/build/iso/pool-work"
# The extracted tree's files belong to subordinate uids of the user namespace, so removing it
# takes the same namespace (the first run's leftovers failed a plain rm with EPERM).
nsrm() { unshare --user --map-root-user --map-auto rm -rf "$@"; }
nsrm "$work"; rm -rf "$pool"; mkdir -p "$work" "$pool"
# The newest of the given .deb files by dpkg's version order (dpkg --compare-versions), not by
# file name: sort -V ranks "4.0.4+git20261013-0oaxaca1" below "4.0.4-0oaxaca2" because "+"
# sorts before "-", where dpkg ranks it above, and the root filesystem got the older desktop.
newest_deb() {
  local best="" bestv="" f v
  for f in "$@"; do
    [[ -f $f ]] || continue
    v=$(dpkg-deb -f "$f" Version)
    if [[ -z $best ]] || dpkg --compare-versions "$v" gt "$bestv"; then best=$f bestv=$v; fi
  done
  printf '%s' "$best"
}
# Our hardware packages and the local packages they depend on, newest version of each.
local_debs=()
for name in $(cd "$here/build" && ls "$DISTRO_ID"-hw-*_all.deb 2>/dev/null | sed 's/_.*//' | sort -u); do
  deb=$(newest_deb "$here/build/${name}_"*_all.deb)
  [[ -n $deb ]] || { echo "no $name .deb in build/: run 'make build' first" >&2; exit 1; }
  local_debs+=("$deb")
done
mkdir -p "$work/local"
cp "${local_debs[@]}" "$work/local/"
echo "== hardware packages: $(cd "$work/local" && ls | tr '\n' ' ')"
echo "== driver pool: extracting $tarball into $work/root and resolving the NVIDIA branch in it"
unshare --user --map-root-user --map-auto --mount --pid --fork --propagation=private \
  bash -eu -s "$tarball" "$work" <<'INNER'
tarball=$1 work=$2
root="$work/root"
mkdir "$root"
tar -xf "$tarball" -C "$root" --exclude='./dev/*'
mount --rbind /dev "$root/dev"
mount -t proc proc "$root/proc"
rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf"
mkdir -p "$root/pool"
cp -r "$work/local" "$root/local"
chroot "$root" /bin/bash -e <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
# Ubuntu's archive only: the distro's own packages come from build/ (/local), and the image's
# sources entry for the distro's apt repository would make this step depend on what is published
# there (a repository not yet published answered 404, and apt update failed the ISO build).
find /etc/apt/sources.list.d -name '*.sources' ! -name ubuntu.sources -delete
apt-get -q update >/tmp/apt-update.log 2>&1 || { echo "apt update: FAILED"; cat /tmp/apt-update.log; exit 1; }
kver=$(ls /boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
echo "kernel: $kver"
best=""
for name in $(apt-cache search --names-only '^nvidia-driver-[0-9]+-open$' | cut -d' ' -f1 | sort -t- -k3,3n); do
    branch=${name#nvidia-driver-}; branch=${branch%-open}
    if apt-cache show "linux-modules-nvidia-$branch-open-$kver" >/dev/null 2>&1; then best=$branch; fi
done
[[ -n $best ]] || { echo "no NVIDIA open branch with prebuilt modules for $kver"; exit 1; }
echo "branch: $best (nvidia-driver-$best-open, linux-modules-nvidia-$best-open-$kver)"
# --download-only with Dir::Cache::archives set: the closure relative to the installed set lands
# in /pool, nothing is installed; --no-install-recommends matches the base image's apt.conf.
# The flavour metapackage too (linux-modules-nvidia-<branch>-open-generic): ubuntu-drivers takes
# the prebuilt modules only when that metapackage is among the kernel-specific package's reverse
# dependencies (get_linux_modules_metapackage in UbuntuDrivers/detect.py), and falls back to DKMS
# otherwise. Without it in the pool the drivers step installed nothing and nouveau drove the GPU
# (Legion laptop, 2026-10-12, docs/7 choice 36).
flavour=${kver#*-*-}
apt-get -q -y --no-install-recommends --download-only -o Dir::Cache::archives=/pool \
    install "nvidia-driver-$best-open" "linux-modules-nvidia-$best-open-$flavour" "linux-modules-nvidia-$best-open-$kver" nvidia-vaapi-driver /local/*.deb >/tmp/apt-download.log 2>&1 \
    || { echo "apt download: FAILED"; tail -20 /tmp/apt-download.log; exit 1; }
echo "$best" > /pool/branch
ls /pool/*.deb | wc -l | sed 's/^/debs: /'
CHROOT
INNER
cp "$work/root/pool/"*.deb "$pool/"
cp "$work/local/"*.deb "$pool/"
cp "$work/root/pool/branch" "$pool/branch"
(cd "$pool" && dpkg-scanpackages . /dev/null 2>/dev/null > Packages && gzip -9 -n -k Packages)
# The license, at the pool's root as well as inside every package: the NVIDIA agreement's
# section 1.1(d) permits distributing the driver for use with OSI-licensed kernels provided
# the binaries are unmodified and "this Agreement is provided to each SOFTWARE recipient".
common=$(ls "$pool"/libnvidia-common-*.deb 2>/dev/null | head -1)
if [[ -n $common ]]; then
  dpkg-deb --fsys-tarfile "$common" | tar -xO --wildcards './usr/share/doc/libnvidia-common-*/copyright' > "$pool/LICENSE.NVIDIA"
fi
echo "   pool: $(ls "$pool"/*.deb | wc -l) packages, $(du -sh "$pool" | cut -f1), branch $(cat "$pool/branch")"
nsrm "$work"
