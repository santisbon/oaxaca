#!/usr/bin/env bash
# machine-setup.sh: make a workstation ready to build, test and publish the distro, once per machine.
#
# Anatomy: this script runs apt and snap for the tools, then four checks of the credentials a
# release needs, then two other scripts: chroot-create.sh (make chroot, the clean build chroot)
# and repo-publish.sh --seed (make repo-seed, aptly's database and build/ filled from the
# published repository). Each step skips itself when its work is already done, so a second run
# only checks.
#
# The credentials are not created here: the apt signing key is restored from the password manager
# (docs/2 - build-infra.md, "Backing up the signing key"), the aws-cli profile APT_AWS_PROFILE and
# GitHub's SSH key are set up by hand.
#
# Usage: scripts/machine-setup.sh [--tools]   (make machine-setup [SETUP_FLAGS=--tools])
#        --tools  install the tools and stop: enough to build and test, without publishing
# Env:   OMARCHY_FORK_DIR  the fork's checkout (default ~/Projects/omarchy)
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
# shellcheck source=/dev/null
source distro.conf
fork=${OMARCHY_FORK_DIR:-$HOME/Projects/omarchy}

tools_only=0
case ${1:-} in
  --tools) tools_only=1 ;;
  '') ;;
  *) echo "unknown option $1 (--tools)" >&2; exit 1 ;;
esac

# Build tools (git, curl and cargo for build.sh's downloads; sbuild, mmdebstrap and uidmap for the
# chroot), the boot tests' QEMU and OVMF, the ISO's squashfs, FAT and xorriso tools, the fork's test
# tools (lua5.5, ripgrep), and aptly for publishing; all from Ubuntu's archive (aptly is in universe).
sudo apt install git curl cargo python3 sbuild mmdebstrap uidmap devscripts debhelper lintian \
  qemu-system-x86 e2fsprogs ovmf squashfs-tools xorriso dosfstools mtools lua5.5 ripgrep aptly
# The aws-cli for the upload, from Amazon's snap.
command -v aws >/dev/null || sudo snap install aws-cli --classic
if ((tools_only)); then
  echo "== tools installed"
  exit 0
fi

missing=()
gpg --list-secret-keys "$APT_KEY_FPR" >/dev/null 2>&1 || missing+=("the apt signing key $APT_KEY_FPR in GnuPG (docs/2, Backing up the signing key)")
aws sts get-caller-identity --profile "$APT_AWS_PROFILE" >/dev/null 2>&1 || missing+=("the aws-cli profile $APT_AWS_PROFILE (aws configure --profile $APT_AWS_PROFILE)")
git ls-remote origin HEAD >/dev/null 2>&1 || missing+=("GitHub access to this repository over SSH")
git -C "$fork" ls-remote origin "$OMARCHY_PORT_REF" >/dev/null 2>&1 || missing+=("the Omarchy fork cloned at $fork, with GitHub access over SSH")
grep -q "^$USER:" /etc/subuid || missing+=("subordinate ids for $USER in /etc/subuid (mmdebstrap's unshare mode)")
[[ -w /dev/kvm ]] || missing+=("write access to /dev/kvm (QEMU's boot tests)")
if ((${#missing[@]})); then
  printf '!! missing: %s\n' "${missing[@]}" >&2
  exit 1
fi
echo "== credentials: ok"

scripts/chroot-create.sh
scripts/repo-publish.sh --seed
echo "== machine ready: make release builds, tests and publishes"
