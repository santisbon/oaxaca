#!/usr/bin/env bash
# keygen.sh: create the apt archive signing key named in distro.conf and export its public half.
#
# Run this yourself in a terminal. gpg asks for the apt signing key passphrase through pinentry, so the
# apt signing key passphrase never appears on a command line. What it does:
#   1. generates an RSA 4096 sign-only key with a 2-year expiry in your default GnuPG home
#   2. exports the public key to packages/archive-keyring/archive-keyring.{gpg,asc}
#   3. writes the fingerprint into distro.conf (APT_KEY_FPR) and re-renders
# The secret key stays in ~/.gnupg. Back it up offline (the script prints how).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"

if [[ -n ${APT_KEY_FPR:-} ]]; then
  echo "distro.conf already has APT_KEY_FPR=$APT_KEY_FPR." >&2
  echo "To rotate the key, clear that value first, then run this again (see docs/build-infra.md)." >&2
  exit 1
fi

params=$(mktemp)
trap 'rm -f "$params"' EXIT
{
  echo "Key-Type: RSA"
  echo "Key-Length: 4096"
  echo "Key-Usage: sign"
  echo "Name-Real: $APT_KEY_NAME"
  [[ -n ${APT_KEY_EMAIL:-} ]] && echo "Name-Email: $APT_KEY_EMAIL"
  echo "Expire-Date: 2y"
  echo "%commit"
} > "$params"

echo "Creating the archive signing key \"$APT_KEY_NAME\" (RSA 4096, sign-only, expires in 2 years)."
echo "pinentry will ask for the apt signing key passphrase. Choose one and store it in your password manager."
out=$(gpg --batch --generate-key "$params" 2>&1 | tee /dev/stderr)
fpr=$(grep -o -E '[0-9A-F]{40}\.rev' <<< "$out" | head -1 | cut -c1-40)
[[ -n $fpr ]] || { echo "could not find the new key's fingerprint in gpg's output" >&2; exit 1; }

pkg="$here/packages/archive-keyring"
gpg --export "$fpr" > "$pkg/archive-keyring.gpg"
gpg --export --armor "$fpr" > "$pkg/archive-keyring.asc"
sed -i "s/^APT_KEY_FPR=.*/APT_KEY_FPR=$fpr/" "$here/distro.conf"
"$here/scripts/render.py" --quiet

cat <<MSG

Done. Fingerprint: $fpr
  public key:  packages/archive-keyring/archive-keyring.gpg (and .asc), commit both
  distro.conf: APT_KEY_FPR set, commit it

Back up the secret key now, to somewhere offline (not this repo):
  gpg --export-secret-keys --armor $fpr > /path/to/offline/${DISTRO_ID}-archive-key.asc
The revocation certificate gpg just wrote under ~/.gnupg/openpgp-revocs.d/ belongs in the same place.
MSG
