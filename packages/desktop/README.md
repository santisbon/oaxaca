<!-- Generated from packages/desktop/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-desktop

The Omarchy port: roadmap step 6. One source package built from the `oaxaca` branch of `santisbon/omarchy` (`https://github.com/santisbon/omarchy`) (Omarchy `v4.5.0` plus the port commits), producing five binary packages, all at version `4.5.0+git20261112.364.7c145081-0oaxaca<N>`: the Omarchy tag, `+git` and the date (UTC) of the commit of `santisbon/omarchy` built (`OMARCHY_PORT_DATE` in `distro.conf`, which `scripts/build.sh` checks against the commit), then the Debian revision. See `docs/6 - omarchy-port.md`.

| Binary package | What it carries | Omarchy's own package it mirrors |
|---|---|---|
| `oaxaca-desktop` | the metapackage: the four below, `oaxaca-session`, `oaxaca-fonts`, `asdcontrol`, `hyprland-preview-share-picker`, `localsend`, `ttfx`, `nwg-displays`, `oaxaca-hyprland-titlebars`, `owe`, `disktree`, `gliff`, `oaxaca-speedtest`, `ffmpegthumbnailer`, and every Ubuntu package named in the port's `install/oaxaca-base.packages` (read at build time into the dependency list) | the ISO's package list |
| `oaxaca-tools` | `/usr/bin/oaxaca-*` (Omarchy's `bin/`, ported to apt), their symlinks under `/usr/share/oaxaca/bin/`, the install tree `/usr/share/oaxaca/install/`, the `version` file, and the `fd` and `bat` names for Ubuntu's `fdfind` and `batcat` | `omarchy` |
| `oaxaca-shell` | `/usr/share/oaxaca/shell/` (the Quickshell shell) and the icon font `/usr/share/fonts/truetype/oaxaca/oaxaca.ttf`, its family kept as `omarchy`, the name menu entries and plugins give in `iconFont` and `fontFamily` | `omarchy` |
| `oaxaca-themes` | `/usr/share/oaxaca/themes/` and `/usr/share/oaxaca/default/themed/` | `omarchy` |
| `oaxaca-config` | `/usr/share/oaxaca/default/` and `/usr/share/oaxaca/config/`, `/etc/skel/` seeds (`.config`, `.bashrc`, launchers, toggles), `/etc/` drop-ins from the port's `etc/` (sudoers, sysctl, logind and the systemd manager, binfmt, NetworkManager, ssh, mise, `profile.d`, fastfetch, kitty, the SDDM theme setting) plus apt periodic and Chromium's flags, its tmpfiles and udev rules under `/usr/lib/`, the uwsm `env.d` file, `environment.d`, fontconfig, the systemd user units and their drop-ins (oomd, blueman, Mullvad), the sleep hook, the PAM profiles, the polkit rule, launchers and icons, the SDDM theme, the Wayland session file, the Plymouth theme files, branding | `omarchy-settings` |

## How the build works

`scripts/build.sh` reads the `upstream` file (`GIT=`, `REF=`) and makes the orig tarball with `git archive` from `santisbon/omarchy`; with `UPSTREAM_DIR=~/Projects/omarchy make build PKG=packages/desktop` it takes the local checkout instead, uncommitted changes included, which is how the port is developed before it is pushed. `debian/rules` then copies the tree to `debian/renamed/`, runs the port's `port/rename.sh` on that copy with `DISTRO_ID=oaxaca` and `DISTRO_NAME=Oaxaca`, writes the `version` file from the changelog, renders the branding placeholders, converts the application icons to the hicolor sizes, and `debian/install-tree.sh` lays the renamed copy out into the four package directories the way Omarchy's two recipes (`omacom/omarchy-pkgs`, `pkgbuilds/omarchy` and `pkgbuilds/omarchy-settings`) do. The metapackage's dependency list is the `port:Depends` substitution variable, filled from the package list in the renamed tree.

## Branding

Omarchy's name is a trademark and its logos are Omarchy's. The build replaces them with the distro's artwork, which `scripts/branding.py` (`make branding`) draws into `debian/extra/`: `logo.svg` and `logo.txt` (the name), `icon.png` and `icon.txt` (the mark), and `splash-logo.png`, which `debian/rules` copies in as the SDDM theme's and the Plymouth theme's logo. The theme wallpapers that carried Omarchy's mark are not installed. The icon font's glyph at `U+E900` (the menu shows it next to "Oaxaca" entries) is the distro's mark, from the `build/branding/mark.svg` that `scripts/branding.py` writes for `santisbon/omarchy`'s `omarchy-dev-font` (docs/6, choices 104 and 105).

## What is not here

The port's choices and drop list are in `docs/6 - omarchy-port.md`; the branch's own rules are in `santisbon/omarchy`'s `PORT.md`.
