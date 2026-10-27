<!-- Generated from packages/iphonebridge/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# iphonebridge

iphonebridge, a Bluetooth bridge that brings a paired iPhone's messages, contacts, notifications, calls and media controls to the desktop, published in Oaxaca's repository (docs/6, choice 109). Install > Service > iPhone installs it; no package depends on it.

The repository serves iphonebridge's own release `.deb` unchanged, the only package of that kind: no source package, no `debian/` here, no build in the chroot. The package keeps iphonebridge's name and version (`0.20.1`), and its maintainer scripts are iphonebridge's.

| Path | What |
|---|---|
| `upstream` | `DEB=`, the release `.deb`'s URL; `SHA256=`, the digest GitHub records for that file; `RELEASES=santisbon/iphonebridge` for `make upstream-check` |

`make build PKG=packages/iphonebridge` downloads the `.deb` into `build/` under its file name, `iphonebridge_<version>_all.deb`, checks the SHA-256, and checks that the file name matches the package's name, version and architecture.

A new iphonebridge release: `make upstream-check` reports it; point `DEB=` at the new release's `.deb`, set `SHA256=` to the digest GitHub shows for that file (`gh release view v<version> -R santisbon/iphonebridge --json assets`), then `make build PKG=packages/iphonebridge`.
