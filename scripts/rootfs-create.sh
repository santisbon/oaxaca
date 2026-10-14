#!/usr/bin/env bash
# rootfs-create.sh: build the root filesystem tarball (roadmap steps 3 and 4).
#
# Anatomy: this script runs mmdebstrap once, in unshare mode (no root privileges). mmdebstrap
# downloads the minbase variant of Ubuntu's archive (apt, dpkg and the Essential and
# Priority: required packages), then installs the .deb files from build/ that make the
# system ours, chosen by PROFILE:
#   base     <id>-archive-keyring, <id>-apt-source, <id>-base (step 3): the base metapackage's
#            dependency list pulls in the kernel, shim, GRUB, systemd, AppArmor, NetworkManager
#            and PipeWire from the Ubuntu archive.
#   session  the base profile plus <id>-nvidia and <id>-session (step 4): Mesa, Hyprland,
#            Xwayland, uwsm, SDDM, the desktop portals and ubuntu-drivers.
#   desktop  the session profile plus the Omarchy port (step 6): <id>-desktop and the four
#            packages built with it, <id>-fonts, and the third-party packages it depends on
#            (asdcontrol, hyprland-preview-share-picker, nwg-displays); the metapackage's
#            dependency list then pulls the applications from the Ubuntu archive.
# Hooks then set the hostname, the locale, the time zone, apt's sources file and the resolver
# symlink. The manifest is written inside the chroot and fetched with mmdebstrap's "download"
# hook, because a plain redirect from a hook to a file under the home directory is denied in
# unshare mode. The result is build/rootfs/<id>-<version>-<arch>-<profile>.tar plus a
# .manifest listing every installed package. No bootloader is written to any disk: that is
# the image step (roadmap step 7).
#
# Usage: scripts/rootfs-create.sh
# Env:   PROFILE                 base | session | desktop | live (default live, the newest layer: the
#                                desktop plus casper and the installer, what the ISO is made from)
#        UBUNTU_MIRROR           default http://archive.ubuntu.com/ubuntu
#        UBUNTU_SECURITY_MIRROR  default http://security.ubuntu.com/ubuntu
#        ROOTFS_COMPONENTS       default "main restricted universe multiverse" (multiverse: nvtop,
#                                intel-media-va-driver-non-free, steam-installer)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
# The hook commands below run under sh with mmdebstrap's environment, so what they need is exported.
export DISTRO_ID
# A LOCPATH in the host's environment reaches the maintainer scripts inside the chroot, and glibc
# ignores /usr/lib/locale/locale-archive whenever LOCPATH is set, so the locales package's check of
# its freshly generated en_US.UTF-8 fails. Some shells set it (this was found under Claude Code).
unset LOCPATH

arch=amd64
profile=${PROFILE:-live}
extra_hooks=()
case $profile in
  base) parts="archive-keyring apt-source base"; debs="" ;;
  session) parts="archive-keyring apt-source base hybrid-backlight nvidia session"; debs="quickshell" ;;
  # plymouth, libplymouth5 and plymouth-label are our rebuild of Ubuntu's Plymouth with one
  # upstream patch (packages/plymouth: the script plugin no longer crashes without a console
  # viewer); the three depend on each other at the exact version, so they travel together.
  desktop) parts="archive-keyring apt-source base hybrid-backlight nvidia session fonts desktop tools shell themes config"
           debs="quickshell asdcontrol hyprland-preview-share-picker nwg-displays plymouth libplymouth5 plymouth-label" ;;
  # live: the desktop plus casper's live session and the installer, the tree the ISO's squashfs
  # is made from (scripts/iso-create.sh). The initramfs is rebuilt at the end so that casper's
  # hooks, installed in the same run as the kernel, are in the image the ISO boots.
  # calamares, calamares-data, libcalamares3.3 and libcalamaresui3.3 are our rebuild of Ubuntu's
  # Calamares with one patch (packages/calamares: Replace mode no longer crashes when encryption
  # is confirmed after a partition was chosen); they depend on each other at the exact version.
  # libkpmcore13 is our rebuild of Ubuntu's KPMcore, the library Calamares partitions with
  # (packages/kpmcore: one patch so encrypted installs work in every partitioning mode).
  live) parts="archive-keyring apt-source base hybrid-backlight nvidia session fonts desktop tools shell themes config live installer"
        debs="quickshell asdcontrol hyprland-preview-share-picker nwg-displays plymouth libplymouth5 plymouth-label libkpmcore13 calamares calamares-data libcalamares3.3 libcalamaresui3.3"
        extra_hooks=(--customize-hook='chroot "$1" update-initramfs -u -k all') ;;
  *) echo "unknown PROFILE '$profile' (base, session, desktop or live)" >&2; exit 1 ;;
esac
mirror=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
security=${UBUNTU_SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu}
components=${ROOTFS_COMPONENTS:-"main restricted universe multiverse"}
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
out_dir="$here/build/rootfs"
out="$out_dir/$DISTRO_ID-$BASE_VERSION-$arch-$profile.tar"
manifest="${out%.tar}.manifest"
tmp="${out%.tar}.tmp.tar"

# The packages of ours that go in, from build/ (make build). mmdebstrap takes a .deb
# path in --include when the path starts with /, and the file-mirror-automount hook copies
# that file into the chroot so dpkg inside can read it. In unshare mode apt runs as a
# subordinate uid that must be able to read the .deb, and a home directory with mode 0750
# (Ubuntu's default) blocks that, so the files are staged in a world-readable directory
# under /tmp for the duration of the run.
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
stage=$(mktemp -d /tmp/"$DISTRO_ID"-rootfs-debs.XXXXXX)
chmod 0755 "$stage"
trap 'rm -rf "$stage"' EXIT
includes=()
for part in $parts; do
  deb=$(newest_deb "$here/build/$DISTRO_ID-${part}_"*_all.deb)
  if [[ -z $deb ]]; then
    echo "no $DISTRO_ID-$part .deb in build/: run 'make build' first" >&2; exit 1
  fi
  install -m 0644 "$deb" "$stage/"
  includes+=("--include=$stage/$(basename "$deb")")
done
# Third-party packages we rebuild keep their upstream names (policy, naming rules), so they
# are listed by name: build/<name>_<version>_<arch>.deb.
for name in $debs; do
  deb=$(newest_deb "$here/build/${name}_"*.deb)
  if [[ -z $deb ]]; then
    echo "no $name .deb in build/: run 'make build' first" >&2; exit 1
  fi
  install -m 0644 "$deb" "$stage/"
  includes+=("--include=$stage/$(basename "$deb")")
done

# apt's sources file for the installed system, in deb822 format, the same layout Ubuntu's
# installer writes to /etc/apt/sources.list.d/ubuntu.sources: the release pocket plus
# -updates from the archive mirror, -security from the security mirror.
ubuntu_sources=$(cat <<EOF
Types: deb
URIs: $mirror
Suites: $BASE_SERIES $BASE_SERIES-updates
Components: $components
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: $security
Suites: $BASE_SERIES-security
Components: $components
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
)

export UBUNTU_SOURCES="$ubuntu_sources"

mkdir -p "$out_dir"
rm -f "$tmp"
echo "creating $out (profile $profile) from $mirror ($BASE_SERIES, $BASE_SERIES-updates, $BASE_SERIES-security; $components)"
mmdebstrap \
  --mode=unshare \
  --variant=minbase \
  --architectures="$arch" \
  --keyring="$keyring" \
  --aptopt='APT::Install-Recommends "false"' \
  --hook-dir=/usr/share/mmdebstrap/hooks/file-mirror-automount \
  "${includes[@]}" \
  --essential-hook='printf "%s\n" "locales locales/default_environment_locale select en_US.UTF-8" "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8" "tzdata tzdata/Areas select Etc" "tzdata tzdata/Zones/Etc select UTC" | chroot "$1" debconf-set-selections' \
  --customize-hook='echo "$DISTRO_ID" > "$1/etc/hostname"' \
  --customize-hook='printf "127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\tlocalhost ip6-localhost ip6-loopback\n" "$DISTRO_ID" > "$1/etc/hosts"' \
  --customize-hook='rm -f "$1/etc/resolv.conf" && ln -s ../run/systemd/resolve/stub-resolv.conf "$1/etc/resolv.conf"' \
  --customize-hook='rm -f "$1/etc/apt/sources.list" "$1/etc/apt/apt.conf.d/99mmdebstrap" && printf "%s\n" "$UBUNTU_SOURCES" > "$1/etc/apt/sources.list.d/ubuntu.sources"' \
  "${extra_hooks[@]}" \
  --customize-hook='chroot "$1" dpkg-query -W -f="\${Package}\t\${Version}\n" > "$1/manifest.tmp"' \
  --customize-hook="download /manifest.tmp $manifest" \
  --customize-hook='rm "$1/manifest.tmp"' \
  "$BASE_SERIES" "$tmp" \
  "deb $mirror $BASE_SERIES $components" \
  "deb $mirror $BASE_SERIES-updates $components" \
  "deb $security $BASE_SERIES-security $components"
mv "$tmp" "$out"
echo "done: $(du -h "$out" | cut -f1) $out ($(wc -l < "$manifest") packages, list in $manifest)"
