#!/usr/bin/env bash
# version-check.sh: fail when a package directory changed since the last release tag without a
# version bump (roadmap step 8).
#
# Anatomy: this script runs git and dpkg only. The last release is the newest v* tag reachable
# from HEAD (git describe). For every directory under packages/ that differs from that tag
# (git diff --quiet), the first line of its rendered debian/changelog at HEAD must carry a
# version that dpkg --compare-versions ranks above the version in the same file at the tag. A
# package directory whose upstream file names a release .deb (DEB=, published unchanged) has no
# debian/changelog; its version is the one in the .deb's file name, <package>_<version>_<arch>.deb.
# Why: apt identifies a package by name and version; a package rebuilt with new content under a
# version users already have is never offered to them (scripts/repo-publish.sh refuses to
# publish such a file for the same reason). A directory that did not change needs no bump, and
# a package new since the tag passes.
#
# Blind spot, by design: packages/desktop builds the fork's branch named in its upstream file
# (REF=<branch>), so a change on that branch alone leaves this repository unchanged and passes
# here. The publish guard catches that case by content, and PORT.md asks for a changelog entry
# with every port change.
#
# Usage: scripts/version-check.sh        (make check-versions; CI's prepare job)
# Env:   VERSION_CHECK_TAG  a ref to compare against instead of the newest v* tag
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

# VERSION_CHECK_TAG=<ref> compares against that ref instead (used to exercise the script before the first tag).
tag=${VERSION_CHECK_TAG:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}
if [[ -z $tag ]]; then
  echo "version-check: no v* tag reachable from HEAD, nothing to compare against"
  exit 0
fi
echo "version-check: comparing against $tag"

version_of() { sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p'; }
deb_version_of() { sed -n 's|^DEB=.*/[^_/]*_\([^_]*\)_[^_]*\.deb$|\1|p'; }

status=0
for dir in packages/*; do
  [[ -d $dir ]] || continue
  name=$(basename "$dir")
  if git diff --quiet "$tag" -- "$dir"; then
    continue
  fi
  if grep -q '^DEB=' "$dir/upstream" 2>/dev/null; then
    new=$(deb_version_of < "$dir/upstream")
    old=$(git show "$tag:$dir/upstream" 2>/dev/null | deb_version_of || true)
    bump="point DEB= in its upstream file at a newer release"
  else
    new=$(version_of < "$dir/debian/changelog")
    old=$(git show "$tag:$dir/debian/changelog" 2>/dev/null | version_of || true)
    bump="add a debian/changelog.in entry"
  fi
  if [[ -z $old ]]; then
    echo "  $name: new since $tag ($new)"
    continue
  fi
  if dpkg --compare-versions "$new" gt "$old"; then
    echo "  $name: changed, $old -> $new"
  else
    echo "  $name: CHANGED since $tag but the version is still $new (was $old at $tag): $bump"
    status=1
  fi
done
((status == 0)) && echo "version-check: ok"
exit $status
