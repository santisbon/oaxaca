#!/usr/bin/env bash
# build-prune.sh: keep only the newest build of each package in build/.
#
# Anatomy: build.sh writes each build's files into build/ and never deletes an earlier build's, and
# every reader of build/ (repo-publish.sh, rootfs-create.sh, rootfs-boot-test.sh, upgrade-test.sh)
# takes the newest version of each package by dpkg's version order, which is also the one version
# repo-publish.sh leaves published. This script deletes the rest, in build/'s top level only:
#   - binary packages: every .deb but the newest per package name and architecture, read with
#     dpkg-deb -f (so an epoch, which the file name leaves out, still counts);
#   - source packages: every .dsc but the newest per source name (its Version field), with the
#     files that .dsc lists (.tar.xz, .debian.tar.xz, .orig*.tar.*) unless the newest .dsc lists
#     them too, and the source version's .changes, .buildinfo and .build logs;
#   - unpacked source trees: build/<source>-<upstream version>/ (build.sh's tree for packages
#     with an orig tarball, such as the desktop) for every upstream version but the newest's.
# Subfolders (apt-cache/, rootfs/, iso/, git/ and the rest) and files that match none of the above
# stay. The newest build of each package is what make publish uploaded, and make repo-seed puts
# the published packages back into build/ should it be lost.
#
# Usage: scripts/build-prune.sh [--dry-run]   (make prune [PRUNE_FLAGS=--dry-run])
#   --dry-run  list what would be deleted, delete nothing
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
dir="$here/build"
dry=0
[[ ${1:-} == --dry-run ]] && dry=1
[[ -d $dir ]] || exit 0
shopt -s nullglob

declare -a doomed=()

# Binary packages: newest per name and architecture.
declare -A best bestv
for f in "$dir"/*.deb; do
  read -r name ver arch < <(dpkg-deb -f "$f" Package Version Architecture | awk -F': ' '{printf "%s ", $2} END {print ""}')
  k="$name $arch"
  if [[ -z ${best[$k]:-} ]]; then
    best[$k]=$f bestv[$k]=$ver
  elif dpkg --compare-versions "$ver" gt "${bestv[$k]}"; then
    doomed+=("${best[$k]}"); best[$k]=$f bestv[$k]=$ver
  else
    doomed+=("$f")
  fi
done

# Source packages: newest .dsc per source name.
dsc_field() { awk -v f="$1" -F': ' '$1 == f {print $2; exit}' "$2"; }
dsc_files() { awk '/^Files:/ {on=1; next} /^[^ ]/ {on=0} on && NF == 3 {print $3}' "$1"; }
declare -A srcbest srcv
for f in "$dir"/*.dsc; do
  src=$(dsc_field Source "$f"); ver=$(dsc_field Version "$f")
  if [[ -z ${srcbest[$src]:-} ]] || dpkg --compare-versions "$ver" gt "${srcv[$src]}"; then
    srcbest[$src]=$f srcv[$src]=$ver
  fi
done
declare -A keep=()
for src in "${!srcbest[@]}"; do
  while read -r g; do keep[$g]=1; done < <(dsc_files "${srcbest[$src]}")
done
for f in "$dir"/*.dsc; do
  src=$(dsc_field Source "$f")
  [[ $f == "${srcbest[$src]}" ]] && continue
  doomed+=("$f")
  while read -r g; do
    [[ -n ${keep[$g]:-} || ! -e $dir/$g ]] || doomed+=("$dir/$g")
  done < <(dsc_files "$f")
done
for src in "${!srcbest[@]}"; do
  newest=${srcv[$src]#*:}
  upstream=${newest%-*}
  # .changes, .buildinfo and .build logs are named <source>_<version without epoch>_<arch>...
  for f in "$dir/${src}"_*.changes "$dir/${src}"_*.buildinfo "$dir/${src}"_*.build; do
    v=${f##*/}; v=${v#"${src}_"}; v=${v%%_*}
    [[ $v == "$newest" ]] || doomed+=("$f")
  done
  for d in "$dir/${src}"-[0-9]*/; do
    d=${d%/}
    [[ ${d##*/} == "$src-$upstream" ]] || doomed+=("$d")
  done
done

if ((${#doomed[@]} == 0)); then
  echo "build/: nothing older to remove"
  exit 0
fi
size=$(du -csh "${doomed[@]}" | tail -1 | cut -f1)
if ((dry)); then
  printf 'would remove %s\n' "${doomed[@]#"$here/"}"
  echo "build/: would remove ${#doomed[@]} older files and folders ($size)"
  exit 0
fi
rm -rf -- "${doomed[@]}"
echo "build/: removed ${#doomed[@]} older files and folders ($size), kept the newest build of each package ($(du -sh "$dir" | cut -f1) left)"
