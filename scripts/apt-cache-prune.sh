#!/usr/bin/env bash
# apt-cache-prune.sh: keep only the newest version of each package in the folder of .deb files
# that rootfs-create.sh and upgrade-test.sh share as apt's package cache (build/apt-cache/).
#
# Anatomy: each mmdebstrap run copies that folder into its chroot's /var/cache/apt/archives/
# (mmdebstrap's sync-in hook) before apt downloads anything, so apt fetches only the packages
# the folder lacks, then copies the chroot's /var/cache/apt/archives/ back out (sync-out). The
# copy back adds each new version of a package and keeps the old one, so after every run this
# script deletes, for each package name and architecture, every .deb but the newest by dpkg's
# version order (dpkg --compare-versions). It reads the name, version and architecture from
# apt's file name, <name>_<version>_<arch>.deb, where apt writes a version's epoch colon as
# "%3a". A package no build installs any more keeps its one newest file; make clean (rm -rf
# build) empties the folder.
#
# Usage: scripts/apt-cache-prune.sh <folder>
set -euo pipefail
dir=${1:?usage: apt-cache-prune.sh <folder>}
[[ -d $dir ]] || exit 0

declare -A best bestv
removed=0
for f in "$dir"/*.deb; do
  [[ -f $f ]] || continue
  b=${f##*/}; b=${b%.deb}
  name=${b%%_*}; arch=${b##*_}
  v=${b#*_}; v=${v%_*}; v=${v//%3a/:}
  k="$name $arch"
  if [[ -z ${best[$k]:-} ]]; then
    best[$k]=$f bestv[$k]=$v
  elif dpkg --compare-versions "$v" gt "${bestv[$k]}"; then
    rm -f "${best[$k]}"; removed=$((removed + 1))
    best[$k]=$f bestv[$k]=$v
  else
    rm -f "$f"; removed=$((removed + 1))
  fi
done
echo "apt cache: removed $removed older .deb files, kept ${#best[@]} in $dir ($(du -sh "$dir" | cut -f1))"
