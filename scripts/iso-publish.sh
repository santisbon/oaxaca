#!/usr/bin/env bash
# iso-publish.sh: upload the installation ISO the last make iso built, with signed checksums, to the
# downloads host (ISO_HOST in distro.conf), and keep only the newest ISO_KEEP ISOs there.
#
# Anatomy: this script runs xorriso (to read the ISO's .disk/info), sha256sum, gpg and the aws-cli.
# The bucket ISO_S3_BUCKET and the CloudFront distribution in front of it come from
# scripts/iso-infra.sh (make iso-infra). What the bucket holds after a run (docs/7, choice 59):
#
#   <BASE_VERSION>/<iso version>/<id>-<BASE_VERSION>-<iso version>-<arch>.iso   the ISO
#   <BASE_VERSION>/<iso version>/SHA256SUMS        its SHA-256, as sha256sum writes it
#   <BASE_VERSION>/<iso version>/SHA256SUMS.gpg    a detached signature of SHA256SUMS by the archive key
#   archive-keyring.asc                            the archive key's public half
#   latest.json                                    the newest ISO's name, URL, size, SHA-256 and date
#
# The ISO's version is its build time, which scripts/iso-create.sh writes into the ISO's .disk/info
# and into build/iso/iso-version; this script checks that the two agree, so an ISO is never
# published under another build's name. Versioned paths are never reused, which lets CloudFront
# cache them; latest.json is the one file rewritten, and the distribution never caches it. The
# test ISO (the one that boots into the boot test) is never uploaded.
#
# gpg asks for the apt signing key passphrase through pinentry, unless gpg-agent still holds it from
# make publish.
#
# Usage: scripts/iso-publish.sh [--dry-run]   (make iso-publish; make release runs it after asking)
#   --dry-run  check the ISO, write the checksum and latest.json under build/iso/publish/, and list
#              what would be uploaded; sign, upload and delete nothing
# Env:   AWS_PROFILE  the aws-cli profile (default APT_AWS_PROFILE in distro.conf)
set -euo pipefail
dry_run=false
[[ ${1:-} == --dry-run ]] && dry_run=true
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
for t in aws xorriso sha256sum gpg gpgv curl; do
  command -v "$t" >/dev/null || { echo "$t is not installed" >&2; exit 1; }
done
export AWS_PROFILE=${AWS_PROFILE:-$APT_AWS_PROFILE}
export AWS_REGION=$APT_S3_REGION
export AWS_PAGER=""

arch=amd64
work="$here/build/iso"
iso="$work/$DISTRO_ID-$BASE_VERSION-$arch.iso"
[[ -f $iso && -f $work/iso-version ]] || { echo "no ISO at $iso (or no $work/iso-version): run make iso first" >&2; exit 1; }
version=$(<"$work/iso-version")
[[ $version =~ ^[0-9]{8}\.[0-9]{4}$ ]] || { echo "$work/iso-version holds '$version', not a YYYYMMDD.HHMM version" >&2; exit 1; }
rm -f "$work/disk-info"
xorriso -osirrox on -indev "$iso" -extract /.disk/info "$work/disk-info" >/dev/null 2>&1 || { echo "could not read .disk/info from $iso" >&2; exit 1; }
info=$(<"$work/disk-info")
[[ $info == *"($version)"* ]] || { echo "the ISO's .disk/info ('$info') does not name version $version: rebuild with make iso" >&2; exit 1; }

name="$DISTRO_ID-$BASE_VERSION-$version-$arch.iso"
prefix="$BASE_VERSION/$version"
stage="$work/publish/$version"
rm -rf "$work/publish"
mkdir -p "$stage"

echo "== checksum and signature for $name"
sha=$(sha256sum "$iso" | cut -d' ' -f1)
printf '%s *%s\n' "$sha" "$name" > "$stage/SHA256SUMS"
if ! $dry_run; then
  gpg --batch --yes --local-user "$APT_KEY_FPR" --detach-sign --output "$stage/SHA256SUMS.gpg" "$stage/SHA256SUMS"
  gpgv --keyring "$here/packages/archive-keyring/archive-keyring.gpg" "$stage/SHA256SUMS.gpg" "$stage/SHA256SUMS"
fi

size=$(stat -c %s "$iso")
date=$(date -u -r "$iso" +%Y-%m-%dT%H:%M:%SZ)
python3 -I - "$stage/latest.json" <<PY
import json, sys
base = "$ISO_URL/$prefix"
json.dump({
    "name": "$DISTRO_NAME $BASE_VERSION",
    "version": "$version",
    "date": "$date",
    "file": "$name",
    "url": f"{base}/$name",
    "size": $size,
    "sha256": "$sha",
    "sha256sums": f"{base}/SHA256SUMS",
    "signature": f"{base}/SHA256SUMS.gpg",
    "key": "$ISO_URL/archive-keyring.asc",
    "key_fingerprint": "$APT_KEY_FPR",
}, open(sys.argv[1], "w"), indent=2)
PY

bucket="s3://$ISO_S3_BUCKET"
if $dry_run; then
  echo "== dry run: would upload to $bucket"
  printf '   %s\n' "$prefix/$name ($size bytes)" "$prefix/SHA256SUMS" "$prefix/SHA256SUMS.gpg" archive-keyring.asc latest.json
  echo "   and keep the newest $ISO_KEEP ISOs under $BASE_VERSION/; latest.json and SHA256SUMS are in $stage"
  exit 0
fi
immutable="public, max-age=31536000, immutable"
echo "== uploading $name ($size bytes) to $bucket/$prefix/"
aws s3 cp "$iso" "$bucket/$prefix/$name" --content-type application/x-iso9660-image --cache-control "$immutable" --only-show-errors
# SHA256SUMS has no extension, and a browser saving a text/plain file without one appends .txt,
# which breaks "gpg --verify SHA256SUMS.gpg SHA256SUMS": served as a download under its own name.
aws s3 cp "$stage/SHA256SUMS" "$bucket/$prefix/SHA256SUMS" --content-type application/octet-stream \
  --content-disposition 'attachment; filename="SHA256SUMS"' --cache-control "$immutable" --only-show-errors
aws s3 cp "$stage/SHA256SUMS.gpg" "$bucket/$prefix/SHA256SUMS.gpg" --content-type application/pgp-signature --cache-control "$immutable" --only-show-errors
aws s3 cp "$here/packages/archive-keyring/archive-keyring.asc" "$bucket/archive-keyring.asc" --content-type application/pgp-keys --cache-control "public, max-age=3600" --only-show-errors
# latest.json last, so it never names an ISO that is not there yet.
aws s3 cp "$stage/latest.json" "$bucket/latest.json" --content-type application/json --cache-control no-cache --only-show-errors

echo "== keeping the newest $ISO_KEEP ISOs"
mapfile -t versions < <(aws s3 ls "$bucket/$BASE_VERSION/" | awk '$1 == "PRE" {sub("/$", "", $2); print $2}' | grep -E '^[0-9]{8}\.[0-9]{4}$' | sort)
if (( ${#versions[@]} > ISO_KEEP )); then
  for old in "${versions[@]:0:${#versions[@]}-ISO_KEEP}"; do
    echo "   deleting $BASE_VERSION/$old/"
    aws s3 rm "$bucket/$BASE_VERSION/$old/" --recursive --only-show-errors
  done
fi

echo "== checking what $ISO_HOST serves"
curl -fsSL "$ISO_URL/latest.json" | python3 -I -c 'import json, sys; d = json.load(sys.stdin); assert d["version"] == sys.argv[1], d["version"]; print("   latest.json names", d["file"])' "$version"
curl -fsSL "$ISO_URL/$prefix/SHA256SUMS" -o "$stage/SHA256SUMS.served"
curl -fsSL "$ISO_URL/$prefix/SHA256SUMS.gpg" -o "$stage/SHA256SUMS.gpg.served"
gpgv --keyring "$here/packages/archive-keyring/archive-keyring.gpg" "$stage/SHA256SUMS.gpg.served" "$stage/SHA256SUMS.served"
served=$(curl -fsSI "$ISO_URL/$prefix/$name" | awk 'tolower($1) == "content-length:" {print $2}' | tr -d '\r')
[[ $served == "$size" ]] || { echo "!! $ISO_URL/$prefix/$name serves $served bytes, the ISO has $size" >&2; exit 1; }
echo "== published $ISO_URL/$prefix/$name"
