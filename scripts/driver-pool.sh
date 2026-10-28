#!/usr/bin/env bash
# driver-pool.sh: put the NVIDIA driver packages on the installation medium, so that the
# installer's drivers step works without a network (docs/7, choice 20).
#
# Anatomy: tar extracts the desktop root filesystem tarball's apt configuration (etc/apt), dpkg
# status file and Ubuntu's archive keyring into build/iso/pool-work/root, and the host's apt-get
# and apt-cache run as the user with APT_CONFIG pointing at those files, so apt resolves against
# the tarball's installed packages, preferences and apt.conf.d, not the host's. apt-get update
# fetches Ubuntu's package lists (the tarball ships none), apt-cache finds the newest NVIDIA open
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
# And the root filesystem tools the installer's snapshots step adds for the filesystem chosen
# (packages/installer/snapshots-setup): btrfs-progs and Timeshift on btrfs, xfsprogs on xfs, which
# the installed system's layer does not carry (docs/7, choice 55). The tarball given is the
# desktop one, that installed system, so every closure is relative to what an installation has.
#
# And every package the installer's system step installs that the installed system lacks: that
# step runs <id>-apply-system, which runs the install-time scripts under /usr/share/<id>/install
# (config, hardware, login, post-install), and those scripts install packages with <id>-pkg-add,
# such as libmfx-gen1.2 on Intel HD Graphics (docs/7, choice 64). The package names are read from
# the scripts in the tarball, so a new script's packages join the pool with no edit here. An
# argument to <id>-pkg-add that is not a literal package name fails the build, because the
# script's packages could not be known here, and so does a named package that ends up neither
# in the tarball nor in the pool. One package is exempt: firmware-b43-installer downloads
# Broadcom's firmware while it installs, so the 2012 and early-2013 MacBooks that get it need a
# network at install whatever the pool holds.
#
# No chroot and no user namespace: Ubuntu's AppArmor (kernel.apparmor_restrict_unprivileged_userns=1)
# gives a namespace that /usr/bin/unshare makes from an unconfined terminal no capabilities, so the
# chroot's mounts failed ("unshare: cannot change root filesystem propagation: Permission denied",
# 2026-10-22, from foot); the step passed before only from Wave Terminal, whose snap profile, in
# complain mode, let unshare keep them.
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
rm -rf "$work" "$pool"; mkdir -p "$work" "$pool"
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
root="$work/root"
mkdir -p "$root"
tar -xf "$tarball" -C "$root" ./etc/apt ./var/lib/dpkg/status ./var/lib/dpkg/arch ./usr/share/keyrings/ubuntu-archive-keyring.gpg
# Ubuntu's archive only: the distro's own packages come from build/ (local/), and the image's
# sources entry for the distro's apt repository would make this step depend on what is published
# there (a repository not yet published answered 404, and apt update failed the ISO build).
find "$root/etc/apt/sources.list.d" -name '*.sources' ! -name ubuntu.sources -delete
# Signed-By names the keyring by its path in the image; this apt runs on the host.
sed -i "s|^Signed-By: /usr/share/keyrings/|Signed-By: $root/usr/share/keyrings/|" "$root/etc/apt/sources.list.d/ubuntu.sources"
mkdir -p "$work/state/lists/partial" "$work/cache" "$root/pool/partial"
# APT_CONFIG is read before Dir::Etc's parts, so the tarball's apt.conf.d and preferences.d
# apply and the host's do not. The architectures are the tarball's (dpkg's arch file).
{
  echo "Dir::Etc \"$root/etc/apt\";"
  echo "Dir::State \"$work/state\";"
  echo "Dir::State::status \"$root/var/lib/dpkg/status\";"
  echo "Dir::Cache \"$work/cache\";"
  echo "Dir::Log \"$work/log\";"
  echo "Debug::NoLocking \"true\";"
  echo "APT::Architecture \"$(head -1 "$root/var/lib/dpkg/arch")\";"
  echo "APT::Architectures { $(sed 's/.*/"&";/' "$root/var/lib/dpkg/arch" | paste -sd' ') };"
} > "$work/apt.conf"
export APT_CONFIG="$work/apt.conf"
apt-get -q update >"$work/apt-update.log" 2>&1 || { echo "apt update: FAILED"; cat "$work/apt-update.log"; exit 1; }
kver=$(tar -tf "$tarball" | sed -n 's|^\./boot/vmlinuz-\(.*\)$|\1|p' | sort -V | tail -1)
echo "kernel: $kver"
best=""
for name in $(apt-cache search --names-only '^nvidia-driver-[0-9]+-open$' | cut -d' ' -f1 | LC_ALL=C sort -t- -k3,3n); do
  branch=${name#nvidia-driver-}; branch=${branch%-open}
  if apt-cache show "linux-modules-nvidia-$branch-open-$kver" >/dev/null 2>&1; then best=$branch; fi
done
[[ -n $best ]] || { echo "no NVIDIA open branch with prebuilt modules for $kver" >&2; exit 1; }
echo "branch: $best (nvidia-driver-$best-open, linux-modules-nvidia-$best-open-$kver)"
# --download-only with Dir::Cache::archives set: the closure relative to the installed set lands
# in pool/, nothing is installed. Recommends are in, as on the installed system (<id>-base 0.1.6
# and later), so the medium carries what an online install would add (nvidia-settings).
# The flavour metapackage too (linux-modules-nvidia-<branch>-open-generic): ubuntu-drivers takes
# the prebuilt modules only when that metapackage is among the kernel-specific package's reverse
# dependencies (get_linux_modules_metapackage in UbuntuDrivers/detect.py), and falls back to DKMS
# otherwise. Without it in the pool the drivers step installed nothing and nouveau drove the GPU
# (Legion laptop, 2026-10-12, docs/7 choice 36).
flavour=${kver#*-*-}
# The install-time scripts' packages (the header's last paragraph). The scripts come from the
# tarball, which holds them with the distro's command names (<id>-pkg-add).
network_only=" firmware-b43-installer "
mkdir -p "$work/scripts"
tar -xf "$tarball" -C "$work/scripts" "./usr/share/$DISTRO_ID/install/config" "./usr/share/$DISTRO_ID/install/hardware" \
  "./usr/share/$DISTRO_ID/install/login" "./usr/share/$DISTRO_ID/install/post-install"
install_pkgs=()
while IFS=: read -r file num text; do
  [[ $text =~ ^[[:space:]]*# ]] && continue
  read -ra names <<<"${text#*"$DISTRO_ID"-pkg-add}"
  for name in "${names[@]}"; do
    [[ $name =~ ^[a-z0-9][a-z0-9.+-]+$ ]] \
      || { echo "${file#"$work/scripts"}:$num: '$name' is not a package name; the pool cannot carry what this line installs" >&2; exit 1; }
    [[ $network_only == *" $name "* || " ${install_pkgs[*]} " == *" $name "* ]] || install_pkgs+=("$name")
  done
done < <(grep -rnE "(^|[^a-z-])$DISTRO_ID-pkg-add( |$)" "$work/scripts")
installed=$(awk '/^Package:/{p=$2} /^Status: install ok installed$/{print p}' "$root/var/lib/dpkg/status")
from_archive=() pool_needed=()
for name in "${install_pkgs[@]}"; do
  grep -qxF "$name" <<<"$installed" && continue
  pool_needed+=("$name")
  # One of ours, built in build/ (asusctl, qmk-hid): the newest .deb joins local/. Otherwise
  # Ubuntu's archive has it.
  deb=$(newest_deb "$here/build/${name}_"*.deb)
  if [[ -n $deb ]]; then cp "$deb" "$work/local/"; else from_archive+=("$name"); fi
done
echo "== install-time packages the tarball lacks: ${pool_needed[*]:-none}"
apt-get -q -y --install-recommends --download-only -o Dir::Cache::archives="$root/pool" \
  install "nvidia-driver-$best-open" "linux-modules-nvidia-$best-open-$flavour" "linux-modules-nvidia-$best-open-$kver" nvidia-vaapi-driver \
  btrfs-progs timeshift xfsprogs "${from_archive[@]}" "$work"/local/*.deb >"$work/apt-download.log" 2>&1 \
  || { echo "apt download: FAILED"; tail -20 "$work/apt-download.log"; exit 1; }
echo "$best" > "$root/pool/branch"
ls "$root/pool/"*.deb | wc -l | sed 's/^/debs: /'
cp "$work/root/pool/"*.deb "$pool/"
cp "$work/local/"*.deb "$pool/"
cp "$work/root/pool/branch" "$pool/branch"
(cd "$pool" && dpkg-scanpackages . /dev/null 2>/dev/null > Packages && gzip -9 -n -k Packages)
# The check: every package an install-time script installs is in the tarball or in the pool, so
# the installer's system step needs no network (docs/7, choice 64).
for name in "${pool_needed[@]}"; do
  grep -qxF "Package: $name" "$pool/Packages" \
    || { echo "$name: an install-time script installs it, and it is neither in the tarball nor in the pool" >&2; exit 1; }
done
# The license, at the pool's root as well as inside every package: the NVIDIA agreement's
# section 1.1(d) permits distributing the driver for use with OSI-licensed kernels provided
# the binaries are unmodified and "this Agreement is provided to each SOFTWARE recipient".
common=$(ls "$pool"/libnvidia-common-*.deb 2>/dev/null | head -1)
if [[ -n $common ]]; then
  dpkg-deb --fsys-tarfile "$common" | tar -xO --wildcards './usr/share/doc/libnvidia-common-*/copyright' > "$pool/LICENSE.NVIDIA"
fi
echo "   pool: $(ls "$pool"/*.deb | wc -l) packages, $(du -sh "$pool" | cut -f1), branch $(cat "$pool/branch")"
rm -rf "$work"
