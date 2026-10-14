#!/usr/bin/env bash
# chroot-create.sh: build the clean chroot tarball that sbuild's unshare mode uses.
#
# Anatomy: `make build` runs sbuild. In unshare mode sbuild unpacks a tarball from
# ~/.cache/sbuild/<series>-<arch>.tar inside an unprivileged user namespace and builds
# there, so no root is needed. This script creates that tarball with mmdebstrap from the
# Ubuntu archive: the buildd variant (build-essential and friends), main + universe, with
# the -updates and -security pockets, and Recommends off.
#
# Usage: scripts/chroot-create.sh [--force]    (skips the work if the tarball is under 7 days old)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"

arch=amd64
mirror=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
out="$HOME/.cache/sbuild/$BASE_SERIES-$arch.tar"
max_age_days=7

if [[ ${1:-} != --force && -f $out ]]; then
  age_days=$(( ( $(date +%s) - $(stat -c %Y "$out") ) / 86400 ))
  if (( age_days < max_age_days )); then
    echo "chroot tarball is $age_days day(s) old, keeping it: $out (use --force to rebuild)"
    exit 0
  fi
fi

mkdir -p "$(dirname "$out")"
rm -f "${out%.tar}.tmp.tar"
# mmdebstrap picks "tarball" vs "directory" from the target's extension, so the temp name must end in .tar
tmp="${out%.tar}.tmp.tar"
echo "creating $out from $mirror ($BASE_SERIES, $BASE_SERIES-updates, $BASE_SERIES-security)"
mmdebstrap \
  --variant=buildd \
  --architectures="$arch" \
  --keyring="$keyring" \
  --aptopt='APT::Install-Recommends "false"' \
  "$BASE_SERIES" "$tmp" \
  "deb $mirror $BASE_SERIES main universe" \
  "deb $mirror $BASE_SERIES-updates main universe" \
  "deb $mirror $BASE_SERIES-security main universe"
mv "$tmp" "$out"
echo "done: $(du -h "$out" | cut -f1) $out"
