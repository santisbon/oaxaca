<!-- Generated from README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# Oaxaca

Oaxaca is a Linux distribution: Ubuntu underneath, and on top the Omarchy desktop (Hyprland, a Quickshell bar and menus, Omarchy's themes and tools), ported from Arch Linux to Ubuntu's package manager. The first machine it is built for is a Lenovo Legion Pro 7 laptop with Intel and NVIDIA graphics, used with an Apple Studio Display, and it is meant to run on other PCs too: Omarchy's fixes for other laptops (ASUS, Apple, Framework, Lenovo and others) are applied at install on the machines they match.

## Built on Ubuntu

Oaxaca is Ubuntu 26.10 (`stonking`), installed from Ubuntu's own package archive: the same kernel, systemd, Mesa, drivers and security updates, managed with apt. Both app stores are ready out of the box: Ubuntu's snapd (the Snap Store) and Flatpak with Flathub. Nothing is installed and then stripped out; the system is assembled from Ubuntu's archive one package at a time, the desktop is built up the same way (Ubuntu's own configuration plus the parts of Omarchy the desktop needs, with each further Omarchy feature added for a recorded reason), and the few parts Ubuntu lacks (the desktop, its fonts, a handful of tools) come from Oaxaca's own apt repository at <https://oaxaca-apt.s3.us-east-1.amazonaws.com>. The installer is a live USB image running Calamares, a graphical installer from Ubuntu's archive (rebuilt with two fixes), and it installs onto an encrypted disk by default.

## Installing software: Recommends are on, with two exceptions

apt on Oaxaca installs a package's required dependencies (`Depends`) and the packages it recommends (`Recommends`), as on a stock Ubuntu, with two exceptions. `oaxaca-base` ships apt pins in `/etc/apt/preferences.d/oaxaca-blocked-recommends` (an apt preferences file: one stanza per package, `Pin-Priority: -1` meaning "never install") that keep out:

- `xdg-desktop-portal-gnome`: Files recommends it, and it recommends `gnome-shell`, which would bring GNOME Shell, `gdm3` (a second login screen next to SDDM), the Ubuntu GNOME session and IBus.
- `sudo-rs`: `sudo` recommends it, and it would take over the `sudo` command from classic sudo, whose sudoers rules Oaxaca's menus use.

To allow one of them, delete its stanza from that file (dpkg asks about the edit when a new `oaxaca-base` changes the file). To install a single package without its Recommends:

```sh
sudo apt install --no-install-recommends <package>
```

Oaxaca systems installed before `oaxaca-base` 0.1.6 were built with Recommends off. Updating removes that setting, but apt does not go back and add the Recommends it skipped; this command does, once (`--solver internal` selects apt's classic solver: with apt 3.3's default solver, `--fix-policy` added nothing when tried on 2026-10-14):

```sh
sudo apt-get --solver internal --fix-policy install
```

## Secure Boot

Oaxaca boots with Secure Boot on or off and never asks the user to enroll a key. Both the live USB and the installed system boot through Ubuntu's own signed chain: shim (signed by Microsoft, so the firmware trusts it) loads Canonical's signed GRUB and kernel. Secure Boot is supported, never required: Oaxaca does not check or change the firmware setting.

## NVIDIA and AMD GPUs

The installer detects an NVIDIA GPU and installs NVIDIA's open driver from the newest branch that has Canonical's prebuilt, signed kernel modules. Because Canonical signed the modules, the driver loads under Secure Boot without a key of your own, and because the driver packages ship on the USB image, the installation needs no network. AMD GPUs need nothing installed: they run on the `amdgpu` driver in Ubuntu's signed kernel and on Mesa, both already in the system.

On laptops with hybrid graphics, where the built-in screen hangs off the Intel or AMD GPU and a discrete NVIDIA or AMD GPU sits beside it, the desktop renders on the display GPU and applications default to it, so the discrete GPU is left alone until something asks for it:

- the app menu starts a program on the discrete GPU when its desktop entry asks for one (Steam's does), or when its id is listed in `~/.config/oaxaca/dgpu-apps` (a line `-<id>` keeps a program on the display GPU);
- `oaxaca-launch-dgpu <command>` runs one program on the discrete GPU (in Steam: `oaxaca-launch-dgpu %command%`): through NVIDIA's PRIME render offload on NVIDIA, through Mesa's `DRI_PRIME` on AMD;
- CUDA programs use an NVIDIA GPU directly, with no launcher.

The AMD path is tested against simulated machines only, not yet on AMD hardware.

## Apple Studio Display

The display's brightness has no standard control on Linux: the Studio Display takes brightness commands over its USB connection. Oaxaca packages `asdcontrol`, the program that sends them (Ubuntu's archive does not have it), and the desktop's brightness keys and controls use it for the display, as Omarchy does on Arch. Ubuntu's `bolt` handles Thunderbolt device authorization for the display's Thunderbolt connection.

## The Omarchy desktop

[Omarchy](https://github.com/omacom/omarchy) is a Linux distribution: Arch Linux's base (kernel, pacman, boot loader, snapshots) with Omarchy's own layer on top, shipped as two Arch packages (the commands, the Quickshell shell, the themes, and the settings, units and starter files a new user gets) plus a package list and setup scripts that tune the Arch base. Oaxaca takes only that layer and puts Ubuntu underneath instead of Arch. It carries a fork of Omarchy v4.0.4 (<https://github.com/santisbon/omarchy>, branch `oaxaca`) in which pacman and the AUR are replaced by apt (and, for the few applications Ubuntu does not ship as regular packages, the Snap Store or Flathub), the scripts that configured Arch's base are dropped in favor of Ubuntu's own configuration, and the package list is translated to Ubuntu's names. The build turns that fork into Debian packages, renamed at build time: `oaxaca-desktop` (the metapackage that pulls in Hyprland, the applications and the rest), `oaxaca-shell`, `oaxaca-themes`, `oaxaca-tools` and `oaxaca-config`. Hyprland comes from Ubuntu's archive; Quickshell, which Ubuntu does not carry, is built for Oaxaca's repository. Updates arrive through apt like the rest of the system.

## Plugins and themes written for Omarchy

Oaxaca runs the plugins in Omarchy's plugin marketplace (<https://plugins.omarchy.org>) and the themes on Omarchy's theme list (<https://omarchy.org/themes/>). A plugin is a git repository of code that runs inside the desktop's shell (the bar, its panels, the menu); a theme is a git repository of colors, wallpapers and per-application settings. Add a plugin with Menu > Setup > Plugins > Add Plugin (or `oaxaca plugin add <git URL>`), and a theme with Menu > Install > Style > Theme (or `oaxaca theme install <git URL>`).

Plugins and themes are written for Omarchy, so they call Omarchy's names. Oaxaca answers to those names through a compatibility layer, while everything you see says Oaxaca:

- every `oaxaca-<name>` command also answers to `omarchy-<name>`, the `oaxaca` command to `omarchy`, and `/usr/share/oaxaca` to `/usr/share/omarchy`; your `~/.config/omarchy`, `~/.local/state/omarchy` and `~/.local/share/omarchy` are links to Oaxaca's folders. These are links: the commands the menu and the key bindings run are the `oaxaca-*` ones, and the `oaxaca` command introduces itself as Oaxaca's even when called as `omarchy`;
- names you do not see keep Omarchy's spelling: the built-in plugins' IDs (`omarchy.clock`, `omarchy.weather`), `OMARCHY_*` environment variables, and app IDs such as `org.omarchy.terminal`.

Omarchy runs on Arch Linux and Oaxaca on Ubuntu, so a plugin or theme that installs software the Arch way needs more than names. Three things handle that:

- **A warning when you add one.** Before keeping a plugin or theme, Oaxaca looks through its files for Arch's package tools (`pacman`, `yay`, `paru`, `makepkg`, Omarchy's AUR commands) and pacman's files, shows up to 10 lines where they appear, and asks "Add it anyway?" with No as the default. A match is a hint: the words also appear in comments and messages, and such a plugin may work fine.
- **Stand-ins for Arch's package tools.** `/usr/lib/oaxaca/arch-standins/` holds `pacman`, `yay`, `paru` and `makepkg`, all running `oaxaca-arch-standin`, and that folder comes last on your `PATH`, so a real program of the same name wins if you install one (Ubuntu's `pacman-package-manager` has a real `pacman`). A query such as `pacman -Q zip` answers "not installed" without a word, so a plugin that only checks takes its "missing" path. Anything else, such as `yay -S xray`, changes nothing: it prints the command that ran, says that Oaxaca installs software with apt, shows a desktop notification, and exits with status 1. Omarchy's AUR commands (`omarchy-pkg-aur-add`, `-install`, `-accessible`) do the same, and the last one answers that the AUR is not available.
- **Package-name translations.** Omarchy's own package command, `omarchy-pkg-add <names>` (here `oaxaca-pkg-add`), installs with apt on Oaxaca, and so do the checks `omarchy-pkg-present` and `omarchy-pkg-missing`. When a plugin gives them an Arch package name that Ubuntu does not use, they look it up in a translation table and use the Ubuntu packages listed there; `python-<name>` becomes `python3-<name>` when Ubuntu has that; any other name is used as it is.

The translation table is a plain text file, one Arch name per line followed by its Ubuntu packages, lines starting with `#` ignored:

- on an installed system: `/usr/share/oaxaca/default/oaxaca/arch-package-names`;
- in the source: `default/omarchy/arch-package-names` in the Omarchy fork (<https://github.com/santisbon/omarchy>, branch `oaxaca`).

Lines from that file:

```
bluez-obex bluez-obexd
github-cli gh
qt6-declarative qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtqml-workerscript qml6-module-qtquick-templates
ttf-jetbrains-mono-nerd oaxaca-fonts
```

The table has 162 entries (2026-10-17), drawn from every package name that the 5602 plugins listed in Omarchy's marketplace ask for in their code, build files and messages (5575 of them could be fetched; 881 name a package), plus the Arch packages Omarchy itself installs. Each Ubuntu package was chosen by the files both distributions install (commands, libraries, Python modules), checked by hand, and is in Ubuntu 26.10's archive or Oaxaca's own repository. An Arch name that is also an Ubuntu package name is never in the table, so the table cannot change what an Ubuntu name installs. Names with no entry are installed as they are, and apt says so when Ubuntu has no such package: software Ubuntu does not package (such as `ruff`, `croc`, `himalaya` or `spotifyd`), AUR-only packages, and vendors' own packages (Chrome, VS Code, 1Password, Spotify, Signal, Tailscale, Mullvad), which come from the vendors' repositories through the menu's Install > Browser, Editor and Service entries instead. To add a translation, edit the file in the fork and open a pull request against `oaxaca`; on your own machine you can also edit the installed copy, which the next update of `oaxaca-config` replaces.

What no layer reaches: plugins that need software Ubuntu does not package (for example `xray`, which is only in Arch's user repository, the AUR), features built on pacman's own files (a widget that watches pacman's log stays idle), and commands Omarchy added after the version Oaxaca carries (v4.0.4). The reasoning, and the sample of marketplace plugins it was measured on, is choice 86 in [docs/6 - omarchy-port.md](docs/6%20-%20omarchy-port.md).

## More

- [docs/README.md](docs/README.md): the developer README. How the distro is built from source, the tools and their commands, the repository map and the status of each roadmap step.
- [docs/0 - plan.md](docs/0%20-%20plan.md): the plan and the reasoning behind the choices above.
- [docs/7 - image-installer.md](docs/7%20-%20image-installer.md): the live USB image and the installer, including the NVIDIA and hybrid-graphics decisions.
