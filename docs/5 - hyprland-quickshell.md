# 5. Hyprland and Quickshell

Roadmap step 5 of the [plan](0%20-%20plan.md#roadmap-option-b): "use the archive versions; if Omarchy's `hyprland.lua` or shell plugins need newer versions, backport Hyprland and its hypr* libraries and Quickshell into your repo". Done 2026-10-09. The answer in one line: Hyprland stays Ubuntu's, because the archive carries the exact version Omarchy's own recipe pins; Quickshell is backported, because Omarchy builds 0.3.2, the archive has 0.3.0, and the releases in between fix crashes in the session lock, which is the Omarchy shell's lock screen. The proof is the QEMU test from step 4, which now also starts Omarchy v4.0.4's real shell on our Quickshell.

## Terms

Each entry uses only terms defined above it, in the developer README's [Terms](README.md#terms), in the plan's [Terms](0%20-%20plan.md#terms), in the policy's [Terms](1%20-%20policy.md#terms) or in [step 4's](4%20-%20session.md#terms).

### Omarchy's package recipes

`omacom/omarchy-pkgs`, a second repository of Omarchy's, holding one Arch `PKGBUILD` per package Omarchy ships from its own package server (`pkgs.omarchy.org`), each with a `.omarchy/package.json` that says how the recipe follows upstream. Where Omarchy's package list (`install/omarchy-base.packages` in the main repository) only names packages, these recipes carry the version Omarchy actually builds and any patch it applies. This document reads them at their `master` branch on 2026-10-09; the repository has no tags.

### Orig tarball and the quilt source format

A Debian source package in format `3.0 (quilt)` is an upstream tarball, kept byte for byte and named `<source>_<upstream version>.orig.tar.gz`, plus a `debian.tar.xz` holding only the `debian/` directory, plus the `.dsc` that lists both. `dpkg-source -b` builds that from a directory holding the unpacked upstream source with `debian/` inside, and looks for the orig tarball in the directory it runs in. The `oaxaca-*` packages are the other format, `3.0 (native)`, one tarball with everything, because there is no upstream.

### Partial and sparse clone

A git clone with `--filter=blob:none` fetches commits and trees but no file contents until a file is checked out; `--sparse` with `sparse-checkout set <paths>` then checks out only the named directories. Together they fetch a 2 MB corner of a 133 MB repository in seconds, with the commit pinned by tag.

### Layer surface

A Wayland window that a compositor places in a fixed layer above or below ordinary windows, through the `wlr-layer-shell` protocol: bars, backgrounds, notifications, lock screens. Each carries a namespace string its owner chooses. `hyprctl -j layers` lists them per monitor and level; the Omarchy shell names its surfaces `omarchy-bar`, `omarchy-background`, `omarchy-menu` and so on.

### IPC handler

Quickshell's mechanism for calling a function inside a running shell from outside: a QML `IpcHandler { target: "<name>" }` block declares functions, and `quickshell ipc -p <config path> call <target> <function> [args]` calls one through the instance's socket. Omarchy's `omarchy-shell` script is a wrapper around that command; its `shell ping` call returns `"ok"`.

### Software rendering

Drawing with Mesa's CPU rasterizer (`llvmpipe`) instead of a GPU. A compositor on software rendering has no GPU fences to wait on, so it needs a different synchronization path; Hyprland selects that path by recognizing the renderer. QEMU without virgl, and Apple Silicon machines on the `simpledrm` driver, are software-rendered.

## Anatomy

The same three targets as step 4, with one new package directory and one new check:

| You run | Script | Tool underneath | What changed in step 5 |
|---|---|---|---|
| `make build PKG=packages/quickshell` | `scripts/build.sh` | `curl` for the [orig tarball](#orig-tarball-and-the-quilt-source-format), then `dpkg-source -b` and `sbuild` as before | the script now handles a package directory that holds only `debian/` and an `upstream` file: it downloads the tarball into `build/`, checks the SHA-256, unpacks it to `build/quickshell-0.3.2/`, copies `debian/` in, and runs `dpkg-source` on that tree |
| `make rootfs` | `scripts/rootfs-create.sh` | `mmdebstrap` | the `session` profile also passes `build/quickshell_*.deb` to `--include`, by its upstream name |
| `make rootfs-test` | `scripts/rootfs-boot-test.sh` | `git` ([sparse clone](#partial-and-sparse-clone) of Omarchy's `shell/` and `config/omarchy/`, cached in `build/omarchy/<tag>/`), then QEMU as before | the test image gets Omarchy's shell at `/usr/share/omarchy/`; the guest starts it on the installed Quickshell and checks the [IPC](#ipc-handler) ping and the bar's [layer surface](#layer-surface) |

## What Omarchy needs, what the archive has

Omarchy v4.0.4's package list names, out of the Hyprland world: `hyprland`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`, `quickshell`, `wl-clipboard`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`, `xdg-terminal-exec`, and `qt6-wayland` in its "other" list. The versions come from Omarchy's [package recipes](#omarchys-package-recipes), which pin what Omarchy's package server builds.

| Software | Omarchy builds | `stonking` has | Debian sid has | Step 5's answer |
|---|---|---|---|---|
| Hyprland | 0.56.2 (`pkgbuilds/hyprland`, with one patch, below) | `hyprland 0.56.2+ds-1` | `0.56.2+ds-3` | the archive's. Same upstream version; Omarchy's recipe also carries `software-renderer.patch`, a backport of Hyprland pull request 16343 (merged upstream 2026-09-27, after 0.56.2), which Ubuntu's and Debian's patch sets lack; see choice 6 |
| Quickshell | 0.3.2 (`pkgbuilds/quickshell`; released upstream 2026-10-08) | `quickshell 0.3.0-1build1` (released 2026-05-04) | `0.3.1-1` | **backported**: `quickshell 0.3.2-0oaxaca1`, choice 1 |
| hypr* libraries | whatever Arch ships for 0.56.2 | `libhyprlang2 0.6.8`, `libhyprutils13 0.14.1`, `libhyprgraphics4 0.5.1`, `libhyprcursor0 0.1.13`, `libaquamarine13 0.14.0`, `libhyprwire3 0.3.1`, `hyprland-protocols 0.7.0` | similar, `libhyprutils13 0.14.2` | the archive's: Ubuntu's Hyprland is built against them, and nothing of Omarchy's links to them directly |
| Companions | `hyprland-guiutils`, `hyprpicker`, `hyprsunset`, `wl-clipboard`, `xdg-terminal-exec` | `0.2.2`, `0.4.7`, `0.4.0`, `2.3.0`, `0.14.3` | same or newer | all present; they are called by `omarchy-*` scripts, so they join the desktop package in step 6, not this layer |
| `hyprland-preview-share-picker` | 0.2.1 (`pkgbuilds/hyprland-preview-share-picker`, a Rust program, GTK4) | not packaged | not packaged | step 6 packaging, with `nwg-displays` and `asdcontrol` |
| Hyprland plugins | `omarchy-hyprland-titlebars` 0.1.0 (`depends=('hyprland=0.56.2')`), `cua-hyprland-plugin` | `hyprland-plugin-*` 0.56.0 (not Omarchy's) | same | not in Omarchy's package list, so not needed for v4.0.4's shell; recorded for step 6. Ubuntu's `hyprland` declares `Provides: hyprland-abi-b51ae4c`, the exact plugin ABI, which a rebuilt plugin would depend on |

**Hyprland's configuration API.** Omarchy's `default/hypr/*.lua` and `config/hypr/*.lua` call 38 distinct functions on Hyprland's Lua object (`hl.env`, `hl.animation`, `hl.config`, `hl.bind`, `hl.on`, `hl.monitor`, `hl.layer_rule`, `hl.window_rule`, `hl.gesture`, `hl.timer`, `hl.device`, the `hl.dsp.*` dispatchers for focus, window, workspace, group and layout, and a few more). Since the archive's Hyprland is the same 0.56.2 that Omarchy's recipe builds and tests against, every one of those calls meets the Lua API it was written for. No check beyond the version is needed here; the port of those files is step 6.

**What the shell imports from Quickshell.** Across `shell/`, 49 files import `Quickshell`, 44 `Quickshell.Io`, 17 `Quickshell.Wayland`, 5 `Quickshell.Hyprland`, 4 `Quickshell.Services.Pipewire`, 2 each `Quickshell.Services.UPower` and `.Mpris`, and one each `Quickshell.Services.SystemTray`, `.Polkit`, `.Pam`, `.Notifications`, `Quickshell.Networking` and `Quickshell.Bluetooth`. Ubuntu's `quickshell` 0.3.0 build ships every one of those QML modules (checked in its `.deb`), and Debian's `rules` turns on none of Quickshell's feature options explicitly, so all of them default on; our build keeps that. The difference between 0.3.0 and 0.3.2 is therefore not modules but behaviour: the fixes listed under choice 1.

## The quickshell package

`packages/quickshell/` is the first package in this repository that is not ours: the policy's naming rule keeps the upstream name for third-party software we rebuild, and the version follows the "third-party we package from source" row, `0.3.2-0oaxaca1`, which sorts above the archive's `0.3.0-1build1` and Debian's `0.3.1-1`, and below a future Debian `0.3.2-1`.

| Path in `packages/quickshell/` | Origin | Content |
|---|---|---|
| `debian/control.in`, `rules.in`, `copyright`, `quickshell.1`, `qs.1` (a symlink to it: the `qs` alias of the command gets the same page), `quickshell.manpages`, `source/format`, `watch`, `upstream/metadata`, `upstream/signing-key.asc` | Debian's `quickshell` 0.3.1-1 (Michael Lloyd), fetched from `deb.debian.org` as `quickshell_0.3.1-1.debian.tar.xz` on 2026-10-09 | unchanged, except: `control.in` carries our `Maintainer` and Debian's as `XSBC-Original-Maintainer` (Ubuntu's convention for a Debian package it changes) and drops the `Vcs-*` fields that named Debian's git tree; `rules.in` sets `-DDISTRIBUTOR="Oaxaca"`, the string Quickshell prints in `--version` and in crash reports. Debian's `gbp.conf` and `salsa-ci.yml` are not copied: they drive Debian's own workflow |
| `debian/changelog.in` | ours on top of Debian's history | the `0.3.2-0oaxaca1` entry with the reasons, then Debian's entries |
| `upstream` | ours | `URL=` of the GitHub release tarball for tag `v0.3.2` and `SHA256=` of it. The checksum is the one Omarchy's recipe records; the download matched it on 2026-10-09 |
| `README.md.in` | ours | the summary of the above |

The upstream source is not in the repository: `scripts/build.sh` downloads it into `build/` on the first build (500 kB) and reuses it after. The build itself is Debian's `dh --buildsystem=cmake+ninja` with `NO_PCH=ON` (Debian's workaround for non-deterministic debug information) and `INSTALL_QML_PREFIX=lib/<multiarch>/qt6/qml`, the path Ubuntu's Qt loads QML modules from. All 27 build dependencies are in `stonking` at the versions Debian's `control` asks for; Quickshell's `CMakeLists.txt` did not change its requirements between 0.3.1 and 0.3.2 (diffed), and Qt stays 6.11.2.

## Files this step adds to the root filesystem

| Path in the root filesystem | Written by | Content |
|---|---|---|
| `/usr/bin/quickshell`, `/usr/lib/x86_64-linux-gnu/qt6/qml/Quickshell/**` | `quickshell 0.3.2-0oaxaca1` | the toolkit binary and its QML modules; `quickshell --version` reports 0.3.2 and distributor Oaxaca |
| `/usr/share/man/man1/quickshell.1.gz` | same | Debian's man page |

`oaxaca-session` now depends on `quickshell (>= 0.3.2)`, so an installed system takes ours from the repository and never the archive's 0.3.0. The test image, and only the test image, also gets `/usr/share/omarchy/shell/` and `/usr/share/omarchy/config/omarchy/` from Omarchy's tag, for the check below.

## Choices

1. **Quickshell is backported to 0.3.2; Hyprland is not touched.** The deciding facts are Quickshell's own changelogs. 0.3.1 (2026-08-21): "fixed session lock crashes on sleep, wake, DPMS, and unlocking", "fixed crashes when a wifi network disappear[s]", plus a dozen other crash fixes in `FileView`, `ScriptModel`, `ScreencopyView` and `PwNodePeakMonitor`, all of which the Omarchy shell uses (34 `FileView`s, the lock plugin on the session lock, the network panel). 0.3.2 (2026-10-08): "fixed main process crashes on pam subprocess misbehavior" (the lock screen authenticates through `Quickshell.Services.Pam`), "fixed networking state breaking after restarting NetworkManager", support for Hyprland's new workspace address format. A lock screen that can crash on unlock is a session the user cannot get back into, and Omarchy's `omarchy-restart-shell` carries a whole paragraph on recovering from exactly that. Omarchy tests its shell on 0.3.2, so that is the version to run it on. Rejected: the archive's 0.3.0, which would ship known crashes in the lock screen to save one package; waiting for Ubuntu, which will not update an interim release's universe package to a new upstream.
2. **Built from Debian's packaging, not from Omarchy's recipe.** Debian's `debian/` is written for `dh`, carries the right multiarch QML path, the man page and a reviewed `copyright`, and is what Ubuntu's own 0.3.0 package is; Omarchy's `PKGBUILD` is for `makepkg` and would have to be translated. The only values taken from Omarchy's recipe are the version and the tarball checksum. Rejected: writing a `debian/` from scratch.
3. **The upstream tarball is fetched at build time from an `upstream` file, not stored in git.** The `upstream` file names the URL and the SHA-256, `build.sh` verifies the download, and the repository stays free of 500 kB binary blobs that would change with every version. The same mechanism will serve `nwg-displays`, `asdcontrol` and `hyprland-preview-share-picker` in step 6. Rejected: committing the tarball (bloats history); `git-buildpackage` with an upstream branch (a second workflow to learn for one package); `uscan` with Debian's `watch` file (it is kept, but it needs network and a GPG verification step that our CI runner would have to replicate).
4. **Version `0.3.2-0oaxaca1`.** The policy's row for third-party software packaged from source: the Debian revision `0` says "not in Debian", `oaxaca1` says whose build. When Debian uploads `0.3.2-1`, it sorts above ours, which is right: at that point our package has no reason to exist and the next rebase drops it.
5. **`quickshell` is a dependency of `oaxaca-session`, not of a later package.** Step 5 is "Hyprland + Quickshell", the toolkit the whole desktop runs on, and the session layer is where Hyprland already is; having both in one metapackage means `apt policy oaxaca-session` shows the compositor and the toolkit a system was built with. The companion tools from Omarchy's list (`hyprpicker`, `hyprsunset`, `hyprland-guiutils`, `wl-clipboard`, `xdg-terminal-exec`) are called by `omarchy-*` scripts, so they belong with those scripts in step 6's desktop package. Rejected: a third metapackage for the toolkit alone.
6. **No Hyprland rebuild for Omarchy's software-rendering patch.** Omarchy's recipe backports Hyprland pull request 16343 ("render: detect software rendering from the GL renderer"), merged upstream after 0.56.2, so that Hyprland on a CPU renderer takes its synchronization fallback and does not tear. That case is a machine with no GPU acceleration: Apple Silicon on `simpledrm`, which the pull request was written for, and QEMU without virgl, which is this repository's CI fallback. On this workstation the test runs with virgl through the Intel render node, and no supported hardware in the plan is software-rendered. A rebuilt Hyprland would mean maintaining a patch and the plugin ABI string for one unsupported case. Rejected for now; if the CI fallback run shows torn or incomplete frames in the shell check, the patch is one `debian/patches` entry away on the same packaging path as `quickshell`.
7. **The proof is Omarchy's real shell, not a synthetic QML file.** The check copies `shell/` and `config/omarchy/` from the pinned Omarchy tag into the test image and starts the shell the way Omarchy's `omarchy-launch-shell` does (`quickshell -n -p <dir>` with `QS_DISABLE_FILE_WATCHER=1` and `QS_NO_RELOAD_POPUP=1`), without any `omarchy-*` script installed. Every helper call fails, and the shell is written to survive that; what the check proves is that the archive's Hyprland plus our Quickshell load the shell's 150 QML files, answer its `shell ping` and put its bar on screen. The error lines in the shell's journal are printed and counted, not judged: they are the missing scripts, and step 6 is where they stop. Rejected: a hand-written QML that imports every module (proves nothing about Omarchy's code); porting the whole of Omarchy first (that is step 6).
8. **The Omarchy tree for the test comes from a sparse git clone, cached under `build/omarchy/<tag>/`.** 2 MB instead of a 133 MB tarball, pinned to the tag in `distro.conf`, and the cache is outside git. Rejected: GitHub's tag tarball (the whole tree); vendoring the shell into the repository (it arrives in step 6 as `oaxaca-shell`, renamed).
9. **Quickshell patched so the lock screen works more than once per login (2026-10-15, `0.3.2-0oaxaca2`).** On the laptop the lock worked the first time after each login and never again until the shell restarted: the lock service's log showed `secure=false` on unlock but no `session-locked=false`, and `oaxaca-shell lock status` then read `"locked":true` with `requested`, `sessionLocked` and `secure` all false. In Quickshell 0.3.2's `src/wayland/session_lock.cpp`, `WlSessionLock::unlock()` releases the lock through `SessionLockManager::unlock()`, which clears the lock object, and only then runs `if (this->isLocked()) emit this->lockStateChanged();`, which is false by then, so the unlock is never announced; the shell's `locked` binding (`lockRequested || sessionLock.locked || sessionLock.secure`, `shell/plugins/lock/Service.qml`) keeps its value, and the lock IPC handler (`if (!root.locked && !root.beginLock()) return "failed"; return "ok"`) then answers "ok" without locking, which is also what the before-sleep lock asks for. `debian/patches/session-lock-announce-unlock.patch` reads the state before releasing it. Quickshell's master branch has the same code (2026-10-15); Omarchy's own Quickshell package (`omacom/omarchy-pkgs`, `pkgbuilds/quickshell`, `pkgrel=6`) carries one patch, `load_qtquick_611.patch`, for Qt 6.11's QML loading, and nothing for the lock. Rejected: working around it in the shell's QML, which would leave every other `WlSessionLock.locked` binding wrong.

## Running it

```
make build PKG=packages/quickshell          # downloads build/quickshell_0.3.2.orig.tar.gz, builds in the chroot
make build PKG=packages/session             # oaxaca-session now depends on quickshell (>= 0.3.2)
make rootfs                                 # session profile: includes build/quickshell_*.deb
make rootfs-test                            # step 4's checks plus the Omarchy shell check
```

The first `make rootfs-test` on a workstation clones Omarchy's `shell/` and `config/omarchy/` into `build/omarchy/v4.0.4/` (network, a few seconds). `KEEP=1` keeps the test tree; the guest prints the shell's journal error lines at the end of the session block.

## Verified on 2026-10-09

All on the Legion laptop, then running Kubuntu 26.04.1 (24 CPUs, KVM, Intel iGPU render node).

- `make build PKG=packages/quickshell`: the first run downloaded `build/quickshell_0.3.2.orig.tar.gz` (500 985 bytes, checksum matched) and failed in `dh_installman`, because Debian's `debian/qs.1` is a symlink to `quickshell.1` and the file copy that created `packages/quickshell/` had skipped symlinks; with the symlink added, the build takes 3 min 10 s in the chroot (`Build needed 00:03:10`) and yields `quickshell_0.3.2-0oaxaca1_amd64.deb`, 1.7 MB. lintian: the `groff-message` warning that this workstation raises for every man page (step 4's finding) on `quickshell.1` and `qs.1`, and `newer-standards-version 4.7.4 (current is 4.7.3)`, which says this workstation's lintian is older than the Standards-Version Debian's packaging declares; neither is an error, and CI's lintian is the check that counts.
- `make build PKG=packages/session`: builds; `oaxaca-session` now carries `Depends: … quickshell (>= 0.3.2)`.
- `make rootfs`: 2.3 GB tarball, 605 packages in the manifest (591 after step 4's keyring addition), `quickshell 0.3.2-0oaxaca1` among them from `build/`, not the archive.
- `make rootfs-test`: the first run cloned Omarchy's `shell/` and `config/omarchy/` at v4.0.4 (commit `c668141`) into `build/omarchy/v4.0.4/`. Step 4's checks all pass as before, then the step 5 lines, in the guest's own words:
  ```
  quickshell: Quickshell 0.3.2 (revision , distributed by Oaxaca)
  omarchy shell unit: active
  omarchy shell ping: ok
  omarchy shell layers: [omarchy-bar]
  omarchy shell log: 7 lines, 0 matching error patterns
  ```
  So on Ubuntu's Hyprland 0.56.2 with virgl, our Quickshell loads Omarchy v4.0.4's shell, the shell's `IpcHandler` answers `ping` with `ok` twelve seconds after launch, and its bar is on screen as the layer surface `omarchy-bar`. The shell wrote seven lines to its journal in those twelve seconds and none of them matches an error pattern, with no `omarchy-*` script, no theme and no Nerd Font installed: the shell's startup tolerates all of that, as choice 7 expected. The other layer surfaces (`omarchy-background`, `omarchy-menu`, …) appear on demand, when a theme sets a background or a key opens the menu, so their absence here says nothing.
- The empty `revision` in `quickshell --version` is expected: Quickshell fills it from `git` at build time, and the orig tarball has no `.git`; Debian's build prints the same.

## Open work

What is left from this step is in the developer README's [To do](README.md#to-do), the one list of open work.

## Facts checked on 2026-10-09

| Fact | Value | Source |
|---|---|---|
| Omarchy v4.0.4 package list, Hyprland world | `hyprland`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`, `quickshell`, `wl-clipboard`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-hyprland`, `xdg-terminal-exec`; `qt6-wayland` in `omarchy-other.packages` | `install/omarchy-base.packages`, `install/omarchy-other.packages` at tag v4.0.4 |
| Omarchy's Hyprland recipe | `pkgver=0.56.2`, `pkgrel=5`, `software-renderer.patch` ("Backport of hyprwm/Hyprland#16343; drop once the packaged release includes it"), `sync: false` in `.omarchy/package.json` | `omacom/omarchy-pkgs` master, `pkgbuilds/hyprland/` |
| Hyprland pull request 16343 | "render: detect software rendering from the GL renderer", merged 2026-09-27; classifies the GL context instead of DRM driver names so software renderers use the existing synchronization fallback; validated on Apple M3 with `simpledrm` | GitHub API, `hyprwm/Hyprland` |
| Omarchy's Quickshell recipe | `pkgver=0.3.2`, `pkgrel=2`, `DISTRIBUTOR='Omarchy'`, `CRASH_REPORTER=Off`, `INSTALL_QML_PREFIX=lib/qt6/qml`, a `pacman` hook running `quickshell --private-check-compat` after Qt updates; `quickshell-git` pinned to the same commit `4f508be` | `pkgbuilds/quickshell/`, `pkgbuilds/quickshell-git/` |
| Quickshell releases | 0.3.0 2026-05-04, 0.3.1 2026-08-21, 0.3.2 2026-10-08 | GitHub releases, `quickshell-mirror/quickshell` |
| Quickshell 0.3.1 changelog | session lock crashes on sleep, wake, DPMS and unlocking; crashes on wifi network disappearing; `FileView`, `ScriptModel`, `ScreencopyView`, `PwNodePeakMonitor`, `JsonAdapter`, `PopupAnchor`, `PanelWindow` crash fixes; `qs kill` and IPC fixes | `changelog/v0.3.1.md` at tag v0.3.1 |
| Quickshell 0.3.2 changelog | Qt 6.12 support; Hyprland's new workspace address format; crashes on pam subprocess misbehavior, reentrant session locks, async `Loader` on reload; networking after NetworkManager restart; `Socket` reconnects; open wifi networks' security | `changelog/v0.3.2.md` at tag v0.3.2 |
| Quickshell 0.3.2 tarball | `quickshell-0.3.2.tar.gz`, 500 985 bytes, SHA-256 `946a27e2…420f7`, the value in Omarchy's recipe | download from `github.com/quickshell-mirror/quickshell/archive/refs/tags/v0.3.2.tar.gz`, `sha256sum` |
| Quickshell build requirements 0.3.1 to 0.3.2 | no change in any `CMakeLists.txt` or `.cmake` file's `find_package`, `pkg_check` or version lines; `QT_MIN_VERSION 6.6.0` | `diff -r` of the two tarballs |
| Ubuntu's `quickshell 0.3.0-1build1` ships | QML modules `Quickshell`, `Bluetooth`, `DBusMenu`, `Hyprland` (IPC, global shortcuts, focus grab, surface extensions), `I3`, `Io`, `Networking`, `Services/{Greetd,Mpris,Notifications,Pam,Pipewire,Polkit,SystemTray,UPower}`, `Wayland` (layer shell, session lock, screencopy, toplevel management, idle), `Widgets`, `WindowManager`, `X11` | the `.deb` from `stonking` universe |
| Debian's `quickshell` packaging | `0.3.1-1`, `3.0 (quilt)`, no patches, `dh --buildsystem=cmake+ninja`, `-DDISTRIBUTOR="Debian" -DNO_PCH=ON -DINSTALL_QML_PREFIX=lib/$(DEB_HOST_MULTIARCH)/qt6/qml`, 27 build dependencies | `quickshell_0.3.1-1.debian.tar.xz` from `deb.debian.org` |
| `stonking` build dependencies | all 27 present: Qt 6.11.2 (`qt6-base-dev 6.11.2+dfsg-4ubuntu2`, `-declarative-dev`, `-wayland-dev`, `-shadertools-dev` and the private-dev packages), `libcli11-dev 2.6.1`, `libcpptrace-dev 1.0.4`, `wayland-protocols 1.49`, `libpipewire-0.3-dev 1.6.8`, `libpolkit-*-dev 127`, `libjemalloc-dev 5.3.1`, `spirv-tools 2026.3~rc1` | the archive's `Packages` indexes |
| `stonking` Hyprland world | `hyprland 0.56.2+ds-1` (`Provides: hyprland-abi-b51ae4c, hyprland-api-0.1`; `Recommends: libcap2-bin, xwayland, xdg-desktop-portal-hyprland`), `hyprland-guiutils 0.2.2`, `hyprpicker 0.4.7`, `hyprsunset 0.4.0`, `hypridle 0.1.8`, `hyprlock 0.9.6`, `hyprpaper 0.8.4`, `hyprpolkitagent 0.1.3`, `hyprland-plugin-* 0.56.0`, `wl-clipboard 2.3.0`, `xdg-terminal-exec 0.14.3`, `nwg-displays 0.3.28`; libraries `libhyprlang2 0.6.8-4build2`, `libhyprutils13 0.14.1-1`, `libhyprgraphics4 0.5.1-2build2`, `libhyprcursor0 0.1.13-2`, `libaquamarine13 0.14.0-2build1`, `libhyprwire3 0.3.1-3build1` | same |
| Ubuntu's Hyprland patches | `Add-dumpabiver-abi-helper`, `Fix-shader-inclusion-order`, `Move-hyprland.pc-into-libdir`, `Update-hyprland.pc-requires-to-include-lua`, `add-fortify-flags-for-subprojects`, `embed`, `gcc-port`, `hyprpm-global-headers`, `libcpp-port`, `useful-asset-error`; Debian's `+ds-3` adds `Relax-glaze-version-requirement` and `update-links-to-wiki`; neither has the software-renderer patch | `hyprland_0.56.2+ds-1.debian.tar.xz` from Launchpad; `sources.debian.org` |
| Hyprland releases | 0.56.2 2026-08-05, 0.56.1 2026-07-27, 0.56.0 2026-07-20, 0.55.4 2026-06-11 | GitHub releases, `hyprwm/Hyprland` |
| Omarchy shell imports | 49 files `Quickshell`, 44 `Quickshell.Io`, 17 `Quickshell.Wayland`, 5 `Quickshell.Hyprland`, 4 `Quickshell.Services.Pipewire`, 2 `.UPower`, 2 `.Mpris`, 1 each `.SystemTray`, `.Polkit`, `.Pam`, `.Notifications`, `Quickshell.Networking`, `Quickshell.Bluetooth`; types used include 103 `Process`, 50 `WlrLayershell`, 34 `FileView`, 27 `IpcHandler`, 20 `PanelWindow`, 2 `PamContext`, `PolkitAgent` | `grep` over `shell/` at tag v4.0.4 (commit `c668141`) |
| Omarchy's Hyprland Lua calls | 38 distinct `hl.*` functions; most used `hl.env` (21), `hl.animation` (16), `hl.dsp.focus` (14), `hl.config` (14), `hl.dsp.window.resize` (13) | `grep` over `default/hypr/` and `config/hypr/` |
| Omarchy's shell launcher | `QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 systemd-cat -t omarchy-shell -- quickshell -n -p "$OMARCHY_PATH/shell"`, relaunched up to 5 times a minute; `OMARCHY_PATH` defaults to `/usr/share/omarchy` in `default/hypr/paths.lua` | `bin/omarchy-launch-shell`, `default/hypr/paths.lua` |
| Omarchy's shell IPC | `IpcHandler { target: "shell" }` with `function ping(): string { return "ok" }`; 17 targets in all; layer namespaces `omarchy-bar`, `omarchy-background`, `omarchy-menu`, `omarchy-notifications`, `omarchy-osd`, `omarchy-polkit` and ten more | `shell/shell.qml`, `grep` over `shell/` |
| Quickshell command line | `quickshell -p <path>` selects the config by path, `-n` is `--no-duplicate`; `quickshell ipc -p <path> call <target> <function> [arguments]` | `src/launch/parsecommand.cpp` at tag v0.3.2 |
| Omarchy repository size | 133 MB checked out; `shell/` 2.0 MB, `config/omarchy/` 36 kB | `du` on the v4.0.4 clone |
