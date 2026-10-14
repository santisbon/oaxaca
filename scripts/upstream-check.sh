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
# GH_TOKEN in the environment (CI sets one) the request is authenticated.
#
# Usage: scripts/upstream-check.sh        (make upstream-check; the weekly CI workflow
#                                          .github/workflows/upstream-check.yml)
# Exit:  0 every package is current, 1 a newer release exists, 2 GitHub could not be asked
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"

token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
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
      python3 -c 'import json, sys; print(json.load(sys.stdin).get("tag_name", ""))'); then
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
exit "$status"
