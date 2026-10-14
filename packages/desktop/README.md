<!-- Generated from packages/desktop/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-desktop

The Omarchy port: roadmap step 6. One source package built from the `oaxaca` branch of the fork `https://github.com/santisbon/omarchy` (Omarchy `v4.0.4` plus the port commits), producing five binary packages, all at version `4.0.4+git20261014.23.d1c146fc-0oaxaca<N>`: the Omarchy tag, `+git` and the date (UTC) of the fork commit built (`OMARCHY_PORT_DATE` in `distro.conf`, which `scripts/build.sh` checks against the commit), then the Debian revision. See `docs/6 - omarchy-port.md`.

| Binary package | What it carries | Omarchy's own package it mirrors |
|---|---|---|
| `oaxaca-desktop` | the metapackage: the four below, `oaxaca-session`, `oaxaca-fonts`, `asdcontrol`, `hyprland-preview-share-picker`, `nwg-displays`, and every Ubuntu package named in the port's `install/oaxaca-base.packages` (read at build time into the dependency list) | the ISO's package list |
| `oaxaca-tools` | `/usr/bin/oaxaca-*` (Omarchy's `bin/`, ported to apt), their symlinks under `/usr/share/oaxaca/bin/`, the install tree `/usr/share/oaxaca/install/`, the `version` file, and the `fd` and `bat` names for Ubuntu's `fdfind` and `batcat` | `omarchy` |
| `oaxaca-shell` | `/usr/share/oaxaca/shell/` (the Quickshell shell) and the icon font `/usr/share/fonts/truetype/oaxaca/oaxaca.ttf`, its family renamed to `oaxaca` | `omarchy` |
| `oaxaca-themes` | `/usr/share/oaxaca/themes/` and `/usr/share/oaxaca/default/themed/` | `omarchy` |
| `oaxaca-config` | `/usr/share/oaxaca/default/` and `/usr/share/oaxaca/config/`, `/etc/skel/` seeds (`.config`, `.bashrc`, launchers, toggles), `/etc/` drop-ins (sudoers, sysctl, logind, oomd, resolved, docker, NetworkManager, sddm theme, fastfetch, kitty, apt periodic), the uwsm `env.d` file, `environment.d`, fontconfig, the systemd user units, zram and plocate drop-ins, the sleep hook, launchers and icons, the SDDM theme, the Wayland session file, the Plymouth theme files, branding | `omarchy-settings` |

## How the build works

`scripts/build.sh` reads the `upstream` file (`GIT=`, `REF=`) and makes the orig tarball with `git archive` from the fork; with `UPSTREAM_DIR=~/Projects/omarchy make build PKG=packages/desktop` it takes the local checkout instead, uncommitted changes included, which is how the port is developed before it is pushed. `debian/rules` then copies the tree to `debian/renamed/`, runs the port's `port/rename.sh` on that copy with `DISTRO_ID=oaxaca` and `DISTRO_NAME=Oaxaca`, writes the `version` file from the changelog, renders the branding placeholders, converts the application icons to the hicolor sizes, and `debian/install-tree.sh` lays the renamed copy out into the four package directories the way Omarchy's two recipes (`omacom/omarchy-pkgs`, `pkgbuilds/omarchy` and `pkgbuilds/omarchy-settings`) do. The metapackage's dependency list is the `port:Depends` substitution variable, filled from the package list in the renamed tree.

## Branding

Omarchy's name is a trademark and its logos are Omarchy's. The build replaces them: `logo.txt`, `icon.txt` and `logo.svg` come from `debian/extra/` (the distro's name in a box) and `icon.png`, the SDDM logo and the Plymouth logo are the name rendered with ImageMagick. The theme wallpapers that carried Omarchy's mark are not installed. These are placeholders until the distro has artwork; the icon font keeps Omarchy's mark at `U+E900` (the menu shows it next to "Oaxaca" entries) until a glyph replaces it.

## What is not here

The port's choices and drop list are in `docs/6 - omarchy-port.md`; the branch's own rules are in the fork's `PORT.md`.
