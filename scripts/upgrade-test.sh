#!/usr/bin/env bash
# upgrade-test.sh: upgrade the published packages to the ones in build/ inside a throwaway
# chroot, and run the migrations for a user who existed before (roadmap step 8).
#
# Anatomy: one mmdebstrap run in unshare mode (no root privileges) whose output is /dev/null,
# so the only things written are a report and a log under build/upgrade-test/. "N" is what an
# installed system has: the versions the published archive (APT_URL in distro.conf) offers.
# "N+1" is build/.
#   1. mmdebstrap installs the minbase variant of the base series (release, -updates and
#      -security pockets; main, restricted, universe and multiverse; Recommends off, as in the
#      images built before <id>-base 0.1.6, which is what the installed systems have) and, from the published archive, every package name that is both published and
#      present in build/. That installed set is N.
#   2. Customize hooks run a script inside the chroot. The script records N's versions, creates a
#      user whose home is /etc/skel as N shipped it and appends a marker line to one of that
#      user's files, points apt at build/ (copied in as a flat file archive with a Packages
#      index written by dpkg-scanpackages) and runs apt-get full-upgrade with the options
#      <id>-update -y uses (the noninteractive frontend, --force-confdef, --force-confold).
#      Then the script records the versions, dpkg --audit, what apt would still upgrade, the
#      unattended-upgrades origins, and whether the marker line survived; when <id>-tools is
#      installed, the script drops a synthetic migration into /usr/share/<id>/migrations, runs
#      <id>-migrate as the user, and checks that the migration ran and nothing is pending.
#   3. The report is downloaded to build/upgrade-test/report.txt (the log beside it) and
#      compared with the expectations at the end of this file; any mismatch exits non-zero.
# Not covered: a running desktop (first-run, the shell), the kernel and the bootloader, which
# are the boot tests' job. Before the first release the published set is small, so N is too.
#
# Usage: scripts/upgrade-test.sh      (make upgrade-test; CI's upgrade-test job)
# Env:   UBUNTU_MIRROR, UBUNTU_SECURITY_MIRROR   as in rootfs-create.sh
# Needs: mmdebstrap, uidmap, ubuntu-keyring, dpkg-dev (dpkg-scanpackages), curl.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
# See rootfs-create.sh: a LOCPATH from the host breaks the locales package inside the chroot.
unset LOCPATH

arch=amd64
mirror=${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}
security=${UBUNTU_SECURITY_MIRROR:-http://security.ubuntu.com/ubuntu}
components="main restricted universe multiverse"
out="$here/build/upgrade-test"
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
# Our archive's key, for the apt that mmdebstrap itself runs: the signed-by option on the mirror
# line (mmdebstrap(1), --keyring: "if you need to pass multiple keyrings, use the signed-by
# option"). Found 2026-10-11 over four failed runs: that apt resolves keyring paths on the host,
# not in the chroot (a key copied into the chroot's trusted.gpg.d or named by an in-chroot
# path is never read), and its download methods run as the unprivileged _apt user, which under a
# home directory of mode 0750 cannot read packages/archive-keyring/, so the key is staged in a
# world-readable directory under /tmp, as rootfs-create.sh stages the .deb files. Inside the
# chroot the installed keyring package and the apt-source package's Signed-By take over, and the
# script inside removes mmdebstrap's sources.list, which carries the staging path.
keystage=$(mktemp -d /tmp/"$DISTRO_ID"-upgrade-test-key.XXXXXX)
chmod 0755 "$keystage"
trap 'rm -rf "$keystage"' EXIT
install -m 0644 "$here/packages/archive-keyring/archive-keyring.gpg" "$keystage/"
our_key="$keystage/archive-keyring.gpg"
stage="$out/$DISTRO_ID-upgrade-test"
report="$out/report.txt"
log="$out/log.txt"
for t in mmdebstrap dpkg-scanpackages curl; do
  command -v "$t" >/dev/null || { echo "$t is not installed (mmdebstrap, dpkg-dev, curl)" >&2; exit 1; }
done
shopt -s nullglob
debs=("$here"/build/*.deb)
((${#debs[@]})) || { echo "nothing in build/ to upgrade to (run 'make build')" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$stage"
# apt's package cache, shared with rootfs-create.sh (its comment on apt_cache has the details):
# copied into the chroot before apt downloads and back out after the upgrade, which downloads
# more, then pruned to the newest version of each package.
apt_cache="$here/build/apt-cache"
mkdir -p "$apt_cache"

echo "== published index from $APT_URL"
index="$out/published-Packages"
curl -sSfL --max-time 60 -o "$index" "$APT_URL/dists/$BASE_SERIES/$APT_COMPONENT/binary-amd64/Packages" \
  || { echo "cannot fetch the published index: is anything published at $APT_URL?" >&2; exit 1; }
declare -A published build_ver build_deb
while read -r n v; do published[$n]=$v; done < <(awk '/^Package:/{p=$2} /^Version:/{print p, $2}' "$index")
# build/ may hold several versions of one package (an older build beside the newest); only the
# newest of each name is N+1, as it is the one a publish would offer.
for deb in "${debs[@]}"; do
  base=$(basename "$deb"); n=${base%%_*}; rest=${base#*_}; v=${rest%%_*}
  if [[ -z ${build_ver[$n]:-} ]] || dpkg --compare-versions "$v" gt "${build_ver[$n]}"; then
    build_ver[$n]=$v; build_deb[$n]=$deb
  fi
done
names=()
for n in $(printf '%s\n' "${!build_ver[@]}" | sort); do
  [[ -n ${published[$n]:-} ]] && names+=("$n")
done
if ((${#names[@]} == 0)); then
  echo "none of build/'s packages is published at $APT_URL yet: nothing to upgrade from"
  exit 0
fi
echo "   N (published) -> N+1 (build/):"
for n in "${names[@]}"; do printf '   %-36s %s -> %s\n' "$n" "${published[$n]}" "${build_ver[$n]}"; done

echo "== flat archive of build/ for apt inside the chroot"
for n in "${!build_deb[@]}"; do cp "${build_deb[$n]}" "$stage/"; done
(cd "$stage" && dpkg-scanpackages . /dev/null > Packages 2>/dev/null)
echo "   $(grep -c '^Package:' "$stage/Packages") packages indexed"

# The script that runs inside the chroot, as root. Placeholders are filled below. The script
# never exits non-zero, so mmdebstrap always reaches the download hooks; the report decides.
inside="$out/inside.sh"
cat > "$inside" <<'INNER'
#!/bin/bash
set -uo pipefail
id=@ID@ names="@NAMES@"
report=/var/log/$id-upgrade-test.report
log=/var/log/$id-upgrade-test.log
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
exec > >(tee -a "$log") 2>&1
r() { echo "$*" | tee -a "$report"; }
ver() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || echo none; }
versions() { for n in $names; do printf '%s=%s ' "$n" "$(ver "$n")"; done; }

r "=== UPGRADE-TEST BEGIN"
r "N packages: $(versions)"

# A user from N's /etc/skel, with a line of their own in one of the files it gave them.
useradd -m -s /bin/bash tester
home=/home/tester
marker_file=
for f in .config/hypr/bindings.conf .bash_aliases .bashrc; do
  [[ -f $home/$f ]] && { marker_file=$home/$f; break; }
done
echo "# $id-upgrade-test marker: a line the user added at N" >> "$marker_file"
r "user config: ${marker_file#$home/}"

# apt's sources as the image has them (rootfs-create.sh): mmdebstrap's sources.list goes away;
# Ubuntu's archive is named in ubuntu.sources, ours in the apt-source package's $id.sources
# with its Signed-By.
rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: @MIRROR@
Suites: @SERIES@ @SERIES@-updates
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: @SECURITY@
Suites: @SERIES@-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
r "apt sources: $(ls /etc/apt/sources.list.d/ | paste -sd' ')"

# N+1: build/ as a flat file archive (deb822, no components, trusted: it is our own build).
cat > "/etc/apt/sources.list.d/$id-upgrade-test.sources" <<EOF
Types: deb
URIs: file:/var/lib/$id-upgrade-test
Suites: ./
Trusted: yes
EOF
if apt-get -q update > /tmp/update.log 2>&1; then r "apt update: ok"; else r "apt update: FAILED"; cat /tmp/update.log; fi
r "upgradable before: $(apt list --upgradable 2>/dev/null | grep -c '^[^ ]*/')"
apt list --upgradable 2>/dev/null | grep '/' | sed 's/^/   /'

# The same apt-get call <id>-update -y makes (bin/omarchy-update-system-pkgs on the port branch).
apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade > /tmp/upgrade.log 2>&1
rc=$?
cat /tmp/upgrade.log
r "full-upgrade exit: $rc"
r "conffile prompts: $(grep -c "^Configuration file '" /tmp/upgrade.log)"
r "dpkg audit: $(dpkg --audit 2>&1 | grep -c .) lines"
r "remaining upgrades: $(apt-get -s full-upgrade 2>/dev/null | grep -c '^Inst ')"
mismatch=
while read -r n v; do
  [[ " $names " == *" $n "* ]] || continue
  inst=$(ver "$n"); [[ $inst == "$v" ]] || mismatch+="$n=$inst(build $v) "
done < <(awk '/^Package:/{p=$2} /^Version:/{print p, $2}' "/var/lib/$id-upgrade-test/Packages")
r "N+1 packages: $(versions)"
r "at build versions: ${mismatch:-yes}"
r "autoremove candidates: [$(apt-get -s autoremove 2>/dev/null | awk '$1=="Remv"{print $2}' | paste -sd' ')]"
if command -v lsb_release >/dev/null; then r "lsb_release: $(lsb_release -is 2>/dev/null) $(lsb_release -cs 2>/dev/null)"; else r "lsb_release: not installed"; fi
r "unattended origins: $(apt-config dump Unattended-Upgrade::Allowed-Origins 2>/dev/null | sed -n 's/^.*:: "\(.*\)";$/\1/p' | paste -sd' ')"
r "user config kept: $(grep -c "$id-upgrade-test marker" "$marker_file")"

# Migrations, when the tools package is installed: a synthetic one proves the runner, the
# per-user state and the marking; the port's real migrations run with it.
if command -v "$id-migrate" >/dev/null; then
  mdir=/usr/share/$id/migrations
  mkdir -p "$mdir"
  cat > "$mdir/9999999999.sh" <<EOF
echo "$id-upgrade-test: synthetic migration"
mkdir -p "\$HOME/.local/state/$id"
echo ran > "\$HOME/.local/state/$id/upgrade-test-migration"
EOF
  # The migrations read OMARCHY_PATH, Omarchy's name, kept for plugins written for Omarchy
  # (docs/6, choice 86).
  as_tester() { runuser -u tester -- env "HOME=$home" "OMARCHY_PATH=/usr/share/$id" PATH=/usr/local/bin:/usr/bin:/bin "$@"; }
  r "migrations shipped: $(ls "$mdir"/*.sh 2>/dev/null | grep -vc 9999999999)"
  r "migrations pending before: $(as_tester "$id-migrate" --pending 2>/dev/null | grep -c .)"
  as_tester "$id-migrate"
  r "migrate exit: $?"
  r "migration ran: $(cat "$home/.local/state/$id/upgrade-test-migration" 2>/dev/null || echo no)"
  r "migrations pending after: $(as_tester "$id-migrate" --pending 2>/dev/null | grep -c .)"
  r "user config kept after migrations: $(grep -c "$id-upgrade-test marker" "$marker_file")"
else
  r "migrations: skipped ($id-tools is not installed at N)"
fi
r "=== UPGRADE-TEST END"
exit 0
INNER
sed -i "s/@ID@/$DISTRO_ID/g; s/@NAMES@/${names[*]}/g; s|@MIRROR@|$mirror|g; s|@SECURITY@|$security|g; s/@SERIES@/$BASE_SERIES/g" "$inside"

includes=()
for n in "${names[@]}"; do includes+=("--include=$n"); done
# The script inside removes mmdebstrap's sources.list, so that from the upgrade on our archive
# is verified the way an installed system verifies it: the keyring package's file named by the
# apt-source package's Signed-By.
echo "== chroot: minbase $BASE_SERIES plus N from $APT_URL, then the upgrade (mmdebstrap, unshare mode)"
mmdebstrap \
  --mode=unshare \
  --variant=minbase \
  --architectures="$arch" \
  --keyring="$keyring" \
  --aptopt='APT::Install-Recommends "false"' \
  --skip=essential/unlink \
  --setup-hook='mkdir -p "$1/var/cache/apt/archives/"' \
  --setup-hook="sync-in $apt_cache /var/cache/apt/archives/" \
  "${includes[@]}" \
  --customize-hook="copy-in $stage /var/lib" \
  --customize-hook="upload $inside /usr/local/sbin/$DISTRO_ID-upgrade-test" \
  --customize-hook="chroot \"\$1\" chmod 0755 /usr/local/sbin/$DISTRO_ID-upgrade-test" \
  --customize-hook="chroot \"\$1\" /usr/local/sbin/$DISTRO_ID-upgrade-test" \
  --customize-hook="download /var/log/$DISTRO_ID-upgrade-test.report $report" \
  --customize-hook="download /var/log/$DISTRO_ID-upgrade-test.log $log" \
  --customize-hook="sync-out /var/cache/apt/archives $apt_cache" \
  "$BASE_SERIES" /dev/null \
  "deb $mirror $BASE_SERIES $components" \
  "deb $mirror $BASE_SERIES-updates $components" \
  "deb $security $BASE_SERIES-security $components" \
  "deb [signed-by=$our_key] $APT_URL $BASE_SERIES $APT_COMPONENT" \
  2>&1 | grep -vE '^I: ' || true
[[ -f $report ]] || { echo "no report came back: see mmdebstrap's output above" >&2; exit 1; }
"$here/scripts/apt-cache-prune.sh" "$apt_cache"

echo "== report ($report)"
cat "$report"
reportc=$(cat "$report")
fail=0
check() { grep -q -- "$1" <<< "$reportc" || { echo "!! expected: $1" >&2; fail=1; }; }
check "^apt update: ok$"
check "^full-upgrade exit: 0$"
check "^conffile prompts: 0$"
check "^dpkg audit: 0 lines$"
check "^remaining upgrades: 0$"
check "^at build versions: yes$"
check "^lsb_release: \($DISTRO_NAME $BASE_SERIES\|not installed\)$"
check "^unattended origins: Ubuntu:$BASE_SERIES Ubuntu:$BASE_SERIES-security UbuntuESMApps:$BASE_SERIES-apps-security UbuntuESM:$BASE_SERIES-infra-security$"
check "^user config kept: 1$"
if grep -q '^migrate exit:' <<< "$reportc"; then
  # Pending before the run: every migration the port ships (a user created from N's /etc/skel
  # has run none) plus the synthetic one.
  shipped=$(sed -n 's/^migrations shipped: //p' <<< "$reportc")
  check "^migrations pending before: $((shipped + 1))$"
  check "^migrate exit: 0$"
  check "^migration ran: ran$"
  check "^migrations pending after: 0$"
  check "^user config kept after migrations: 1$"
else
  check "^migrations: skipped"
fi
check "^=== UPGRADE-TEST END$"
if ((fail)); then echo "!! upgrade test FAILED"; exit 1; fi
echo "== upgrade test passed (N: ${names[*]})"
