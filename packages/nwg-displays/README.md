<!-- Generated from packages/nwg-displays/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# nwg-displays

nwg-displays 0.4.4, the display layout app for Oaxaca's "Setup, Monitors" menu entry: roadmap step 6. nwg-displays is a Python 3 program (GTK 3 through PyGObject, the `gtk-layer-shell` library for its overlay windows, and `i3ipc` to talk to the compositor's socket) that shows the connected monitors as boxes you drag around, and on Apply writes the layout, resolution, refresh rate, scale and transform of each monitor to a configuration file the compositor reads. Ubuntu's archive carries 0.3.28, which writes only Hyprland's old `monitors.conf` format; Hyprland 0.55 and newer, which Omarchy v4.0.4 builds on, read a Lua configuration, and nwg-displays writes that Lua file since 0.4.3. See `docs/0 - plan.md`, "System settings UI".

The package keeps the upstream name, as the policy says for third-party software we package from source, and the version `0.4.4-0oaxaca1`: a new upstream release on Debian's packaging, so the `-0oaxaca1` revision marks "not in Debian yet", sorts above the archive's `0.3.28-1`, and sorts below a future Debian `0.4.4-1`.

| Path | What |
|---|---|
| `debian/` | Debian's `nwg-displays` 0.3.28-1 packaging (Debian Python Team, uploader Maytham Alsudany), with our changelog entry and Maintainer |
| `upstream` | the upstream tarball's URL and SHA-256; `scripts/build.sh` downloads the tarball as the orig tarball and unpacks the tarball around `debian/` before `dpkg-source` |

Unlike the `oaxaca-*` packages, this directory holds no upstream source: `make build PKG=packages/nwg-displays` fetches the source into `build/`.

## What the package installs

| Path | What |
|---|---|
| `/usr/bin/nwg-displays` | the GUI; the entry point `nwg_displays.main:main` from upstream's `setup.py` |
| `/usr/bin/nwg-displays-apply` | a command that applies a saved profile without opening the GUI (`nwg_displays.scripts.apply_profile_json:main`) |
| `/usr/bin/nwg-displays-toggle-wallpapers` | a command that toggles the wallpapers a profile stores (`nwg_displays.scripts.toggle_profile_wallpapers:main`) |
| `/usr/lib/python3/dist-packages/nwg_displays/` | the Python module: `main.py`, `tools.py`, `profiles.py`, `settings_applier/`, `wallpaper_manager/`, `scripts/`, the Glade UI file and CSS under `resources/`, translations under `langs/` |
| `/usr/share/applications/nwg-displays.desktop`, `/usr/share/pixmaps/nwg-displays.svg` | the menu entry and its icon, from Debian's `debian/nwg-displays.install` |
| `/usr/share/doc/nwg-displays/README.md` | upstream's README, from Debian's `debian/nwg-displays.docs` |

## Where the packaging and the source come from

| Path in `packages/nwg-displays/` | Origin | Content |
|---|---|---|
| `debian/rules`, `copyright`, `nwg-displays.install`, `nwg-displays.docs`, `source/format`, `source/options`, `upstream/metadata`, `watch` | Debian's `nwg-displays` 0.3.28-1, fetched from `deb.debian.org` as `nwg-displays_0.3.28-1.debian.tar.xz` on 2026-10-10 (SHA-256 `3b79a6cf...7d52f31`, the one Debian's `.dsc` records) | unchanged. `rules` is `dh $@ --buildsystem=pybuild` with `PYBUILD_NAME=nwg-displays`: pybuild runs upstream's `setup.py` and dh-python fills `${python3:Depends}`. Debian's `gbp.conf` and `salsa-ci.yml` are not copied: those two files drive Debian's own workflow. Debian's empty `patches/` directory is not copied either |
| `debian/control.in` | Debian's `control` | our `Maintainer`, Debian's as `XSBC-Original-Maintainer` (Ubuntu's convention for a Debian package it changes); the `Vcs-*` fields that named Debian's git tree are dropped. Debian's `Uploaders`, Section, dependencies and Description stay as they are |
| `debian/changelog.in` | ours on top of Debian's history | the `0.4.4-0oaxaca1` entry with the reasons, then Debian's four entries |
| `upstream` | ours | `URL=` of GitHub's tarball for the release tag `v0.4.4` (published 2026-08-24, the newest release on 2026-10-10, checked with `gh api repos/nwg-piotr/nwg-displays/releases`) and `SHA256=` computed from the download on 2026-10-10. GitHub's tag tarball is the same source Debian uses: the `v0.3.28` tag tarball's SHA-256 equals the `nwg-displays_0.3.28.orig.tar.gz` checksum in Debian's `.dsc` (`35ffe993...fad26e9`) |
| `README.md.in` | ours | this summary |

## What was checked in the 0.4.4 source

Each fact names the file in the unpacked `v0.4.4` tarball and the line that proves the fact, as read on 2026-10-10.

- **Dependencies.** The set of modules the Python code imports is the same in 0.3.28 and 0.4.4 (`grep -rh '^import\|^from' nwg_displays/` on both trees, compared): `gi` with `Gtk` 3.0, `Gdk` 3.0 and `GtkLayerShell` 0.1 (`nwg_displays/main.py` lines 26, 28 and 39; `nwg_displays/tools.py` lines 12 and 13), `i3ipc`, and the standard library. `importlib_metadata` in `nwg_displays/__about__.py` line 4 is only the fallback when `importlib.metadata` is missing, and Python 3.14 has that module. Upstream's `setup.py` (line 24) declares `install_requires=[]`, so pybuild adds nothing. Debian's `Depends` (`gir1.2-gtk-3.0`, `gir1.2-gtklayershell-0.1`, `python3-gi`, `python3-i3ipc`, plus `${python3:Depends}`) therefore stays, and every name is in `stonking`: `python3-gi` 3.57.1-1, `gir1.2-gtk-3.0` 3.24.52-0ubuntu1, `gir1.2-gtklayershell-0.1` 0.10.1-1, `python3-i3ipc` 2.2.1-4 (all `universe` except `python3-gi` and `gir1.2-gtk-3.0` in `main`); the build dependency `dh-sequence-python3` is provided by `dh-python` 7.20260623 and `python3-setuptools` is 78.1.1-0.1build1. The `setup.py` diff between the two versions changes only `version=` and adds `scripts/*`, `settings_applier/*` and `wallpaper_manager/*` to `package_data`.
- **Lua output for Hyprland 0.55 and newer exists.** `nwg_displays/settings_applier/settings_applier.py`: the GUI's Apply path `_apply_hyprland_gui` builds one `hl.monitor({...})` block per monitor (line 520) and writes the list with `save_list_to_text_file(lines_lua, outputs_path_lua)` (line 539), next to the old-format `monitors.conf` lines (line 538); the profile loader `_apply_hyprland_json` does the same at lines 140 and 151. Workspace rules go to `hl.workspace_rule({...})` blocks in `nwg_displays/main.py` line 992. The 0.3.28 tree contains no Lua code at all (`grep -ri lua nwg_displays/` finds nothing), and upstream's release note for v0.4.3 says the version "generates `~/.config/hypr/monitors.lua` and `~/.config/hypr/workspaces.lua` for Hyprland v0.55.x". v0.4.4's release note adds Hyprland colour management (`cm`, `sdrbrightness`, `sdrsaturation`, `bitdepth`) and VRR (`vrr`) fields to the same blocks (`settings_applier.py` lines 488 to 507) and fixes monitor descriptions containing `#` in the Lua output.
- **Which file the Lua output goes to by default.** With no option, `-m/--monitors_path` defaults to `<config home>/hypr/monitors.conf` (`nwg_displays/main.py` lines 1149 to 1157; `hypr_config_dir` is `$XDG_CONFIG_HOME/hypr` or `~/.config/hypr`, `main.py` line 62 and `tools.py` lines 23 to 25). The Lua path is derived from the `-m` value: `outputs_path.removesuffix(".conf") + ".lua"` when the value ends in `.conf`, else the fixed string `"~/.config/hypr/monitors.lua"` (`settings_applier.py` lines 526 to 530 and 142 to 146). So the default writes `~/.config/hypr/monitors.conf` and `~/.config/hypr/monitors.lua`, the same file name Omarchy's hand-edited monitor file uses.
- **`-m/--monitors_path` exists and keeps Lua output at a custom path, with one rule.** The option is defined at `main.py` lines 1149 to 1157 and stored as `outputs_path` at line 1217. Because the Lua path is the `.conf` path with the suffix swapped (the lines above), `nwg-displays -m ~/.config/hypr/monitors-gui.conf` writes `monitors-gui.conf` and `monitors-gui.lua` in that directory. A value that does not end in `.conf`, such as the plan's `-m ~/.config/hypr/monitors-gui.lua`, sends the Lua output to the literal string `~/.config/hypr/monitors.lua`, and `save_list_to_text_file` (`tools.py` line 531) opens that string as given, with no tilde expansion, so the write fails. The menu entry must pass a `.conf` path and the Lua file to `require()` from Omarchy's `monitors.lua` is then `monitors-gui`.
- **Files Debian's `install` and `docs` name still exist.** `nwg-displays.desktop`, `nwg-displays.svg` and `README.md` sit at the top of the 0.4.4 tree. Upstream's own `install.sh` installs the same two files to `/usr/share/applications` and `/usr/share/pixmaps`.
- **The source tree carries three dangling symlinks** under `.direnv/` (`flake-profile`, `flake-profile-6-link`, `flake-profile-9-link`), left in the tag by upstream's Nix development shell; the 0.3.28 tarball Debian built from has the same three. They stay in the orig tarball and the build does not touch them.

## Version reasoning

The policy's "third-party we package from source" row gives `<upstream>-0oaxaca<N>`, so `0.4.4-0oaxaca1`. Rejected: the "rebuild from a Debian source package" form `0.3.28-1oaxaca1`, because Debian's source is 0.3.28 and the whole point is the newer upstream, and a native version `0.4.4`, which would hide that Debian's packaging is reused and would not sort below Debian's own `0.4.4-1` when Debian ships that release, at which point the plan says to backport Debian's package instead.
