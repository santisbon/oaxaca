<!-- Generated from packages/owe/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# owe

OWE, the wallpaper engine behind Omarchy v4.5.0's video backgrounds and theme intros, packaged for Oaxaca's repository. The package keeps the upstream name, as the policy says for third-party software we build from source.

| Path | What |
|---|---|
| `upstream` | the tag tarball's URL and SHA-256 (the one Omarchy's recipe records), and `RELEASES=omacom/owe` for `make upstream-check` |
| `debian/rules` | builds with Meson and installs the files Omarchy's recipe installs, without its pacman hook |

`omacom/owe` has no licence file on 2026-11-05; `debian/copyright` records the MIT licence that Omarchy's recipe names.
