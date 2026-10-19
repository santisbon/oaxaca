#!/usr/bin/env bash
# upstream-check.sh: fail when a packaged third-party program has a newer upstream release than
# the version this repository builds.
#
# Anatomy: this script runs curl, python3 (to read the JSON answer), sed and dpkg. For every package directory whose upstream
# file sets RELEASES=<owner>/<repo> (today packages/localsend), it asks GitHub's REST API for that
# repository's latest release (GET /repos/<owner>/<repo>/releases/latest, which skips drafts and
# pre-releases), drops a leading "v" from the release's tag, and compares the result with the
# upstream part of the first version in the package's rendered debian/changelog
# (dpkg --compare-versions). A newer release fails the check and prints what to update.
# Why: these packages repackage a project's release, and nothing else would notice a new one.
# LocalSend receives files over the network, so a fix release left unpackaged matters.
# GitHub allows 60 unauthenticated API requests an hour per address; with GITHUB_TOKEN or
# GH_TOKEN in the environment (CI sets one), or else the token of a logged-in GitHub CLI
# ("gh auth token", as on the workstation), the request is authenticated (5000 an hour). The
# unauthenticated quota ran out during a release on 2026-10-17 (HTTP 403 for every package).
#
#
# The second check is for the Ubuntu source packages this repository rebuilds with a patch: every
# package directory whose upstream file sets DSC= to a Launchpad source file
# (https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/<source>/<version>/..., today
# packages/plymouth and packages/calamares). It asks Launchpad's API which versions of <source>
# are published in the base series (getPublishedSources on the primary archive, status
# Published) and fails when the release, -updates or -security pocket has a version above
# <version>, the one the rebuild starts from. Why: the rebuild's version (<version> plus
# "<distro id><n>") ranks below Ubuntu's next upload, so apt replaces the rebuild with Ubuntu's
# package once that upload is published, keeping Oaxaca's fix only if Ubuntu's upload carries it
# (docs/1, Version scheme). After the base series' release (stonking, 2026-10-15) such an upload
# is a stable update in -updates or -security. A version only in -proposed is reported and does
# not fail: apt does not install from -proposed.
#
# Usage: scripts/upstream-check.sh        (make upstream-check; the weekly CI workflow
#                                          .github/workflows/upstream-check.yml)
# Exit:  0 every package is current, 1 a newer release or Ubuntu upload exists, 2 GitHub or
#        Launchpad could not be asked
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
# shellcheck source=/dev/null
source distro.conf

token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
if [[ -z $token ]] && command -v gh >/dev/null; then
  token=$(gh auth token 2>/dev/null || true)
fi
auth=(); [[ -n $token ]] && auth=(-H "Authorization: Bearer $token")

status=0
for upstream in packages/*/upstream; do
  releases=$(sed -n 's/^RELEASES=//p' "$upstream")
  [[ -n $releases ]] || continue
  dir=$(dirname "$upstream")
  ours=$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$dir/debian/changelog")
  ours=${ours#*:}; ours=${ours%-*}
  if ! latest=$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$releases/releases/latest" |
      python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))' 2>/dev/null); then
    echo "!! $(basename "$dir"): could not ask GitHub for $releases's latest release" >&2
    status=2; continue
  fi
  latest=${latest#v}
  if [[ -z $latest ]]; then
    echo "!! $(basename "$dir"): GitHub's answer for $releases had no tag_name" >&2
    status=2; continue
  fi
  if dpkg --compare-versions "$latest" gt "$ours"; then
    echo "!! $(basename "$dir"): $releases released $latest; this repository builds $ours."
    echo "   Update the version and the SHA-256s in $upstream, add a changelog entry, make build PKG=$dir"
    ((status == 2)) || status=1
  else
    echo "-- $(basename "$dir"): $ours is current ($releases's latest release is $latest)"
  fi
done

# The rebuilt Ubuntu source packages (see the header).
for upstream in packages/*/upstream; do
  dsc=$(sed -n 's/^DSC=//p' "$upstream")
  [[ $dsc == https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/* ]] || continue
  dir=$(dirname "$upstream")
  rest=${dsc#https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/}
  source=${rest%%/*}; base=${rest#*/}; base=${base%%/*}
  query="https://api.launchpad.net/devel/ubuntu/+archive/primary?ws.op=getPublishedSources&exact_match=true&status=Published"
  query+="&source_name=$source&distro_series=https://api.launchpad.net/devel/ubuntu/$BASE_SERIES"
  # One "<version> <pocket>" line per publication.
  if ! published=$(curl -fsSL "$query" |
      python3 -c 'import json, sys; [print(e["source_package_version"], e["pocket"]) for e in json.load(sys.stdin)["entries"]]' 2>/dev/null); then
    echo "!! $(basename "$dir"): could not ask Launchpad for $source in $BASE_SERIES" >&2
    status=2; continue
  fi
  newer=""; proposed=""
  while read -r version pocket; do
    [[ -n $version ]] || continue
    dpkg --compare-versions "$version" gt "$base" || continue
    if [[ $pocket == Proposed ]]; then proposed+=" $version"; else newer+=" $version ($pocket)"; fi
  done <<< "$published"
  if [[ -n $newer ]]; then
    echo "!! $(basename "$dir"): Ubuntu published $source${newer} in $BASE_SERIES; this repository rebuilds $base with its own patch."
    echo "   apt now prefers Ubuntu's version. Check whether that upload carries the patch in $dir/debian/patches;"
    echo "   if not, rebase: point DSC= and SHA256= in $upstream at the new .dsc, add a changelog entry, make build PKG=$dir"
    ((status == 2)) || status=1
  else
    echo "-- $(basename "$dir"): $base is Ubuntu's newest $source in $BASE_SERIES${proposed:+ (in -proposed:$proposed)}"
  fi
done
exit "$status"
