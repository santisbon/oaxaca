#!/usr/bin/env bash
# repo-publish.sh: add the packages in build/ to the apt repository, sign it, and upload it to
# the S3 bucket that serves it (infra/apt-repo/README.md).
#
# Anatomy: aptly keeps a database and a package pool under ~/.local/state/<id>/aptly. This
# script adds the newest version of each package in build/ (.deb files and .dsc source packages,
# chosen by dpkg's version order, so older builds still lying in build/ are never published) to
# the local repo and removes every older version of those packages from it, so the repository
# offers one version of each. It takes a snapshot and publishes it (aptly writes dists/ and pool/
# under its public/ directory and signs the Release file with the archive key from distro.conf,
# asking gpg for the apt signing key passphrase). With --push, the aws-cli's "s3 sync" uploads public/ to the
# bucket APT_S3_BUCKET, in three passes so a client never reads an index that names a missing
# file: pool/ first, then dists/, then pool/ again with --delete to drop the files no index
# names any more. Without --push, the same sync runs with --dryrun and lists what would change.
#
# Before adding anything, the script fetches the published Packages index from APT_URL and
# refuses a .deb whose name and version are already published with different content: apt
# clients identify a package by name and version, so installed systems would never see the
# new file, and a client holding the old index would fail the hash check on download. The
# only honest fix is a version bump (scripts/version-check.sh). --replace overrides, for a
# package that no installed system can have yet (before the first release).
#
# Usage: scripts/repo-publish.sh [--push] [--replace]
# Env:   AWS_PROFILE  the aws-cli profile for the upload (default APT_AWS_PROFILE in distro.conf)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
[[ -n ${APT_KEY_FPR:-} ]] || { echo "APT_KEY_FPR is empty in distro.conf: run scripts/keygen.sh first" >&2; exit 1; }

root="${APTLY_ROOT:-$HOME/.local/state/$DISTRO_ID/aptly}"
cfg="$root/aptly.conf"
mkdir -p "$root"
[[ -f $cfg ]] || printf '{ "rootDir": "%s", "gpgProvider": "gpg" }\n' "$root" > "$cfg"
aptly() { command aptly -config="$cfg" "$@"; }

repo="$DISTRO_ID"
if ! aptly repo show "$repo" >/dev/null 2>&1; then
  aptly repo create -distribution="$BASE_SERIES" -component="$APT_COMPONENT" "$repo"
fi

push=0 replace=0
for arg in "$@"; do
  case $arg in
    --push) push=1 ;;
    --replace) replace=1 ;;
    *) echo "unknown option $arg (--push, --replace)" >&2; exit 1 ;;
  esac
done

shopt -s nullglob
# The newest .deb per package name and the newest .dsc per source name, by dpkg's version order
# (sort -V ranks "4.0.4+git…" below "4.0.4-0…", where dpkg ranks it above).
declare -A best_file best_ver
for f in "$here"/build/*.deb "$here"/build/*.dsc; do
  if [[ $f == *.deb ]]; then
    name=$(dpkg-deb -f "$f" Package); ver=$(dpkg-deb -f "$f" Version); key="deb:$name"
  else
    name=$(sed -n 's/^Source: //p' "$f" | head -1); ver=$(sed -n 's/^Version: //p' "$f" | head -1); key="dsc:$name"
  fi
  if [[ -z ${best_ver[$key]:-} ]] || dpkg --compare-versions "$ver" gt "${best_ver[$key]}"; then
    best_file[$key]=$f; best_ver[$key]=$ver
  fi
done
files=("${best_file[@]}")
((${#files[@]})) || { echo "nothing in build/ to publish (run 'make build')" >&2; exit 1; }

# The guard: same name and version as published, different SHA-256.
index=$(mktemp)
trap 'rm -f "$index"' EXIT
if curl -sSfL --max-time 30 -o "$index" "$APT_URL/dists/$BASE_SERIES/$APT_COMPONENT/binary-amd64/Packages"; then
  clash=()
  for deb in "${files[@]}"; do
    [[ $deb == *.deb ]] || continue
    base=$(basename "$deb")
    name=${base%%_*}; rest=${base#*_}; version=${rest%%_*}
    published=$(awk -v n="$name" -v v="$version" '
      /^Package:/ {p=$2} /^Version:/ {ver=$2} /^SHA256:/ {if (p==n && ver==v) print $2}' "$index")
    [[ -n $published ]] || continue
    local_sum=$(sha256sum "$deb" | cut -d' ' -f1)
    [[ $local_sum == "$published" ]] || clash+=("$name $version")
  done
  if ((${#clash[@]})); then
    printf 'already published with different content: %s\n' "${clash[@]}" >&2
    if ((replace)); then
      echo "--replace given: publishing over them anyway" >&2
    else
      echo "bump the version (debian/changelog.in, then make build), or pass --replace if no installed system can have these" >&2
      exit 1
    fi
  fi
else
  echo "no published index at $APT_URL yet (or unreachable): skipping the same-version check" >&2
fi
aptly repo add -force-replace "$repo" "${files[@]}"
# One version per package: drop what is older than the version just added.
for key in "${!best_ver[@]}"; do
  name=${key#*:}
  aptly repo remove "$repo" "Name (= $name), \$Version (<< ${best_ver[$key]})" >/dev/null
done

base="$repo-$(date +%Y%m%dT%H%M%S)"
snap="$base"; n=1
while aptly snapshot show "$snap" >/dev/null 2>&1; do n=$((n + 1)); snap="$base-$n"; done
aptly snapshot create "$snap" from repo "$repo"
# aptly derives the architecture list from the packages, and "all" is not an architecture,
# so a repo of arch-independent packages would publish nothing. Name them explicitly.
archs="amd64,source"
if aptly publish list -raw | grep -q " $BASE_SERIES\$"; then
  aptly publish switch -gpg-key="$APT_KEY_FPR" "$BASE_SERIES" "$snap"
else
  aptly publish snapshot -gpg-key="$APT_KEY_FPR" -origin="$APT_ORIGIN" -label="$APT_LABEL" \
    -distribution="$BASE_SERIES" -architectures="$archs" "$snap"
fi

# aptly's own pool keeps files no package references any more; drop them.
aptly db cleanup >/dev/null

public="$root/public"
command -v aws >/dev/null || { echo "published locally to $public; the aws-cli is needed to upload it" >&2; exit 1; }
export AWS_PROFILE=${AWS_PROFILE:-$APT_AWS_PROFILE}
export AWS_REGION=$APT_S3_REGION
bucket="s3://$APT_S3_BUCKET"
if ((push)); then
  aws s3 sync --only-show-errors "$public/pool" "$bucket/pool"
  aws s3 sync --only-show-errors --delete "$public/dists" "$bucket/dists"
  aws s3 sync --only-show-errors --delete "$public/pool" "$bucket/pool"
  echo "uploaded $snap to $bucket; apt reads it at $APT_URL"
else
  echo "published locally to $public; what an upload would change in $bucket:"
  { aws s3 sync --dryrun --delete "$public/pool" "$bucket/pool"; aws s3 sync --dryrun --delete "$public/dists" "$bucket/dists"; } \
    | sed 's/^(dryrun) //' | awk '{print $1}' | sort | uniq -c
  echo "upload with: make publish PUBLISH_FLAGS=--push"
fi
