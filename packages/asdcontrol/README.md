<!-- Generated from packages/asdcontrol/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# asdcontrol

asdcontrol 0.6.0, a command-line program that reads and sets the brightness of an Apple Studio Display or an Apple Pro Display XDR over the display's USB HID interface, packaged for Oaxaca's repository: roadmap step 6. Ubuntu's archive has no asdcontrol; Omarchy v4.0.4 installs the program from its own repository (`omacom/omarchy-pkgs`, `pkgbuilds/asdcontrol/PKGBUILD`).

The package keeps the upstream name, as the policy says for third-party software we package from source, and the version `0.6.0-0oaxaca1`: the `-0oaxaca1` revision marks "not in Debian" and sorts below a future Debian `0.6.0-1`.

## What the package installs

| Path | What |
|---|---|
| `/usr/bin/asdcontrol` | the program, one C++ file built with the upstream `Makefile` (`g++`, dpkg's hardening flags) |
| `/etc/sudoers.d/50-asdcontrol` | Omarchy's sudoers rule (`omacom/omarchy-pkgs`, `pkgbuilds/asdcontrol/asdcontrol.sudoers`) with `%sudo`, Ubuntu's admin group, in place of Arch's `%wheel`; mode 0440, a conffile |

## Where the source comes from

| File in this directory | What |
|---|---|
| `upstream` | the upstream tarball's URL and SHA-256; `scripts/build.sh` downloads the tarball as the orig tarball and unpacks the tarball around `debian/` before `dpkg-source` |
| `debian/` | our packaging: `control.in`, `changelog.in`, `rules`, `copyright` (GPL-2+, pointing at the GPL-2 text in /usr/share/common-licenses as lintian requires), `install`, `asdcontrol.sudoers` |

The tarball is GitHub's archive of the upstream tag `v0.6.0` (https://github.com/omakasui/asdcontrol/archive/refs/tags/v0.6.0.tar.gz). The SHA-256 in `upstream`, `3112a6d5fc51a204c96ef9d27187577c6efc80b952e37a77969efbd0124e81d3`, is the checksum Omarchy's PKGBUILD records; the same checksum came out of `sha256sum` on the download on 2026-10-10.

Unlike the `oaxaca-*` packages, this directory holds no upstream source: `make build PKG=packages/asdcontrol` fetches the source into `build/`.

## What the distro uses asdcontrol for

The desktop's `oaxaca-brightness-display-apple` script (Omarchy's `omarchy-brightness-display-apple`, renamed by the port) runs `sudo asdcontrol` three ways: `asdcontrol --detect /dev/usb/hiddev* ...` to find the display, `asdcontrol <device>` to read the brightness, and `asdcontrol <device> -- +5%` (or `-5%`, or `50%`) to set the brightness. The `/dev/hiddev*` nodes belong to root, which is why the script needs sudo, and the sudoers rule exists so that the brightness keys work without a password prompt. The rule first denies `asdcontrol` with arbitrary arguments to everyone, then allows members of the `sudo` group exactly those three argument shapes, matched as regular expressions.

The regular-expression match needs sudo 1.9.10 or later (Ubuntu's `sudo` package, 1.9.17 in stonking, has the feature); `sudo-rs`, the Rust rewrite Ubuntu installs alongside classic sudo on its own images, rejects the rule with "regular expressions are not supported". Oaxaca's `oaxaca-base` package depends on classic `sudo`, and `debian/rules` runs `visudo -c -f` on the rule with the chroot's classic sudo at build time, so a rule sudo would reject fails the build.
