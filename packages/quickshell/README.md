<!-- Generated from packages/quickshell/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# quickshell

Quickshell 0.3.2, the Qt/QML toolkit the Omarchy shell runs on, backported into Oaxaca's repository: roadmap step 5. Ubuntu's archive carries 0.3.0 and Omarchy v4.0.4 pins 0.3.2 (`omacom/omarchy-pkgs`, `pkgbuilds/quickshell/PKGBUILD`); between the two, Quickshell fixed session lock crashes on sleep, wake and unlock, which is the shell's lock screen. See `docs/5 - hyprland-quickshell.md`.

The package keeps the upstream name, as the policy says for third-party software we rebuild, and the version `0.3.2-0oaxaca1`: a new upstream release on Debian's packaging, so the `-0oaxaca1` revision marks "not in Debian yet" and sorts below a future Debian `0.3.2-1`.

| Path | What |
|---|---|
| `debian/` | Debian's `quickshell` 0.3.1-1 packaging (Michael Lloyd), with our changelog entry, Maintainer, and `DISTRIBUTOR=Oaxaca` in `rules` |
| `debian/patches/session-lock-announce-unlock.patch` | ours (`0.3.2-0oaxaca2`): `WlSessionLock::unlock()` announces the unlock, so a lock screen works more than once per login (`docs/5 - hyprland-quickshell.md`, choice 9) |
| `upstream` | the upstream tarball's URL and SHA-256; `scripts/build.sh` downloads it as the orig tarball and unpacks it around `debian/` before `dpkg-source` |

Unlike the `oaxaca-*` packages, this directory holds no upstream source: `make build PKG=packages/quickshell` fetches it into `build/`.
