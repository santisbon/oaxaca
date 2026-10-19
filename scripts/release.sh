#!/usr/bin/env bash
# release.sh: build what is not published yet, test the image built from it, commit, and publish.
#
# Anatomy: this script runs git and make only; each step below names the make target, and the
# make target's script does the work (build.sh, rootfs-create.sh, rootfs-boot-test.sh,
# iso-create.sh, iso-boot-test.sh, upgrade-test.sh, repo-publish.sh). What it adds is the order,
# the stops between steps, and two decisions no other script makes:
#   - the desktop's version: OMARCHY_PORT_DATE, _COUNT and _COMMIT in distro.conf are set from
#     the fork's pushed HEAD (build.sh only checks them against the commit it fetches);
#   - the packages to build: those whose version at the top of the rendered debian/changelog is
#     missing from the published source index. A package changed without a version bump is not
#     built; repo-publish.sh's guard refuses its file if a build of it turns up.
# The first failing step stops the release. Prompts: sudo (none expected), git's commit editor,
# gpg's pinentry for the apt signing key passphrase, and the question before the upload.
#
# Before running: commit the fork's changes and this repository's (step 8 commits with git add -A,
# so anything uncommitted lands in the release commit); when the fork changed, give the desktop package a
# new changelog entry; bump every other package that changed (docs/README.md, "Releasing").
#
# The release commit's message is computed, not typed: "Release: " and, comma-separated, the
# desktop's version when the desktop is built and "<package directory> <version>" for each other
# package built (release_message below). Step 8 opens git's editor with that message filled in;
# --message prints it and stops, before step 1, with nothing pushed, written or built.
#
# Usage: scripts/release.sh             (make release; make machine-setup first on a new workstation)
#        scripts/release.sh --message   (make release-message)
# Env:   OMARCHY_FORK_DIR  the fork's checkout (default ~/Projects/omarchy)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
# shellcheck source=/dev/null
source distro.conf
fork=${OMARCHY_FORK_DIR:-$HOME/Projects/omarchy}
changelog=packages/desktop/debian/changelog.in

# The published versions, "<source> <version>" per line, from the repository's source index.
published=$(curl -fsSL "$APT_URL/dists/$BASE_SERIES/$APT_COMPONENT/source/Sources.gz" | gunzip | awk '/^Package:/ {p=$2} /^Version:/ {print p" "$2}')
# The fork's HEAD as the desktop's version parts: commit date in UTC, commits since Omarchy's tag,
# short hash.
d=$(TZ=UTC git -C "$fork" log -1 --format=%cd --date=format-local:%Y%m%d)
n=$(git -C "$fork" rev-list --count "$OMARCHY_TAG"..HEAD)
c=$(git -C "$fork" rev-parse --short=8 HEAD)

# The package directories whose version at the top of the rendered debian/changelog is not
# published. Before step 2 the desktop's rendered changelog still names distro.conf's commit, so
# with --message the desktop counts as changed when the fork has moved past that commit.
unpublished() {
  local dir top
  for dir in packages/*/; do
    top=$(sed -n '1s/^\([^ ]*\) (\([^)]*\)).*/\1 \2/p' "$dir/debian/changelog")
    if [[ $dir == packages/desktop/ && $c != "$OMARCHY_PORT_COMMIT" ]] || ! grep -qxF "$top" <<<"$published"; then
      echo "${dir%/}"
    fi
  done
}
# The release commit's message from the package directories given: the desktop as
# "desktop <OMARCHY_PORT_VERSION>" (the version without its Debian revision), first; every other
# package as "<directory name> <version at the top of its debian/changelog>".
release_message() {
  local dir parts=()
  for dir in "$@"; do
    [[ $dir == packages/desktop ]] && parts+=("desktop $OMARCHY_VERSION+git$d.$n.$c")
  done
  for dir in "$@"; do
    [[ $dir == packages/desktop ]] && continue
    parts+=("${dir#packages/} $(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' "$dir/debian/changelog")")
  done
  local IFS=,
  printf 'Release: %s\n' "${parts[*]}" | sed 's/,/, /g'
}

if [[ ${1:-} == --message ]]; then
  [[ -z $(git -C "$fork" status --porcelain) ]] || { echo "!! $fork has uncommitted changes: commit them first, since the commit's hash is part of the desktop's version" >&2; exit 1; }
  mapfile -t todo < <(unpublished)
  ((${#todo[@]})) || { echo "every package's version is published: nothing to release" >&2; exit 1; }
  release_message "${todo[@]}"
  exit 0
fi

# 1. Push the fork: the desktop build clones the fork's branch from GitHub, not the local checkout.
[[ $(git -C "$fork" branch --show-current) == "$OMARCHY_PORT_REF" ]] || { echo "!! $fork is not on $OMARCHY_PORT_REF" >&2; exit 1; }
[[ -z $(git -C "$fork" status --porcelain) ]] || { echo "!! $fork has uncommitted changes: commit them first" >&2; exit 1; }
git -C "$fork" push

# 2. Point distro.conf at the fork's HEAD (d, n and c above: together the desktop's version) and
#    render every template.
if [[ $c != "$OMARCHY_PORT_COMMIT" ]]; then
  # The desktop changelog's top entry carries the version placeholder; the entry below it has to
  # name the published version, or that version's entry would take the new version. Compared
  # with the published version, not distro.conf's: a release that stopped before uploading left
  # distro.conf at a version nobody has.
  pub=$(awk -v s="$DISTRO_ID-desktop" '$1 == s {print $2}' <<<"$published")
  pub=${pub%-*}
  if ! head -1 "$changelog" | grep -qF '(@OMARCHY_PORT_VERSION@-' || ! grep -qF "($pub-" "$changelog"; then
    echo "!! the fork moved to $c, but $changelog has no new entry above the published $pub's:" >&2
    echo "   write $pub into the top entry's first line, add a new entry above it" >&2
    echo "   with the placeholder (docs/README.md, \"Before each release\"), then run make release again" >&2
    exit 1
  fi
  sed -i "s/^OMARCHY_PORT_DATE=.*/OMARCHY_PORT_DATE=$d/; s/^OMARCHY_PORT_COUNT=.*/OMARCHY_PORT_COUNT=$n/; s/^OMARCHY_PORT_COMMIT=.*/OMARCHY_PORT_COMMIT=$c/" distro.conf
fi
make render
# shellcheck source=/dev/null
source distro.conf
echo "== desktop version: $OMARCHY_PORT_VERSION"

# 3. Build the packages whose version is not published yet.
mapfile -t changed < <(unpublished)
if ((${#changed[@]} == 0)); then
  echo "== every package's version is published: nothing to release"
  exit 0
fi
echo "== to build: ${changed[*]}"
make build PKG="${changed[*]}"

# 4. Newer upstream releases of the repackaged programs: reported, not a reason to stop.
make upstream-check || echo "== a newer upstream release is listed above: package it in a later release"

# 5. The desktop and live root filesystems from Ubuntu's archive plus build/'s newest packages: the
#    desktop one is the installed system's layer of the ISO, the live one the live session (docs/7,
#    choice 55). The live one is booted in QEMU (the base, session and desktop checks).
make rootfs PROFILE=desktop
make rootfs
make rootfs-test

# 6. The installation ISO from those root filesystems, booted under OVMF with Secure Boot on, then off.
make iso
make iso-test
make iso-test SECURE_BOOT=off
# The ISO installed on an encrypted btrfs disk, factory-reset, and handed to a new owner.
make factory-reset-test

# 7. The published packages upgraded to build/'s in a throwaway chroot, migrations included; then
#    the published desktop booted in QEMU and updated to build/'s inside its running session.
make upgrade-test
make session-upgrade-test

# 8. Commit this repository (git opens the editor with the release message filled in; an empty
#    message stops the release) and push.
git status -sb
git add -A
git diff --cached --quiet || git commit -e -m "$(release_message "${changed[@]}")"
git push

# 9. Sign the repository locally and list what the upload would change; upload only on "y".
make publish
read -rp "Upload to $APT_S3_BUCKET? [y/N] " answer
[[ $answer == y ]] || { echo "== not uploaded: make publish PUBLISH_FLAGS=--push uploads this release later"; exit 1; }

# 10. Upload, then check the uploaded signature with our public key.
make publish PUBLISH_FLAGS=--push
curl -fsSL "$APT_URL/dists/$BASE_SERIES/InRelease" | gpgv --keyring "$here/packages/archive-keyring/archive-keyring.gpg" -
echo "== released $OMARCHY_PORT_VERSION: run $DISTRO_ID-update on installed systems; build/iso/ has the matching ISO"
