# Audit of what the port removed from Omarchy

Written 2026-10-16, after three removals turned out to be wrong: the agent skills (deleted as Omarchy's contributing workflow, though seven of their nine files are help for users), the update snapshots (deleted with Limine, though only the boot menu needed Limine), and the launcher's handling of desktop ids that end in `.desktop`. This document lists everything the port removed from Omarchy v4.0.4, why, whether the reason holds, and what to restore. Nothing here has been restored yet: the [restore list](#restore-list) is for the distro's maintainer to choose from.

## Terms

Each entry uses only terms defined above it.

### Omarchy and the port

Omarchy is the Arch Linux desktop this distro follows, at its release tag `v4.0.4`. The port is the fork's branch `oaxaca` (`~/Projects/omarchy`, `github.com/santisbon/omarchy`), which rewrites Omarchy for Ubuntu and is packaged by this repository (`packages/desktop`).

### stonking

Ubuntu 26.10, the base series. "In stonking" means Launchpad lists the package as published for that series, checked 2026-10-16.

### Choice

A numbered decision in one of this repository's step documents, such as "docs/6, choice 15" in `docs/6 - omarchy-port.md`.

### Verdicts

- **Justified**: the reason for removing the feature holds.
- **Replaced**: the distro does the same job another way, named in the row.
- **Restore**: the reason does not hold, and the feature works on Ubuntu within the project's requirements (Secure Boot without a MOK, Ubuntu's signed GRUB and kernel, packages from Ubuntu's archive, vendor apt repositories, the Snap Store or Flathub).
- **Partial**: part of the feature can come back, or it can come back another way.
- **Unclear**: the facts needed were not reachable.

## How the audit was done

The deleted files are `git diff --name-status --diff-filter=D v4.0.4 oaxaca` in the fork: 321 files. The 106 migrations and 32 tests among them are covered elsewhere (the fork's `migrations/README.md` and `PORT.md`, "Tests"). The rest, 183 files, plus the 70 menu entries removed from `default/omarchy/omarchy-menu.jsonc`, the 97 package names that Omarchy's `install/omarchy-base.packages` has and the port's does not, and the features cut inside the 121 files both sides have, were read one by one against the reasons recorded in this repository's docs and the fork, and checked against stonking on Launchpad, the Snap Store (`snap info`), Flathub, vendor apt repositories, mainline Linux 7.3 and the live root filesystem built 2026-10-16.

## What the audit found overall

- **No commit says why anything was removed.** The commits that deleted the files, `ef4c9211` "Port Omarchy v4.0.4 to Ubuntu", `c304e943` "Trim pre-installed software", `4b680c26` "Remove features we provide through Ubuntu", `3c21fd64` "Don't customize firewall" and `963b196e`, have no message body. Every recorded reason is in docs/6, docs/1, docs/0, the fork's `PORT.md` or the comments in the port's package list.
- **The preinstall trim rests on one choice.** docs/6 choice 15 ("nothing of Omarchy's taste") dropped Omarchy's command-line tools and preinstalled apps; neither the plan nor the policy has a rule about what to preinstall. Some of what went is basic (no `unzip`, no calculator, no system monitor), and some is still wired into the port's own files (the prompt, the `ls` and `cd` aliases, the debug report).
- **Removals were coupled to Limine and Snapper wholesale.** Snapshots, the factory reset and two ASUS display fixes went because Omarchy delivered them through Limine or Snapper, though the feature itself works with GRUB and Timeshift.
- **Reasons that expired were not revisited.** Voxtype's invitation went when Voxtype could not be installed and stayed gone after it could; Brave and Edge went as "proprietary builds replaced by open counterparts" and stayed gone after Chrome and VS Code came back; the `ic`/`ix`/`icx` aliases stayed gone after tmux came back.
- **Some "Ubuntu's configuration" removals dropped a reason specific to this desktop.** docs/6's rule follows Ubuntu's settings unless a reason is specific to this desktop; Wi-Fi power save (link drops on Intel BE200 firmware, the Legion's card), the SSH keepalive (needed by the kept `ssh-reconnect`) and the out-of-memory killer's scope (keeps the compositor out) had such reasons.
- **The rule "Delete rather than stub" was not followed through.** Scripts were kept with nothing calling them, and kept scripts call deleted programs (section [Broken references](#broken-references-and-leftovers)).

## Restore list

Ranked by what a user meets first. Each item names its section below.

**1. Broken or weaker than Omarchy today**

1. Firewall: ufw ships off (`ENABLED=no`), so nothing filters inbound traffic, and Setup > Security > SSH's `ufw limit 22/tcp` does nothing. Turn ufw on with deny incoming and LocalSend's port 53317, without Omarchy's Docker rules. ([System files](#system-install-and-hardware-files))
2. Wi-Fi power save: Ubuntu's `wifi.powersave = 3` is back on; Omarchy turned it off for link drops on Intel BE200/BE211 firmware, the Legion's card. ([System files](#system-install-and-hardware-files))
3. Broken references: the screensaver never runs (no `ttfx`); the clipboard's open action and imv's Ctrl+E call `tensaku-edit`, which does not exist (point both at swappy); the Symfony branch of `omarchy-install-dev-env` fails; the debug report has no hardware section (no `inxi`); the prompt, `ls` and `cd` aliases are dormant (no starship, eza, zoxide); the agent skill points at deleted config files. ([Broken references](#broken-references-and-leftovers))
4. Hyprland's reload guard ships but nothing pauses it during an upgrade; wire it into the config package's preinst and postinst. ([System files](#system-install-and-hardware-files))
5. The out-of-memory killer can pick the compositor: Ubuntu's policy is on `user@.service`, the case Omarchy's `app.slice` drop-in avoided. ([System files](#system-install-and-hardware-files))
6. SSH keepalive, which the kept `ssh-reconnect` needs. ([Kept files](#features-cut-inside-files-the-port-kept))
7. Basic tools: `unzip`, a calculator (gnome-calculator, with the Calculator key), a system monitor (btop, with Super+Ctrl+T and theme sync), and Disks (`gnome-disk-utility`, today only Suggested, so never installed). ([Packages](#packages-dropped-from-the-base-list-and-their-configurations))

**2. Cheap restores**

Share > Receive and Chromium's Google account (one menu line each; [Commands](#commands-launchers-and-menu-entries)); the `ic`/`ix`/`icx` aliases, the Voxtype invitation, 1Password's Chromium extension, the fingerprint lid-closed gate and DNS for networks joined later ([Kept files](#features-cut-inside-files-the-port-kept)); the ASUS Panther Lake display fixes, Intel Quick Sync and i965 video drivers, BCM4331 Wi-Fi firmware and the inotify limit ([System files](#system-install-and-hardware-files)); `inxi` and `whois` ([Packages](#packages-dropped-from-the-base-list-and-their-configurations)).

**3. Omarchy's defaults dropped by choice 15**

starship, zoxide, eza, lazygit and dua-cli with their configurations; mise from its vendor apt repository; Docker with sudoless Docker and the database installer; the preinstalled apps (Xournal++, OBS Studio, Kdenlive, Pinta and Moonlight from Flathub, LibreOffice and Obsidian from their vendors' snaps); Omarchy's LazyVim configuration through `/etc/skel`. ([Packages](#packages-dropped-from-the-base-list-and-their-configurations), [Commands](#commands-launchers-and-menu-entries))

**4. Menu installers that work on Ubuntu**

Brave, Edge and Zen; Helix, Cursor and Zed; Symfony; the six Nerd Fonts, built from the release zip `oaxaca-fonts` already uses; OpenClaw through mise; Heroic, NordVPN, Bitwarden, Sunshine and Minecraft. ([Commands](#commands-launchers-and-menu-entries))

**5. Larger projects**

A factory reset on Timeshift and `oem-config`; Omarchy's own MIT-licensed apps (ttfx, herdr, cliamp, omawrite, omacut, omacalc, try) built in the distro's apt repository as LocalSend is; the Windows VM after Docker; an NVIDIA-only GPU toggle through `prime-select`; Dell XPS touchpad haptics; Learn > Omarchy with a caveat.


## Commands, launchers and menu entries

85 deleted files under `bin/` and `applications/` and 70 removed menu entries, grouped by feature. The commits that deleted them, `ef4c9211` (47 files), `c304e943` (37) and `963b196e` (the HEY handler), give no reason per item; the reasons are from docs/6, docs/1, docs/0 and the fork's `PORT.md`.

### Restore or partly restore

| Feature | Files and menu entries | What it did | Removed because | Checked facts | Verdict |
|---|---|---|---|---|---|
| Share > Receive | `trigger.share.receive` | opened LocalSend to receive files | none recorded; removed when LocalSend was not packaged yet | LocalSend is preinstalled since `8a7a6b3a`; Share > File, Folder and Clipboard already use it | **Restore**: one menu line |
| Chromium's Google account | `install.service.chromium-account` | adds Google's OAuth client to `~/.config/chromium-flags.conf` so Chromium can sign in and sync | none recorded | `bin/omarchy-install-chromium-google-account` is still in the fork and `omarchy-refresh-chromium` calls it; Chromium reads that file since `/etc/chromium.d/zz-oaxaca-user-flags` | **Restore**: one menu line |
| Docker: sudoless Docker, Docker databases, Docker TUI | `bin/omarchy-sudo-docker`, `-setup-security-sudoless-docker`, `-remove-security-sudoless-docker`, `-install-docker-dbs`, `-launch-docker-tui`, `applications/Docker.desktop`; `install.development.docker-dbs`, `setup.security.sudoless-docker`, `remove.security.sudoless-docker` | Omarchy preinstalls Docker, keeps the user out of the root-equivalent `docker` group behind an opt-in, and offers one-click MySQL, Postgres, Redis, MongoDB, MariaDB and MSSQL containers | `PORT.md`: they "run on Docker, whose setup the port removed"; docs/6, "Core and apps" | `docker.io` 29.7.2 is in main, `docker-compose-v2` and `docker-buildx` in universe; the scripts only use `docker run` and `usermod`; the reason is circular | **Restore** after an Install > Development > Docker entry; the TUI (lazydocker, not in stonking) is **partial** |
| Factory reset | `bin/omarchy-system-factory-reset`, `-factory-reset-finish`, `-provision-owner`; `setup.reset` | on btrfs, swapped `@` for the installer's factory snapshot, re-keyed the disk encryption and recreated the owner at first boot | docs/6: among "programs the distro cannot install"; docs/1: scripts tied to Limine and Snapper | the same mistake as snapshots: only the Limine and mkinitcpio steps were Arch-specific; btrfs installs have Timeshift; `oem-config` (universe) creates a user at first boot | **Partial**: a factory Timeshift snapshot at install, restored by the reset, then `oem-config-prepare`; the re-keying needs rewriting |
| Brave, Edge | `install.browser.brave`, `.edge`, and their remove and default-browser entries | regular Brave and Microsoft Edge | docs/6: Chrome, Edge and VS Code replaced by open counterparts | Chrome and VS Code are back in the menu, so the rule no longer holds; Brave's repository (already added for Brave Origin) has `brave-browser`; `packages.microsoft.com/repos/edge` has `microsoft-edge-stable` | **Restore** through `omarchy-pkg-repo-add` |
| Zen | `install.browser.zen` and its remove and default entries | Firefox-based browser | `PORT.md` only notes Omarchy offers it | Flathub `app.zen_browser.zen` (verified); no apt repository or snap | **Partial**: from Flathub |
| Nerd Font installers | `install.style.font` with Bitstream, Cascadia, Fira, Iosevka, Meslo, Victor | install a patched Nerd Font and switch to it | docs/6: "the Nerd Font installers" | the `ttf-*-nerd` names are Arch's; `oaxaca-fonts` already builds JetBrains Mono from the Nerd Fonts release zip; `bin/omarchy-install-font` stayed, unused, with Arch names | **Restore**: build the six from the same zip |
| Helix | `bin/omarchy-install-editor-helix`; `install.editor.helix` | Helix linked to the theme | `PORT.md`: Install > Package, without Omarchy's setup | `hx` in universe; the fork still has `helix.toml.tpl` and `omarchy-restart-helix` | **Restore** |
| Cursor | `install.editor.cursor` | Cursor editor | none recorded | Cursor's apt repository (`downloads.cursor.com/aptrepo`) has `cursor`; its signing key URL not verified | **Restore** through `omarchy-pkg-repo-add` |
| Zed | `bin/omarchy-install-editor-zed`; `install.editor.zed` | Zed themed by Omarchy's `omazed` | `PORT.md` | Ubuntu's `zed` is another program; Flathub `dev.zed.Zed` (unverified); `omazed` is nowhere | **Partial**: Flathub, no theme sync |
| Symfony | `install.development.php.symfony`, `remove.development.php.symfony` | PHP with `symfony-cli` | none recorded | the `symfony)` branch left in `omarchy-install-dev-env` installs a package stonking does not have, so it fails; Symfony's Cloudsmith repository has `symfony-cli` 5.22.1 | **Restore** with the vendor repository |
| btop and Obsidian theme sync | `bin/omarchy-restart-btop`, `-theme-set-obsidian` | reload btop's colors; copy the theme's `obsidian.css` into every vault | `c304e943` (the apps were no longer preinstalled) | the themes still render `btop.theme` and `obsidian.css` | **Restore** with the apps |
| OpenClaw | `bin/omarchy-install-ai-openclaw`, `-remove-ai-openclaw`, `-install-openclaw-cli`; `install.ai.openclaw`, `remove.ai.openclaw`, `setup.default.agent.openclaw`, `remove.ai` | the OpenClaw agent, its gateway and Control UI, and the default-agent choice | `PORT.md`: the snap is a third party's | Omarchy's package is the npm module; npm has `openclaw` 2026.10.4 from the project; the port installs other npm agents through mise; `omarchy-launch-openclaw` and `-openclaw-onboard` were kept | **Restore** through `mise use -g npm:openclaw` |
| Heroic, Minecraft | `bin/omarchy-install-gaming-heroic`, `-remove-gaming-heroic`, `-remove-gaming-minecraft`; their menu entries | game launchers | `PORT.md`: Install > Flatpak | Flathub `com.heroicgameslauncher.hgl` (verified), `com.mojang.Minecraft` (unverified) | **Restore** Heroic as a Flathub entry; Minecraft **partial** |
| NordVPN, Bitwarden | `bin/omarchy-install-service-nordvpn`; `install.service.nordvpn`, `install.service.bitwarden` | VPN client; password manager | `PORT.md`: Install > Snap | NordVPN's apt repository answers and its snap is the vendor's; Bitwarden's snap and Flatpak are verified | **Restore** (NordVPN like Mullvad; Bitwarden like Thunderbird) |
| Sunshine | `bin/omarchy-install-service-sunshine`, `-remove-service-sunshine` | game-streaming host | `PORT.md`: Flathub | Flathub `dev.lizardbyte.app.Sunshine` (verified) | **Partial** |
| Windows VM | `bin/omarchy-windows-vm`; `install.windows`, `remove.windows` | Windows in the `dockurr/windows` container over RDP | `PORT.md`: runs on Docker | needs Docker, `freerdp3-x11` (universe), `netcat-openbsd`; the image is from Docker Hub, not one of the project's package sources | **Partial**, after Docker, if a Docker Hub image is acceptable |
| Hybrid-GPU toggle | `bin/omarchy-hw-hybrid-gpu`, `-toggle-hybrid-gpu`; `trigger.hardware.hybrid-gpu` | ASUS-only GPU modes through supergfxd | docs/6 | `supergfxctl` is not in stonking; `nvidia-prime` (main) has `prime-select intel` / `on-demand` | **Partial**: an NVIDIA-only toggle |
| Dell XPS touchpad haptics | `trigger.hardware.touchpad-haptics` with High, Mid, Low | haptic strength on XPS Synaptics touchpads | none recorded | the tool is MIT in `omacom-io/omarchy-pkgs` (a script, a udev rule, a service); `omarchy-hw-dell-xps-haptic-touchpad` was kept | **Restore** (niche): package it like `oaxaca-hw-legion` |
| Learn > Omarchy | `learn.omarchy` | Omarchy's manual | none recorded | parts of the manual do not apply (firewall, pacman, Limine), most does | **Partial**: with a caveat, or a page of the port's own |
| Disk Usage | `applications/Disk Usage.desktop` and icon | `dua i /` in a terminal | docs/6 | `dua-cli` in universe | **Partial** (with the package, section "Packages") |

### Replaced

the AUR commands (Install > Package, Snap and Flatpak); pacman upkeep (`omarchy-update-system-pkgs` with apt); the 32-bit GPU libraries (`omarchy-install-32bit-graphics`); the local package test (`UPSTREAM_DIR=… scripts/build.sh`); Learn > Arch (Learn > Ubuntu); the preinstalled web-app launchers and HEY's mailto handler (Install > Web App; Omarchy's set could come back as presets); LM Studio (Install > Flatpak).

### Justified

Battle.net (umu-launcher not in stonking); ONCE (a GitHub binary, needs Docker); ChatGPT desktop, Grok Bot, Hermes Desktop, Perplexity (only third parties' snaps or nothing; web apps and the agents cover them); T3 Code (a GitHub release only); hibernation (out of the first release; docs/0 and docs/1 give different reasons, Secure Boot lockdown versus scope); direct boot of a UKI and Limine's refresh (GRUB only); package channels (the apt repository has none); upgrade to Quattro (Omarchy's own migration path); log upload and the Omarchy Discord (Omarchy's services); Learn > Herdr (Herdr is not available); the preinstalls toggle (nothing removable is preinstalled).

## System, install and hardware files

The 92 files deleted under `install/`, `etc/` and `default/` went in four port commits, none of whose messages gives a reason: `ef4c9211` "Port Omarchy v4.0.4 to Ubuntu" (60 files), `4b680c26` "Remove features we provide through Ubuntu" (29), `c304e943` "Trim pre-installed software" (2), `3c21fd64` "Don't customize firewall" (1). The reasons below are from docs/6, docs/1, docs/4 and the fork's `PORT.md`. Facts were read from the live root filesystem tarball built 2026-10-16 (kernel 7.3.0-9), stonking's packages on Launchpad, and mainline Linux 7.3-rc7.

### Restore or partly restore

| Feature | Files | What it did | Removed because | Checked facts | Verdict |
|---|---|---|---|---|---|
| Wi-Fi power save off | `etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf` | `wifi.powersave = 2` | docs/6: Ubuntu's configuration | Omarchy's commit `da157fb9`: power save causes "20-300ms latency spikes" and "outright link drops on Intel BE200/BE211 firmware"; the Legion has a BE200; the image ships `default-wifi-powersave-on.conf` (`wifi.powersave = 3`) | **Restore**: a hardware reason, not taste |
| ASUS Panther Lake display fixes | `install/hardware/asus/fix-asus-ptl-b9406-display.sh`, `fix-asus-ptl-display-backlight.sh` | ExpertBook B9406: `xe.enable_panel_replay=0` (the panel froze on the last frame); B9406 and Zenbook UX5406AA: `xe.enable_dpcd_backlight=1` (brightness was on or off only) | docs/6: they wrote Limine drop-ins | the image's `xe.ko` has both parameters; mainline has no ASUS quirk for them; the DMI checks `omarchy-hw-asus-expertbook-b9406` and `-zenbook-ux5406aa` are still on the branch | **Restore** as `/etc/modprobe.d` options (or `/etc/default/grub.d`) on a DMI match |
| Firewall | `install/config/firewall.sh` | ufw on: deny incoming, allow outgoing, allow LocalSend (53317 tcp/udp) | docs/6 choice 13 (ufw as Ubuntu ships it) | the image's `/etc/ufw/ufw.conf` has `ENABLED=no`: nothing filters inbound traffic; `omarchy-setup-security-sshd` adds `ufw limit 22/tcp`, which does nothing while ufw is off; LocalSend is preinstalled | **Partial**: enable ufw with deny incoming and LocalSend's port (without the Docker rules), or have the SSH setup enable ufw and say so |
| Hyprland reload guard around upgrades | `default/libalpm/hooks/10-omarchy-hyprland-reload-pause.hook`, `90-…-resume.hook` | paused Hyprland's automatic config reload while the config package was being upgraded | docs/6: libalpm hooks gone | `oaxaca-hyprland-reload-guard` ships and `omarchy-hyprland-monitor-watch` asks it whether it is paused, but nothing pauses it; dpkg unpacks Hyprland's defaults under a running session | **Restore** in the config package's preinst and postinst |
| SSH keepalive | `install/config/ssh-keepalive.sh` | `ServerAliveInterval 15`, `ServerAliveCountMax 3`, `ConnectTimeout 10` | docs/6: `ssh_config.d` ships empty | the kept `ssh-reconnect` wrapper needs it | **Restore** |
| systemd-oomd scope | `default/systemd/user/app.slice.d/10-oomd.conf`, `etc/systemd/oomd.conf.d/10-omarchy.conf` | made the user's apps (`app.slice`) the kill candidates under memory pressure, never the compositor | docs/6: Ubuntu's three files | Ubuntu's `user@.service.d/10-oomd-user-service-defaults.conf` sets the kill policy on `user@.service`, the case Omarchy's comment warns "would put the compositor back in the candidate pool"; the thresholds match | **Partial**: restore the `app.slice` drop-in and set `ManagedOOMMemoryPressure=auto` on `user@.service` |
| Intel video acceleration | `install/hardware/intel/video-acceleration.sh` | Quick Sync runtime and the i965 driver for older Intel | no specific reason | `intel-media-va-driver-non-free` and `libvpl2` are in the image; `libmfx-gen1.2` (QSV encode) and `i965-va-driver` are not (both universe) | **Partial**: add both |
| Broadcom BCM4331 Wi-Fi | `install/hardware/fix-bcm43xx.sh` | `broadcom-wl-dkms` for BCM4360 and BCM4331 | docs/6: DKMS | BCM4360 needs DKMS (a MOK); BCM4331 works with the in-kernel `b43` and `firmware-b43-installer` (main) | **Partial**: firmware for BCM4331 on a PCI match |
| inotify watch limit | `etc/sysctl.d/90-omarchy-file-watchers.conf` | `fs.inotify.max_user_watches=524288` | docs/6: Ubuntu's value | the kernel sizes the limit from RAM (1%, up to 1048576); localsearch's `30-localsearch.conf` forces 65536, which lowers it on any machine above about 8 GB | **Restore** (low) |
| `tcp_mtu_probing=1` | `etc/sysctl.d/99-omarchy-sysctl.conf` | fixes stalled SSH and HTTPS over broken path-MTU networks | docs/6 grouped the whole file under zram | unrelated to zram | **Partial** (low) |
| PATH for `ssh host command` | `install/config/ssh-command-path.sh` | mise shims and `~/.local/bin` for non-interactive SSH commands | docs/6: Omarchy's line lacked `/usr/sbin`; `/etc/profile.d` covers login shells | `ssh host cmd` is not a login shell | **Partial** (low): with Ubuntu's full PATH |
| Wireless regulatory domain | `install/hardware/set-wireless-regdom.sh` | country code from the timezone | no reason recorded | the script writes an Arch file; Ubuntu sets no country | **Partial** (low): `options cfg80211 ieee80211_regdom=XX` |
| Voxtype first-run invitation | `install/user/first-run/install-voxtype.hook` | one-time "Install Dictation" notification | removed when Voxtype was AUR-only | Voxtype is in the distro's apt repository since choice 30 | **Restore** (optional) |
| Dell XPS haptic touchpad | `install/hardware/dell-xps-touchpad-haptics.sh` | installed Omarchy's `dell-xps-touchpad-haptics` | docs/6: Arch-only package | the package's source was not reachable | **Unclear** |

### Replaced

mkinitcpio files (initramfs-tools, `oaxaca-nvidia`'s hook, `oaxaca-base`'s Thunderbolt option); Snapper (Timeshift, choice 38); SDDM's Wayland greeter (`oaxaca-session`); the passwordless keyring (keyring unlocked by the login password, docs/4 choice 14); Plymouth's theme file (the distro's plymouth package); `nsswitch.conf` (Ubuntu's, with mDNS); the DNS and timezone sudoers rules (`omarchy-dns` on nmcli; `omarchy-timezone`); the icon links and Chromium first-run preferences; the Bluetooth pairing agent (blueman's applet; to confirm it runs under the session); CUPS hardening (Ubuntu's `cups-browsed` runs as its own user, browses only DNS-SD and has an AppArmor profile; `CreateRemoteCUPSPrinterQueues No` is the one setting missing); the MacBook SPI and Surface keyboards (in-kernel modules that initramfs-tools already adds); Motorcomm YT6801 Ethernet (in-kernel `dwmac-motorcomm`); NVIDIA (`oaxaca-drivers-install`); Vulkan drivers (`mesa-vulkan-drivers`).

### Justified

pacman's update guard, configuration and mirrors; Limine (docs/1 section 6); Battle.net (umu-launcher not in stonking); ASUS ROG tools and their GPU sleep hooks (asusctl and supergfxctl not in stonking; hibernation is out); shutdown timeouts and open-file limits (taste; Ubuntu's user manager already stops in 5 s); plocate tuning; zram and zswap; Docker's daemon setup (Docker is not preinstalled); resolved's multicast setting (a no-op); dirmngr keyservers; faillock (Ubuntu's stack has no `pam_faillock`); sudo's password tries; the powerprofilesctl shebang (Ubuntu's is already `/usr/bin/python3`); Omarchy's ISO provisioning and factory reset (Calamares installs; the reset relied on Limine and mkinitcpio); Apple T2 (needs a custom kernel); Apple-style F-keys for every keyboard (taste); TUXEDO and Slimbook backlight (DKMS only, so a MOK); Framework 16's qmk_hid (not in stonking; its udev rule stays); Intel FRED (`fred=on` is already the default in 7.3); Intel IPU7 camera (no sensor module or HAL within the requirements; worth stating as unsupported); network cleanup (archinstall leftovers).

## Packages dropped from the base list, and their configurations

Omarchy's `install/omarchy-base.packages` (v4.0.4) names 97 packages that the port's list does not. The port's commits that removed them, `ef4c9211` ("Port Omarchy v4.0.4 to Ubuntu") and `c304e943` ("Trim pre-installed software"), have empty message bodies; the recorded reasons are the comments in the port's package list (lines 174 to 212) and docs/6, "Core and apps" and choice 15 ("nothing of Omarchy's taste"). Neither the plan nor the policy has a rule about what to preinstall, so the trim rests on choice 15 alone.

### Renamed for Ubuntu or provided another way (no loss)

avahi (`avahi-daemon`); bluez-utils (`bluez`, `bluez-tools`); fcitx5-gtk and fcitx5-qt (`fcitx5-frontend-gtk3`, `-gtk4`, `-qt6`); fd (`fd-find`); gpu-screen-recorder (`gpu-screen-recorder-cli`); gvfs-mtp, gvfs-nfs, gvfs-smb (`gvfs-backends`); libvips (`libvips-tools`); nautilus-python (`python3-nautilus`); networkmanager (`network-manager`); noto-fonts, -cjk, -emoji (`fonts-noto-core`, `-cjk`, `-color-emoji`); nss-mdns (`libnss-mdns`); nvim (`neovim`); python-gobject (`python3-gi`); qt6-imageformats (`qt6-image-formats-plugins`); sushi (`gnome-sushi`); tesseract and tesseract-data-eng (`tesseract-ocr`, `tesseract-ocr-eng`); tldr (`tealdeer`); woff2-font-awesome (`fonts-font-awesome`); yaru-icon-theme (`yaru-theme-icon`); zbar (`zbar-tools`); libsecret (`libsecret-1-0`; Arch's `secret-tool` is lost, low value); libyaml (`libyaml-0-2`). Moved into the distro's own packages: asdcontrol, hyprland-preview-share-picker, localsend, ffmpegthumbnailer and pamixer (desktop packages); hyprland, quickshell, sddm, uwsm, gnome-keyring, wireplumber, xdg-desktop-portal-gtk and -hyprland (session packages); ttf-ia-writer and ttf-jetbrains-mono-nerd-basic (`oaxaca-fonts`). Replaced: chromium (the xtradeb PPA's build, preinstalled; the list's comment calling it a snap placeholder with snapd pinned out is stale), evince (Papers; stonking's evince is an alpha).

### Justified

| Package | Why |
|---|---|
| expac, fakeroot, pacman-contrib, yay | pacman and AUR tooling |
| kernel-modules-hook | an Arch pacman hook; Ubuntu keeps old kernel packages installed |
| inetutils | `hostname` and `iputils-ping` cover what is used |
| tzupdate | not in stonking; Calamares guesses the timezone itself |
| ufw-docker | not in stonking; re-check if Docker comes back with ufw enabled |
| aether | Omarchy's theme designer; not in stonking, and its repository has no licence, so it cannot be redistributed |
| python-poetry-core | nothing uses it (the list's recorded reason, "dev-env installs them via mise", is wrong: dev-env does not) |
| dotnet-runtime | Omarchy shipped it for Pinta; justified only if Pinta comes from Flathub, which bundles .NET (the recorded reason is wrong too) |
| qemu-user-static-binfmt | for multi-architecture Docker builds; justified while Docker is out |

### Restore candidates

| Package | What it is | Facts (stonking, 2026-10-16) | How |
|---|---|---|---|
| unzip | extract .zip files | main 6.0-31; the image has no unzip, zip or 7zip | base list |
| btop, with `config/btop/btop.conf` | system monitor (Super+Ctrl+T, theme sync) | universe 1.4.7-1; the image has no system monitor at all | base list, config, binding, theme hook |
| starship, with `config/starship.toml` | shell prompt | universe 1.26.0; `default/bash/init` still starts it when present | base list, config |
| zoxide | smarter `cd` | universe 0.10.0; `default/bash/aliases` still wires it | base list |
| eza | modern `ls` | universe 0.23.5-5; the `ls`/`lt` aliases still call it | base list |
| mise and usage | Omarchy's developer-tool manager, behind dev-env and the coding-agent launchers | not in stonking; mise's vendor apt repository (`mise.jdx.dev/deb`) is live, and the vendor publishes a classic snap | vendor apt repository (today a curl script installs it on demand) |
| gnome-disk-utility | Disks: format, SMART, images | main 46.1; `oaxaca-desktop-apps` holds it but is only Suggested, so it is never installed and no menu entry installs it | Depends or Recommends |
| a calculator | Calculator key, Super+Ctrl+Q | Omacalc is not in stonking; gnome-calculator 1:50.0 in main; the image has no calculator | preinstall gnome-calculator and bind the keys, or build Omacalc (MIT) |
| inxi | hardware summary in `omarchy-debug` | universe 3.3.41; the debug report says "inxi is not installed" | base list |
| dua-cli | disk usage TUI behind the "Disk Usage" launcher | universe 2.34.0-1 | base list, launcher |
| lazygit, with its (empty) config | git TUI | universe 0.57.0 | base list |
| Obsidian | notes (Super+Shift+O, theme sync) | the vendor's snap (`obsidianmd`, classic) and Flathub | snap, `omarchy-theme-set-obsidian`, binding |
| whois, ruby | small tools Omarchy shipped on purpose (ruby: "Ensure the system always has a base ruby", upstream `b7989ac8`) | main | base list |
| Docker (docker.io, docker-buildx, docker-compose-v2) | containers, enabled by Omarchy with sudoless access | main and universe | with Omarchy's deleted setup scripts; lazydocker would need a build of the distro's own |
| xournalpp, obs-studio, kdenlive | Omarchy's preinstalled apps | universe | base list (kdenlive is large) |
| Pinta, Moonlight | Omarchy's preinstalled apps | not in stonking; Flathub (Pinta's snap is a third party's) | Flathub |
| LibreOffice | office suite | Install > Productivity installs Canonical's snap | preinstall the snap to match Omarchy |
| Omarchy's own MIT apps: ttfx, herdr, cliamp, omawrite, omacut, try | screensaver effects, terminal multiplexer, music player, writing app, video trimmer, throwaway directories | not in stonking; licensed MIT or Apache-2.0 | build in the distro's apt repository, as LocalSend is |
| Omarchy's LazyVim configuration (omarchy-nvim), with lua5.1, luarocks, tree-sitter-cli and a C compiler | Neovim set up by Omarchy | the port dropped it because the package build cannot fetch plugins | ship the configuration in `/etc/skel` and let lazy.nvim fetch plugins on first launch |
| libpq-dev, libmariadb-dev | headers for Rails' pg and mysql2 gems | main | add to `dev-env ruby` |

## Features cut inside files the port kept

| Feature | Where | What it did | Removed because | Checked facts | Verdict |
|---|---|---|---|---|---|
| SSH client keepalive | `install/config/all.sh` ran `ssh-keepalive.sh` | wrote `/etc/ssh/ssh_config.d/20-omarchy-keepalive.conf`: `ServerAliveInterval 15`, `ServerAliveCountMax 3`, `ConnectTimeout 10` | docs/6, "Ubuntu's configuration, not Omarchy's" (stonking ships `ssh_config.d` empty) | the port kept `default/bash/fns/ssh-reconnect`, which Omarchy's script says the keepalive exists for; without it a dead connection hangs until TCP gives up | **Restore**: the three-line drop-in in the config package |
| btop: Super+Ctrl+T "Activity", theme sync, restart on theme change | `default/hypr/bindings/utilities.lua`, `bin/omarchy-theme-set`, `install/user/theme.sh` | themed system monitor on a key | docs/6 choice 15 ("Command-line preferences") | btop 1.4.7-1 in universe; the plan (docs/0, line 380) said to keep btop and add GPU boxes | **Restore** with `config/btop`, the binding, the restart and the theme link |
| Voxtype first-run invitation | `bin/omarchy-provision-first-run` | one-time "Install Dictation with Voxtype" notification | removed 2026-10-10 when Voxtype could not be installed (choice 5) | Voxtype is in the distro's apt repository since choice 30 (2026-10-14) | **Restore** `install/user/first-run/install-voxtype.hook` |
| DNS for every network, present and future | `bin/omarchy-dns` | Cloudflare, Google or custom DNS for all connections, with a Quad9 fallback | docs/6: rewritten on nmcli as the user, no sudoers rule, no edit of `resolved.conf` | the port changes only the connection profiles that exist when it runs; a network joined later uses DHCP's DNS | **Partial**: NetworkManager's global DNS (a `global-dns` drop-in or the D-Bus `GlobalDnsConfiguration`) |
| Edge, Brave, Zen | `bin/omarchy-install-browser`, `-remove-browser`, `-theme-set-browser`, `-theme-set-browser-policy`, `-install-chromium-copy-url` | install, remove and theme these browsers | docs/6: proprietary builds replaced by open counterparts | Chrome and VS Code came back since, so that rule no longer holds; Microsoft's Edge apt repository, Brave's repository (already added for Brave Origin) and Flathub's `app.zen_browser.zen` (verified) exist | **Restore** |
| 1Password extension in Chromium | `bin/omarchy-install-service-1password` | wrote `/usr/share/chromium/extensions/<id>.json` so the extension installs itself | no reason recorded | Chromium is preinstalled and reads that directory | **Restore**, with the removal in `omarchy-remove-service-1password` |
| Fingerprint skipped with the lid closed | `bin/omarchy-setup-security-fingerprint` (`pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed`) | a docked, closed laptop went straight to the password | docs/6: Ubuntu's `fprintd` pam-auth-update profile is used | `omarchy-hw-laptop-closed` still ships; `pam_fprintd` now sits in `common-auth` for sudo, polkit and SDDM, so a docked laptop waits up to 10 s on the reader | **Partial**: a pam-configs profile of the port's own with the gate before `pam_fprintd` |
| `ic`, `ix`, `icx` aliases | `default/bash/aliases` | tmux development layouts with an agent | none recorded (removed when tmux was out) | `tdl` is back (choice 25) | **Restore** |
| Calculator key | `utilities.lua` (`XF86Calculator`, Super+Ctrl+Q → `omacalc`) | the keyboard's Calculator key | choice 5 (Omarchy's own app) | gnome-calculator 1:50.0-1ubuntu1 in main | **Partial**: bind to gnome-calculator |
| Obsidian binding and theme sync | `applications.lua` (Super+Shift+O), `omarchy-theme-set` | launch and theme Obsidian | docs/6, core and apps | Snap Store (`obsidianmd`) and Flathub | **Partial**: a binding shown only when Obsidian is installed |
| Symfony development environment | `bin/omarchy-install-dev-env`, `-remove-dev-env` | `omarchy install dev-env symfony` | none recorded | not in stonking; Symfony's apt repository on Cloudsmith has `symfony-cli` 5.22.1 | **Restore** through `omarchy-pkg-repo-add` |
| Kernel parameters for ASUS Panther Lake laptops and FRED | `install/hardware/all.sh` (`xe.enable_dpcd_backlight=1`, `xe.enable_panel_replay=0`, `fred=on`) | backlight and display on ASUS B9406 and UX5406AA | docs/6: wrote Limine drop-ins | Ubuntu's GRUB passes parameters too (`/etc/default/grub.d/*.cfg`); the kernel's FRED default is not checked | **Partial** (ASUS); FRED unclear |
| Surface and MacBook SPI keyboard modules in the initramfs | `install/hardware/all.sh` | the keyboard works at the disk encryption passphrase prompt | docs/6: mkinitcpio and DKMS | the DKMS part rightly stays out; `applespi` and the Surface modules are in the mainline kernel | **Partial**: hardware-gated `/etc/initramfs-tools/modules` lines |
| Wireless regulatory domain from the timezone | `install/hardware/all.sh` | sets the country for Wi-Fi channels | the script writes an Arch file | `wireless-regdb` is in the base list | **Partial** (low): `options cfg80211 ieee80211_regdom=XX` |
| RetroArch CRT shader and full core set | `bin/omarchy-install-gaming-retroarch` | CRT look, about 30 cores | in-file comment: no Ubuntu packages; the Online Updater fetches them | | **Justified** |
| HEY bindings and mailto | `applications.lua`, `mimeapps.list` | HEY web app | choice 27, the maintainer's request | Super+Shift+E opens Thunderbird | **Replaced** |
| Herdr, Cliamp, Omawrite, lazydocker bindings; `h` alias | `applications.lua`, `utilities.lua`, `aliases` | Omarchy's own apps | choice 5 | not in stonking | **Justified** |
| OpenClaw as default agent | `bin/omarchy-default-agent` | `omarchy default agent openclaw` | `PORT.md`: only a third party's snap | | **Justified** |
| Bluetooth pairing agent `bt-agent.service` | `install/user/first-run/enable-user-units.sh` | headless pairing | docs/6: blueman's applet autostarts | not checked that XDG autostart runs under the uwsm session | **Replaced**, to confirm on a booted Oaxaca |
| Debug log upload | `bin/omarchy-debug` | 24-hour shareable URL on logs.omarchy.org | in-file comment: no upload service | Omarchy's own service | **Justified** |
| Performance power profile on AC | `bin/omarchy-powerprofiles-set` | performance on AC | in-file comment (Legion fans; Ubuntu's default is balanced) | | **Justified** |
| Snapshots | `omarchy-snapshot`, `omarchy-update` | Snapper and Limine | choice 38 | | **Replaced** (Timeshift on btrfs) |
| Faillock (10 tries, 120 s) | `omarchy-apply-lock`, `install/config/all.sh` | lockout after failed passwords | docs/6 | Ubuntu's `common-auth` has no `pam_faillock` | **Justified** |
| Passwordless default keyring | `install/user/all.sh`, `install/login/all.sh` | keyring without a password | docs/4 choice 14 | | **Justified** |
| Arch setup steps (firewall script, docker.sh, theme-system.sh, pacman, module cleanup, service enables) | `install/config/*`, `install/post-install/all.sh`, `enable-services.sh` | Arch-specific setup | docs/6, choice 13 | | **Justified** |
| Arch, AUR and DKMS drivers (NVIDIA, Vulkan, VA, IPU7, T2, bcm43xx, yt6801, Tuxedo, asusctl, Dell haptics, Surface firmware) | `install/hardware/all.sh` | drivers | docs/6 | NVIDIA through `oaxaca-drivers-install`; Mesa Vulkan and VA drivers in `oaxaca-session`; the rest need DKMS (a MOK) or a custom kernel, or are not in stonking | **Replaced** or **Justified** |
| Emacs daemon theme integration | `bin/omarchy-install-editor-emacs` | themed Emacs | Omarchy's own AUR package | | **Justified** |
| umu-launcher, wine-staging for Lutris | `bin/omarchy-install-gaming-lutris` | Proton runner | in-file comment | not in stonking | **Justified** |
| Package cache keeps two versions | `omarchy-update-pkg-prune` | offline downgrade | in-file comment | | **Justified** |
| Update conflict handler, keyring, AUR steps, stable-channel downgrade | `omarchy-update*`, `omarchy-reinstall-pkgs` | pacman-only | docs/6 | | **Justified** |

## Broken references and leftovers

Things in the port today that call something deleted, or ship without the feature they served:

- `bin/omarchy-launch-screensaver` exits when `ttfx` is missing, so the screensaver never runs.
- `bin/omarchy-clipboard-open` and imv's Ctrl+E (`config/imv/config`) call `tensaku-edit`, Omarchy's image editor, which is not installed; swappy is the port's editor.
- The `symfony)` branch of `bin/omarchy-install-dev-env` installs `symfony-cli`, which stonking does not have.
- `bin/omarchy-debug` prints "inxi is not installed".
- `default/bash/init` and `default/bash/aliases` wire starship, eza and zoxide, none of which is installed.
- The ported agent skill (`default/agents/skills/omarchy/SKILL.md`) points at the btop, lazygit and starship configuration files, which were deleted.
- Scripts with nothing calling them: `omarchy-launch-terminal-herdr`, `-menu-herdr-keybindings`, `-refresh-herdr`, `-restart-herdr` and `config/herdr/`; `omarchy-launch-openclaw`, `-openclaw-onboard`; `omarchy-install-font` (with Arch package names); `omarchy-hw-dell-xps-haptic-touchpad`; `omarchy-theme-set-t3code`.
- Comments and docs that are out of date: `omarchy-default-agent` names `omarchy-install-openclaw-cli`; `enable-services.sh` describes a wait-online mask that is gone; the package list says Chromium is a snap placeholder with snapd pinned out, and that "dev-env installs" lua51, luarocks and python-poetry-core through mise (it does not; and Omarchy shipped `dotnet-runtime` for Pinta); `PORT.md` says Omarchy's list does not install `try` (it has `tobi-try`); docs/6 says Chrome and VS Code were replaced (both are back); docs/0 and docs/1 give different reasons for leaving out hibernation.
