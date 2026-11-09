<!-- Generated from packages/quickshell/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# quickshell

Quickshell at commit 2b4501a2 (7 commits past tag v0.3.2, the commit Omarchy v4.5.0's recipe builds), the Qt/QML toolkit the Omarchy shell runs on, backported into Oaxaca's repository: roadmap step 5. Ubuntu's archive carries 0.3.0 and Omarchy v4.0.4 pins 0.3.2 (`omacom/omarchy-pkgs`, `pkgbuilds/quickshell/PKGBUILD`); between the two, Quickshell fixed session lock crashes on sleep, wake and unlock, which is the shell's lock screen. See `docs/5 - hyprland-quickshell.md`.

Omarchy's recipe also carries `load_qtquick_611.patch`, its work-around for Qt 6.12. Ubuntu's Qt is 6.11, so this package leaves the patch out. The first line of `shell/shell.qml`, `//@ pragma OmarchyLoadPatch`, then only makes Quickshell log `Unrecognized pragma`.

The package keeps the upstream name, as the policy says for third-party software we rebuild, and the version `0.3.2+r7.g2b4501a-0oaxaca1`: a new upstream release on Debian's packaging, so the `-0oaxaca1` revision marks "not in Debian yet". The `+r7.g2b4501a` part ranks the version above a Debian `0.3.2-1` and below a Debian `0.3.3-1` (`dpkg --compare-versions`), so apt replaces this package once the archive carries Quickshell 0.3.3 or newer.

| Path | What |
|---|---|
| `debian/` | Debian's `quickshell` 0.3.1-1 packaging (Michael Lloyd), with our changelog entry, Maintainer, and `DISTRIBUTOR=Oaxaca` in `rules` |
| `upstream` | the upstream tarball's URL and SHA-256; `scripts/build.sh` downloads it as the orig tarball and unpacks it around `debian/` before `dpkg-source` |

Unlike the `oaxaca-*` packages, this directory holds no upstream source: `make build PKG=packages/quickshell` fetches it into `build/`.
