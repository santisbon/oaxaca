#!/usr/bin/env bash
# build.sh: build one or more packages in the clean chroot and lint the result.
#
# Anatomy: for each package directory, this script first runs dpkg-source -b from inside
# build/, which writes the source package (.dsc and .tar.xz) there. sbuild (config:
# sbuild.conf, mode: unshare) then takes that .dsc, unpacks the chroot tarball from
# ~/.cache/sbuild in a user namespace, installs the build dependencies there, runs
# dpkg-buildpackage, and drops the .deb, .changes and .buildinfo files into build/. Then
# lintian, on the host, checks every .changes file.
#
# dpkg-source runs from build/ on purpose: dpkg-source -b writes its output to the current
# directory, and handing sbuild the package directory instead would make sbuild run
# dpkg-source inside packages/<dir>, littering packages/ with .dsc and .tar.xz files.
#
# A package directory with an "upstream" file is a "3.0 (quilt)" package whose source is
# not in the repository. The file is shell syntax, sourced by this script, and names the
# source in one of three ways:
#   URL=<tarball url> SHA256=<hex>     one upstream tarball, downloaded once as
#                                      build/<source>_<upstream version>.orig.tar.gz and
#                                      checked against the SHA-256 (quickshell)
#   GIT=<repository url> REF=<ref>     a git tree: the repository is cloned once under
#   [DATE= COUNT= COMMIT= TAG=]        (optional: the commit's UTC date, its count of
#                                      commits since TAG and its 8-digit hash, which the
#                                      upstream version carries; the build fails when the
#                                      commit does not match them)
#                                      build/git/<source>/ and "git archive <ref>" makes the
#                                      orig tarball; with UPSTREAM_DIR=<dir> in the
#                                      environment, that local working tree (uncommitted
#                                      changes included, .git excluded) is used instead, for
#                                      developing a port before it is pushed (desktop)
#   FILES=<list file>                  a list, relative to the package directory, of
#                                      "<url> <sha256>" lines: each file is downloaded and
#                                      checked, and together they form the orig tarball
#                                      (fonts)
#   DSC=<.dsc url> SHA256=<hex>        an Ubuntu (or Debian) source package rebuilt with our
#                                      additions (plymouth). The .dsc is downloaded into
#                                      build/dsc/<source>/ and checked against the SHA-256; the
#                                      tarballs the .dsc lists (orig and debian) are downloaded
#                                      next to it, and dpkg-source -x checks them against the
#                                      .dsc's checksums and unpacks the tree with their debian/
#                                      and their patches applied. The package directory's
#                                      debian/ is then laid over theirs: debian/changelog is
#                                      prepended (our entry on top of theirs), the lines of
#                                      debian/patches/series are appended to theirs, every
#                                      other file replaces or adds one, .in files are skipped.
#                                      The package directory holds only what we change: for
#                                      plymouth its patches, their series lines and one
#                                      changelog entry. No fork of the source: the orig tarball stays
#                                      theirs and dpkg-source -b applies the added patch
# and may add:
#   COMPONENT_NAMES=(<n> ...)          extra orig tarballs, one per name, fetched from
#   COMPONENT_URLS=(<url> ...)         COMPONENT_URLS and checked against COMPONENT_SHA256S,
#   COMPONENT_SHA256S=(<hex> ...)      stored as build/<source>_<ver>.orig-<n>.tar.gz and
#                                      unpacked into <n>/ inside the tree, which is where
#                                      dpkg-source puts them when the source is unpacked
#   NO_TOP_DIR=1                       the tarballs hold their files at the top, with no
#                                      <name>-<version>/ directory around them (a release's
#                                      prebuilt binaries: localsend), so they are unpacked as
#                                      they are instead of with --strip-components=1;
#                                      dpkg-source accepts such an orig tarball as it is
#   RELEASES=<owner>/<repo>            the GitHub repository whose latest release
#                                      scripts/upstream-check.sh compares with the version in
#                                      debian/changelog (make upstream-check)
#   CARGO_VENDOR=1                     run "cargo vendor" in the tree on this host (network)
#                                      and ship the result as the component "vendor", so the
#                                      chroot can build a Rust program offline
# The script unpacks the source to build/<source>-<upstream version>/, copies the package's
# debian/ in, and runs dpkg-source on that tree, so the orig tarballs sit in the directory
# dpkg-source searches (the current one). The other packages are native and need none of this.
#
# Usage: scripts/build.sh [packages/<dir> ...]     default: every directory under packages/
# Env:   WITH_REPO=1     also enable the published apt repo inside the chroot, for packages
#                        that build-depend on other packages of ours (needs the repo to be live).
#        UPSTREAM_DIR    for a GIT= package: build from this local tree instead of the ref.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"

out="$here/build"
mkdir -p "$out"
export SBUILD_CONFIG="$here/sbuild.conf"
tarball="$HOME/.cache/sbuild/$BASE_SERIES-amd64.tar"
[[ -f $tarball ]] || { echo "no chroot tarball at $tarball: run 'make chroot' first" >&2; exit 1; }

pkgs=("$@")
if ((${#pkgs[@]} == 0)); then
  mapfile -t pkgs < <(find "$here/packages" -mindepth 1 -maxdepth 1 -type d | sort)
fi

extra=()
if [[ ${WITH_REPO:-0} == 1 ]]; then
  extra+=("--extra-repository=deb $APT_URL $BASE_SERIES $APT_COMPONENT"
          "--extra-repository-key=$here/packages/archive-keyring/archive-keyring.asc")
fi

# Reproducible tarballs: sorted entries, no owner, every mtime set to the package's changelog
# date (set per package below; the epoch would make lintian call the files ancient), gzip
# without a timestamp. The same tree and changelog always give the same orig tarball.
TAR_OPTS=(--sort=name --owner=0 --group=0 --numeric-owner)

# fetch <url> <file> <sha256>: download once into <file>, then check the SHA-256 every time.
fetch() {
  local url=$1 file=$2 sum=$3
  if [[ ! -f $file ]]; then
    echo "-- downloading $url"
    curl -sSfL -o "$file.part" "$url" && mv "$file.part" "$file"
  fi
  echo "$sum  $file" | sha256sum --check --quiet || { echo "!! $file does not match the SHA-256 given for $url" >&2; exit 1; }
}

built=0
for pkg in "${pkgs[@]}"; do
  pkg=$(cd "$pkg" && pwd)
  name=$(basename "$pkg")
  if [[ ! -f $pkg/debian/changelog ]]; then
    echo "!! $name: no debian/changelog (run 'make render')" >&2; exit 1
  fi
  # A DSC= package takes debian/control from the source package it rebuilds.
  if [[ ! -f $pkg/debian/control ]] && ! grep -q '^DSC=' "$pkg/upstream" 2>/dev/null; then
    echo "!! $name: no debian/control (run 'make render')" >&2; exit 1
  fi
  if [[ $name == archive-keyring && ! -s $pkg/archive-keyring.gpg ]]; then
    echo "-- skipping $name: no public key yet (run scripts/keygen.sh)"; continue
  fi
  src=$(dpkg-parsechangelog -l "$pkg/debian/changelog" -S Source)
  ver=$(dpkg-parsechangelog -l "$pkg/debian/changelog" -S Version)
  dsc="$out/${src}_${ver#*:}.dsc"
  echo "== building $name ($src $ver)"
  tree="$pkg"
  if [[ -f $pkg/upstream ]]; then
    TAR_OPTS=(--sort=name --owner=0 --group=0 --numeric-owner)
    uver=${ver#*:}; uver=${uver%-*}
    URL= SHA256= GIT= REF= DATE= COUNT= COMMIT= TAG= FILES= DSC= CARGO_VENDOR= NO_TOP_DIR= RELEASES=
    COMPONENT_NAMES=() COMPONENT_URLS=() COMPONENT_SHA256S=()
    # shellcheck source=/dev/null
    source "$pkg/upstream"
    orig="$out/${src}_${uver}.orig.tar.gz"
    prefix="${src}-${uver}"
    TAR_OPTS+=("--mtime=@$(dpkg-parsechangelog -l "$pkg/debian/changelog" -S Timestamp)")
    if [[ -n $DSC ]]; then
      dscdir="$out/dsc/$src"
      mkdir -p "$dscdir"
      dscfile="$dscdir/$(basename "$DSC")"
      fetch "$DSC" "$dscfile" "$SHA256"
      # The files the .dsc lists sit next to it on the server. dpkg-source -x checks each
      # against the .dsc's checksums; gpgv cannot check the uploader's signature here (that key
      # is not on this host), dpkg-source says so and goes on, and the pinned SHA-256 of the
      # .dsc is what ties the download to the version this package's changelog names.
      while read -r _ _ f; do
        [[ -n $f && ! -f $dscdir/$f ]] || continue
        echo "-- downloading ${DSC%/*}/$f"
        curl -sSfL -o "$dscdir/$f.part" "${DSC%/*}/$f" && mv "$dscdir/$f.part" "$dscdir/$f"
      done < <(sed -n '/^Files:/,/^[^ ]/{/^ /p}' "$dscfile")
      tree="$out/$prefix"
      rm -rf "$tree"
      (cd "$dscdir" && dpkg-source -x "$(basename "$dscfile")" "$tree")
      # dpkg-source -b looks for the orig tarball in the current directory, build/.
      ln -f "$dscdir/${src}_${uver}.orig.tar."* "$out/"
      # Our debian/ over theirs: see the header.
      while IFS= read -r -d '' f; do
        rel=${f#"$pkg/debian/"}
        case $rel in
          *.in) ;;
          changelog) { cat "$f"; echo; cat "$tree/debian/changelog"; } > "$tree/debian/changelog.new"
                     mv "$tree/debian/changelog.new" "$tree/debian/changelog" ;;
          patches/series) mkdir -p "$tree/debian/patches"; cat "$f" >> "$tree/debian/patches/series" ;;
          *) install -D -m "$(stat -c %a "$f")" "$f" "$tree/debian/$rel" ;;
        esac
      done < <(find "$pkg/debian" -type f -print0)
    elif [[ -n $URL ]]; then
      fetch "$URL" "$orig" "$SHA256"
    elif [[ -n $GIT ]]; then
      # DATE, COUNT, COMMIT: the upstream version names the commit (the desktop's
      # +git<date>.<count>.<commit>), so a build from any other commit would put different
      # contents under that version.
      check_commit() { # check_commit <git dir> <commit>
        [[ -n $DATE ]] || return 0
        local date count commit
        date=$(TZ=UTC git -C "$1" log -1 --format=%cd --date=format-local:%Y%m%d "$2")
        count=$(git -C "$1" rev-list --count "$TAG..$2")
        commit=$(git -C "$1" rev-parse --short=8 "$2")
        if [[ $date != "$DATE" || $count != "$COUNT" || $commit != "$COMMIT" ]]; then
          echo "!! $name: the commit is $date.$count.$commit (date.count.commit) but the version says $DATE.$COUNT.$COMMIT:" >&2
          echo "   set OMARCHY_PORT_DATE=$date OMARCHY_PORT_COUNT=$count OMARCHY_PORT_COMMIT=$commit in distro.conf, add a changelog entry, and run make render" >&2
          exit 1
        fi
      }
      if [[ -n ${UPSTREAM_DIR:-} ]]; then
        echo "-- orig tarball from the local tree $UPSTREAM_DIR (UPSTREAM_DIR), not from $GIT $REF"
        if [[ -n $DATE ]]; then
          if [[ -n $(git -C "$UPSTREAM_DIR" status --porcelain 2>/dev/null) ]]; then
            echo "-- warning: $UPSTREAM_DIR has uncommitted changes, so version $uver names no commit; do not publish this build"
          else
            check_commit "$UPSTREAM_DIR" HEAD
          fi
        fi
        tar "${TAR_OPTS[@]}" --exclude-vcs --transform "s,^\./,$prefix/," -cf - -C "$UPSTREAM_DIR" . | gzip -n > "$orig.part"
      else
        cache="$out/git/$src"
        # A bare clone has no .git directory; ask git whether the cache is already a repository.
        if ! git -C "$cache" rev-parse --git-dir >/dev/null 2>&1; then
          echo "-- cloning $GIT into $cache"
          mkdir -p "$(dirname "$cache")"
          git clone -q --bare "$GIT" "$cache"
        fi
        echo "-- fetching $REF from $GIT"
        # The tag too, which the commit count is counted from.
        git -C "$cache" fetch -q "$GIT" "$REF" ${TAG:+"refs/tags/$TAG:refs/tags/$TAG"}
        check_commit "$cache" FETCH_HEAD
        git -C "$cache" archive --format=tar --prefix="$prefix/" FETCH_HEAD | gzip -n > "$orig.part"
        echo "   $src $uver = commit $(git -C "$cache" rev-parse FETCH_HEAD)"
      fi
      mv "$orig.part" "$orig"
    elif [[ -n $FILES ]]; then
      files="$out/${prefix}-files"
      rm -rf "$files"; mkdir -p "$files"
      while read -r url sum; do
        [[ -z $url || $url == \#* ]] && continue
        fetch "$url" "$files/$(basename "$url" | sed 's/%20/ /g')" "$sum"
      done < "$pkg/$FILES"
      tar "${TAR_OPTS[@]}" --transform "s,^\./,$prefix/," -cf - -C "$files" . | gzip -n > "$orig.part"
      mv "$orig.part" "$orig"
    else
      echo "!! $name: upstream names no URL=, GIT=, FILES= or DSC=" >&2; exit 1
    fi
    if [[ -z $DSC ]]; then
    tree="$out/$prefix"
    rm -rf "$tree"; mkdir -p "$tree"
    strip=(--strip-components=1); [[ ${NO_TOP_DIR:-} == 1 ]] && strip=()
    tar -xzf "$orig" "${strip[@]}" -C "$tree"
    for i in "${!COMPONENT_NAMES[@]}"; do
      comp=${COMPONENT_NAMES[$i]}
      ctar="$out/${src}_${uver}.orig-${comp}.tar.gz"
      fetch "${COMPONENT_URLS[$i]}" "$ctar" "${COMPONENT_SHA256S[$i]}"
      mkdir -p "$tree/$comp"
      tar -xzf "$ctar" "${strip[@]}" -C "$tree/$comp"
    done
    if [[ ${CARGO_VENDOR:-} == 1 ]]; then
      echo "-- cargo vendor (network) in $tree"
      (cd "$tree" && cargo vendor --locked vendor >/dev/null)
      tar "${TAR_OPTS[@]}" -cf - -C "$tree" vendor | gzip -n > "$out/${src}_${uver}.orig-vendor.tar.gz"
    fi
    rm -rf "$tree/debian"
    cp -a "$pkg/debian" "$tree/debian"
    fi
  fi
  (cd "$out" && dpkg-source -b "$tree")
  (cd "$out" && sbuild --dist="$BASE_SERIES" --arch=amd64 --arch-all --source --build-dir="$out" "${extra[@]}" "$dsc")
  built=$((built + 1))
done

if ((built == 0)); then echo "nothing built"; exit 0; fi
echo "== lintian"
lintian --fail-on error --info "$out"/*.changes
echo "== artifacts in build/"
ls -1 "$out"/*.deb "$out"/*.dsc 2>/dev/null
