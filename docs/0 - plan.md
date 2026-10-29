# Custom distro: Hyprland + Quickshell + Omarchy look, with apt

*Wording revised 2026-10-05 to follow the documentation guidelines (terms defined before use, subjects named); decisions, facts and dates unchanged.*

## Context

Goal: your own Linux distro with a base system, apt, [Wayland](#wayland-xwayland-and-glx), Xwayland, [Hyprland](#hyprland-quickshell-and-omarchy), Quickshell, and Omarchy's desktop, themes, and fonts. Two starting points are on the table: [Linux From Scratch](#linux-from-scratch) (LFS/BLFS plus the dpkg hints) or an Ubuntu base. This plan compares the two starting points, recommends one, and gives the roadmap. This plan is advisory; nothing gets built in the session that wrote it.

### Facts checked today (2026-09-24)

- **Omarchy v4.0.4** (omacom/omarchy, MIT, released 2026-09-15) now runs the whole desktop in Quickshell: "one long-lived Quickshell process" hosts the bar, panels, menus and overlays as plugins (`shell/README.md`). Waybar is out. So "Quickshell + Omarchy look" is one requirement now, not two.
- Omarchy is **built for [Arch](#arch-pacman-and-the-aur)**. `install/omarchy-base.packages` uses Arch/AUR names (`yay`, `pacman-contrib`, `ttf-ia-writer`, `ttf-jetbrains-mono-nerd-basic`, and Omarchy's own packages like `owe`, `aether`, `omacut`). `default/` has `pacman`, `libalpm`, `limine` and `snapper` pieces. `bin/` has 459 `omarchy-*` scripts, and some wrap pacman (`omarchy-pkg-*`, `omarchy-refresh-pacman`).
- **Omarchy theming anatomy:** you run `omarchy-theme-set <name>`, a bash script. That script copies `themes/<name>/` (most themes are just a `colors.toml` plus backgrounds and previews), then calls `omarchy-theme-set-templates`, which fills in the [templates](#templates-and-theme-switching) under `default/themed/*.tpl` (including `hyprland.lua.tpl` and `shell.toml.tpl`). Then `omarchy-theme-set` tells the running Quickshell process to reload. None of that chain is tied to a distro, so the theming ports cleanly.
- **Ubuntu packaging** ([Launchpad](#launchpad-and-ppas)): `hyprland` is 0.53.3 in 26.04 [LTS](#ubuntu-series-lts-and-interim-releases) "Resolute Raccoon" and 0.56.2 in 26.10 "Stonking Stingray", which is in freeze now and ships in October. `quickshell` 0.3.0 is **only in 26.10**. 26.04 LTS doesn't have Quickshell at all.
- **Minimum Hyprland for Omarchy v4.0.4 is 0.55.0** (checked 2026-09-24). Lua config first shipped in Hyprland 0.55.0 (2026-05-09), and Omarchy switched its configs to Lua the next day ("Swap configs to lua", 2026-05-10). Every Lua function, event and config option Omarchy uses exists in 0.55.0. So 26.04's Hyprland 0.53.3 can't run Omarchy at all, and 26.10's 0.56.2 is fine. The check covered names only, not argument shapes, so booting a test image is the final proof.

## Terms

Each entry uses only terms defined above it, or terms the [README](README.md#terms) defines (package, source package, suite and pocket, component, archive, Essential and Priority, Recommends, metapackage, build dependencies, chroot). Those developer README terms are linked, not repeated. The first use of each term below links to its entry.

### Hyprland, Quickshell and Omarchy

Hyprland is a Wayland compositor: the program that draws windows and reads input, which on Wayland is also the display server. Since 0.55.0 Hyprland reads its configuration as Lua files. Quickshell is a Qt/QML toolkit for building desktop shells, meaning bars, panels, menus and overlays. Omarchy is DHH's desktop setup for Arch Linux, incubated at 37signals and now funded by the Omacom Foundation (omarchy.org/foundation): a Hyprland configuration, a Quickshell-based shell, themes, fonts and about 460 `omarchy-*` scripts. This plan ports Omarchy to an apt-based system.

### Omarchy's shell

The single long-lived Quickshell process that Omarchy starts, running `shell/shell.qml`, which loads plugins for the bar, the panels, the menu and the lock screen. "Shell" in this plan always means this process, never a command interpreter; scripts are called bash scripts.

### Linux From Scratch

LFS is a book and project for building a Linux system by compiling every package from source by hand. BLFS ("Beyond LFS") covers the desktop and server software on top. The "dpkg hints" are community notes on adding dpkg to such a system.

### Arch, pacman and the AUR

Arch Linux is the rolling-release distribution Omarchy is built for. pacman is Arch's package manager, the counterpart of apt and dpkg together. The AUR (Arch User Repository) holds community build recipes that `yay` and similar tools compile locally; it is where Omarchy gets packages Arch itself does not ship, such as `asdcontrol`.

### Ubuntu series, LTS and interim releases

Ubuntu publishes a series every six months, named by year and month (26.04, 26.10) with a codename that doubles as the apt [suite](README.md#suite-and-pocket) (`resolute`, `stonking`). An LTS (long-term support) series ships every two years in April and gets five years of updates; an interim series gets nine months. Launchpad, defined below, is where the series' package versions are published.

### Backport

Rebuilding a newer version of a package, taken from a newer series or from upstream, so that it installs on an older series, and publishing that rebuild in your own apt repository. A backport is yours to maintain and update.

### Desktop environment

A DE is a complete desktop suite such as GNOME or KDE Plasma: display manager, session, window manager, panels, settings and a set of applications, shipped as one dependency tree. This plan installs no DE; Hyprland, Quickshell and Omarchy's shell take that role piece by piece.

### minbase

One of mmdebstrap's package-set variants: only the `Essential: yes` packages plus every `Priority: required` package, which includes apt. The result has no kernel, no init and no network configuration; every later layer is an explicit choice. The developer README's [mmdebstrap section](README.md#mmdebstrap-make-chroot) lists the other variants.

### Snap

Canonical's self-contained application package format, served by the `snapd` daemon from Canonical's store rather than from the apt archive. On Ubuntu some apt packages, such as `chromium-browser` and `firefox`, are empty placeholders whose only job is to install the snap.

### sysfs

The kernel's view of devices and their settings, mounted at `/sys` and read and written as ordinary files. Examples in this plan: `/sys/power/mem_sleep`, `/sys/class/backlight/`, `/sys/bus/pci/devices/<address>/power/`.

### udev rules and systemd units

A udev rule is a line in a file under `/etc/udev/rules.d/` or `/usr/lib/udev/rules.d/` that matches a device event (a device being added, for example) and reacts by setting permissions, running a program, or asking systemd to start a unit. A systemd unit is a service, timer, mount or device description in a `.service`-style file; a user unit runs inside a user's login session instead of system-wide, and a oneshot unit runs a command once and exits.

### Secure Boot

A firmware feature that only runs boot code signed by a key the firmware trusts. Ubuntu's shim is signed by Microsoft, and shim verifies Ubuntu's GRUB and kernel, which Canonical signs. The kernel then refuses unsigned kernel modules. Secure Boot can be turned off in the firmware setup; the distro supports it in both states and never requires it (see `1 - policy.md`, section 5).

### LSM and lockdown

A Linux Security Module is a set of hooks inside the kernel that can refuse an operation; AppArmor is one LSM. Lockdown is another LSM, which Ubuntu's kernel turns on when it boots under Secure Boot. In `integrity` mode lockdown blocks anything that would let root alter the running kernel: unsigned modules, raw memory access, and hibernation. `/sys/kernel/security/lockdown` shows the mode.

### MOK

A Machine Owner Key: a signing key the machine's owner adds to the firmware's trust list through shim (`mokutil`), so that modules or kernels signed with it load under Secure Boot. Enrolling one needs a reboot and a password prompt at boot; this plan's default path never asks for that.

### DKMS

Dynamic Kernel Module Support: a framework that compiles an out-of-tree kernel module on the machine itself every time a new kernel is installed. Under Secure Boot the result has to be signed with a MOK. Canonical's prebuilt `linux-modules-nvidia-*` packages are the alternative this plan chooses.

### HWE kernel

Hardware enablement kernel: a newer kernel series that Canonical backports to an LTS so that new hardware works there. The prebuilt NVIDIA modules exist for the stock kernel and for the HWE kernels only.

### iGPU, dGPU, hybrid graphics and MUX mode

The iGPU is the graphics unit inside the CPU (Intel here); the dGPU is the separate NVIDIA chip. A hybrid laptop has both, with the internal display and usually the outputs wired to the iGPU, so the dGPU renders and copies frames across. A MUX (multiplexer) is a hardware switch some laptops have, set in the firmware, that wires the internal display straight to the dGPU instead; that configuration is called MUX or dGPU-only mode.

### GSP

The GPU System Processor: a RISC-V core on NVIDIA GPUs from the Turing generation onward that runs NVIDIA's firmware. NVIDIA's open kernel modules offload work to it and therefore run only on GPUs that have one.

### Wayland, Xwayland and GLX

Wayland is the display protocol between applications and the compositor. Xwayland is an X11 server that runs as a Wayland client so that applications written for X11 still work. GLX is the OpenGL binding for X11, so only applications running under Xwayland use it; native Wayland applications use EGL or Vulkan instead.

### VA-API and NVDEC

VA-API is the Linux video decode and encode API that browsers and players call. NVDEC is the NVIDIA GPU's hardware video decoder. `nvidia-vaapi-driver` is the bridge: it implements VA-API on top of NVDEC, selected with the `LIBVA_DRIVER_NAME=nvidia` environment variable.

### Render offload

Running one application on the dGPU while the compositor and everything else stay on the iGPU. NVIDIA selects it per process with the environment variables `__NV_PRIME_RENDER_OFFLOAD=1` and `__GLX_VENDOR_LIBRARY_NAME=nvidia`; "PRIME" is the Linux name for this GPU switching.

### DRM devices and connectors

DRM (Direct Rendering Manager) is the kernel's graphics interface. Each GPU is a DRM device, `/dev/dri/cardN`, and each output on it is a connector named by type and index: `eDP-1` is the internal display, `DP-1` a DisplayPort output, `HDMI-A-1` an HDMI output. sysfs lists them under `/sys/class/drm/cardN-<connector>/` with a `status` file reading `connected` or `disconnected`.

### Multiarch

dpkg's ability to install packages built for a second architecture next to the native ones. `dpkg --add-architecture i386` enables 32-bit x86 packages on a 64-bit system, which 32-bit games and parts of Steam need; it also doubles the download size of every library installed for both.

### Unprivileged user namespaces

A kernel feature that lets a process without root privileges create its own isolated view of users, mounts and network. Browser and Electron sandboxes rely on it. Since 23.10 Ubuntu uses AppArmor to allow it only to programs that have a profile.

### Portals

xdg-desktop-portal: D-Bus services through which applications ask the desktop for file pickers, screen sharing, screenshots and settings, so that sandboxed and Wayland applications do not need direct access. Each desktop provides a backend; `xdg-desktop-portal-hyprland` covers screen sharing under Hyprland and `-gtk` covers file dialogs.

### Display manager and uwsm

A display manager is the graphical login screen that starts a session after authentication; Omarchy uses SDDM. uwsm (Universal Wayland Session Manager) is what SDDM then runs: it starts the compositor as a systemd user session so that user units, environment files and logind integration work the way they do under GNOME or KDE.

### Templates and theme switching

Omarchy keeps the configuration files that carry colors as templates, `default/themed/*.tpl`, with placeholders for theme values. `omarchy-theme-set <name>` copies a theme directory, fills every template, writes the results into the user's config, and tells Omarchy's shell to reload. A "theme template" for a program means such a `.tpl` file exists for it.

### Migrations

Omarchy's `migrations/` directory: dated scripts that run once each on an existing installation to move user configuration forward after an upgrade, the way database migrations do. Porting Omarchy means porting new migrations with each rebase.

### initramfs

The small early-boot filesystem the bootloader loads with the kernel; it holds the modules and tools needed before the real root filesystem is mounted, such as the NVIDIA modules and the LUKS unlock. Ubuntu builds it with `initramfs-tools` (`update-initramfs`); Arch and Omarchy use `mkinitcpio` for the same job.

### Limine, Snapper and btrfs

Arch-side pieces Omarchy relies on that this plan does not port: Limine is the bootloader Omarchy installs (Ubuntu's default is GRUB), btrfs is the filesystem Omarchy formats with, and Snapper takes btrfs snapshots before updates so an update can be rolled back.

### LUKS and Plymouth

LUKS is the Linux disk encryption format, managed by `cryptsetup`; `cryptsetup-initramfs` adds the unlock step to the initramfs. Plymouth is the graphical boot splash, and under full-disk encryption it is what draws the passphrase prompt; Omarchy ships a Plymouth theme.

### Sleep states

Suspend to RAM keeps memory powered and turns the rest off: `deep` (ACPI S3) does that fully, `s2idle` is the firmware-light variant where devices idle instead. `/sys/power/mem_sleep` lists what the firmware offers and marks the default. Hibernation (S4) writes memory to swap and powers off entirely; suspend-then-hibernate does the first and later switches to the second.

### logind and inhibitors

systemd-logind is the service that handles sessions, the lid switch and sleep requests. A program can hold an inhibitor: a *delay* inhibitor makes logind wait a few seconds before sleeping so the holder can act (lock the screen, save state), a *block* inhibitor stops the action, and the `PrepareForSleep` D-Bus signal tells listeners that sleep is about to happen or has just ended.

### Launchpad and PPAs

Launchpad is Canonical's development platform: Ubuntu's bug tracker, build farm and package publishing, and the source of the version facts in this plan. A PPA (Personal Package Archive) is an apt repository hosted on Launchpad that builds the source packages you upload, signed with a key Launchpad holds.

### Image and installer tools

mkosi builds bootable disk images from a package list with systemd's tooling, which suits quick virtual-machine tests. live-build builds Debian-style live and installer ISOs. Calamares is a graphical installer framework distributions embed in their ISOs; it handles partitioning, LUKS, users and the bootloader.

### OSD

On-screen display: the short-lived overlay that shows a volume or brightness level after a key press. Omarchy's shell draws it (`omarchy-osd`).

## Options and tradeoffs

| | A. LFS/BLFS + dpkg/apt added on | B. Ubuntu base (recommended) | C. Debian testing base | D. Fork Omarchy on Arch |
|---|---|---|---|---|
| apt | You add apt yourself: dpkg's status database starts out empty, so you'd have to fake entries for every LFS-built package, or apt can't resolve dependencies | Built in | Built in | No, uses pacman (fails your requirement) |
| Package [archive](README.md#archive) | None. Every .deb (Mesa, Qt6, PipeWire, Hyprland's ~8 hypr* libraries...) is yours to build and patch for security | Ubuntu archive plus your own small repo | Debian archive plus your repo | Arch + AUR |
| Hyprland/Quickshell | Build from source. Recent Hyprland needs a very new C++ compiler | In the 26.10 archive. For an LTS you [backport](#backport) both | Hyprland is in Debian's archive; Quickshell is newer in Debian's archive than in Ubuntu's | Native, same versions Omarchy tests |
| Omarchy port effort | Highest (all Arch assumptions plus a bare base) | Medium: swap pacman for apt in the wrapper scripts, repackage fonts and Omarchy's own apps | Medium, same as B | Lowest |
| Ongoing cost | Very high. You're the security team for hundreds of packages | Low to medium: you maintain about 5 to 15 packages | Medium: testing moves under you | Low |
| Learning value | Highest | Moderate (packaging, image building) | Moderate | Low |
| Release cadence | Yours | 26.10 interim (9-month support) now, then the next LTS | Rolling-ish | Rolling |

**Main tension:** Omarchy follows Arch's rolling releases. Any apt base gives you *version skew*, where Ubuntu's Hyprland and Quickshell lag what Omarchy's configs expect. How much skew you tolerate decides your base release and how much you backport.

## Recommendation

**Option B: an Ubuntu-based distro, started on 26.10, with your own apt repository for the Hyprland/Quickshell stack and the ported Omarchy pieces. Move to the next LTS once that LTS ships Quickshell.** This is a judgment call, not a vendor-documented best practice. Reasons:

- Option B is the only apt option where both Hyprland and Quickshell are in the official archive today, so you only maintain the delta.
- LFS gives you apt the tool but not apt the ecosystem. With no .deb archive behind apt, apt does nothing you couldn't do by hand. You'd spend most of your time on Mesa/Qt/security rebuilds instead of your desktop.
- Rejected: **A (LFS)** as the product, because of the maintenance load. LFS is still worth doing as a separate learning project in a VM. **D (Arch)**, because it fails the apt requirement. **C (Debian testing)** is a close second if you'd rather avoid Canonical-specific tooling. The roadmap for C is almost the same as for B.
- Accepted costs: the 26.10 interim release forces a base upgrade around mid-2027. And you have to keep merging upstream's new tags into your Omarchy fork, porting or deleting each new upstream [migration](#migrations) (`migrations/`).

## Exactly which Ubuntu base

**You don't start from Ubuntu Desktop and strip GNOME out. You build up from the Ubuntu archive, so no [desktop environment](#desktop-environment) is ever installed.** There are three ways to get an Ubuntu base without a desktop:

| Starting point | What it is | Has a DE? | Verdict |
|---|---|---|---|
| **`mmdebstrap --variant=minbase stonking` from the Ubuntu archive** | A script that builds a root filesystem straight from `archive.ubuntu.com`: just apt, dpkg, coreutils and essentials. No kernel, no systemd yet; you add the kernel and systemd afterwards | No | **Use this.** mmdebstrap is scriptable and reproducible, and you pick every package after the base |
| Ubuntu Base tarball (`cdimage.ubuntu.com/ubuntu-base`) | A prebuilt rootfs of about 30 MB, made for containers | No | About the same content, but the tarball is a download you can't control. Fine for quick experiments |
| Ubuntu Server ISO | A full installed server | No | No GNOME, but the server install brings snapd, cloud-init, netplan, landscape tools and server defaults you'd have to remove. Starting from Desktop is worse still: you'd remove GNOME, [snaps](#snap) and gdm |

So the base is **Ubuntu 26.10 `stonking`, `main` + `universe` [components](README.md#component), built with `mmdebstrap --variant=minbase`, then an explicit package list on top**. The layers on top (roadmap steps 3 to 6) are: `linux-generic`, `systemd-sysv`, `network-manager`, `pipewire`/`wireplumber`, then `hyprland`, `quickshell`, `xwayland`, the [portals](#portals), `sddm`, `uwsm`, then your `oaxaca-*` packages.

What to watch for so GNOME/KDE pieces don't creep back in:
- **Install without [Recommends](README.md#recommends).** *Changed 2026-10-14 (`3 - rootfs.md`, choice 4): Recommends are on, with `xdg-desktop-portal-gnome` and `sudo-rs` pinned out; leaving Recommends off cost a test round per missing package.* Build images with apt's `APT::Install-Recommends "false";` option, and ship that same line in a file under `/etc/apt/apt.conf.d/` in the image (apt reads every file in that directory; one `Name "value";` option per line), so installs after first boot behave the same way. Otherwise packages like `nautilus` or `sddm` can pull in large parts of GNOME or KDE through Recommends. Omarchy itself uses a few GNOME apps (Nautilus, Evince, gnome-keyring). A few GNOME apps are expected, not a full DE.
- **Snaps.** On Ubuntu, `chromium-browser` and `firefox` are placeholder debs that install the snap. Omarchy uses Chromium. Either hold `snapd` off the system with an apt pin (a stanza in a file under `/etc/apt/preferences.d/` reading `Package: snapd`, `Pin: release *`, `Pin-Priority: -1`) and use Mozilla's Firefox apt repo or Google Chrome's deb repo, or accept snapd. Minbase doesn't include snapd, so avoiding snapd is just a matter of not pulling it in.
- **Networking.** Ubuntu Server uses netplan + systemd-networkd. With [minbase](#minbase) you skip netplan and use NetworkManager directly, as Omarchy does. *Found in step 3 (2026-10-07): `stonking`'s `network-manager` package depends on `netplan.io`, so netplan is installed anyway; a one-line netplan file sets `renderer: NetworkManager` and netplan generates nothing of its own.*

### Kernel and security updates come from Ubuntu

**You don't package the kernel.** The plan installs Ubuntu's `linux-generic` [metapackage](README.md#metapackage) straight from Canonical's archive, and nothing in the plan rebuilds or patches the kernel. Kernel security fixes reach your users through plain `apt upgrade`, exactly as on stock Ubuntu. Canonical's security team does that work.

- **Anatomy:** `linux-generic` is a metapackage (a package with no files, only dependencies) that always depends on the current kernel binary, modules and headers. When Canonical releases a fixed kernel, the metapackage's dependencies move to that kernel, and apt pulls that kernel in. The NVIDIA modules from `linux-restricted-modules` are rebuilt and signed by Canonical in lockstep, so the NVIDIA modules update along with the kernel.
- **Make sure the image actually sees updates.** Given only the suite name, `mmdebstrap` uses just the release [pocket](README.md#suite-and-pocket) (`stonking`), which never receives fixes. The image's apt sources entry, the stanza file `/etc/apt/sources.list.d/ubuntu.sources`, must also list **`stonking-updates`** and **`stonking-security`** in its `Suites:` line, for every enabled component (`main restricted universe multiverse`). Pass the two extra pockets to `mmdebstrap` as extra `deb` lines on its command line, and ship the same `ubuntu.sources` file in the image.
- **Optional:** add `unattended-upgrades` (from `main`) so security fixes install automatically, like Ubuntu's defaults. Rebooting into a new kernel stays the user's job.
- **The one condition:** you must stay on an Ubuntu kernel. A custom kernel would make kernel security yours and break the signed NVIDIA module setup (see "NVIDIA proprietary driver"). The plan never ships a custom kernel.

**What Canonical covers vs. what you cover.** Ubuntu's security maintenance follows components ([Ubuntu release cycle](https://ubuntu.com/about/release-cycle)):

| Where the package comes from | Who ships security fixes |
|---|---|
| `main` (the kernel, systemd, Mesa, NetworkManager, PipeWire, and so on) and `restricted` (the NVIDIA driver and modules) | Canonical, for the release's whole support period |
| `universe` (Hyprland, Quickshell, and other community packages) | Community maintainers on a best-effort basis. Ubuntu Pro extends Canonical coverage to universe, but only for LTS releases |
| Your own repo (`oaxaca-*`, `nwg-displays`, `asdcontrol`, fonts) | **You.** It's a short list, mostly scripts, configs and small tools, not network-facing daemons |

**Support window.** 26.10 is an interim release with **9 months** of updates, ending around July 2027. After that date, even kernel updates stop, so upgrading to the next release (27.04, or the next LTS once it has Quickshell) isn't optional. Plan the release-upgrade test (roadmap step 8) with that date in mind.

### AppArmor

**Anatomy:** AppArmor has two halves. The *kernel side* is a [Linux Security Module](#lsm-and-lockdown) (LSM, a kernel hook that enforces access rules), and Ubuntu's `linux-generic` kernel already has it built in and enabled. The *userspace side* is the `apparmor` package: the `apparmor.service` unit that loads profiles at boot, the `apparmor_parser` compiler, the profiles in `/etc/apparmor.d/`, and a sysctl file (a kernel-setting file applied at boot), `/usr/lib/sysctl.d/10-apparmor.conf`.

**Does the minbase base include AppArmor?** No. The kernel side becomes active once you install `linux-generic`, but the userspace side isn't part of `minbase`, and `ubuntu-minimal` doesn't depend on or recommend `apparmor` (checked in the resolute package metadata). So without adding the `apparmor` package you get the LSM with no profiles loaded, meaning nothing is confined.

**Is AppArmor a good fit? Yes. Add `apparmor` explicitly.** This is a choice, not a vendor-documented best practice. Reasons:
- The kernel half is already in `linux-generic`, so the extra cost is one package plus a boot-time service.
- Other Ubuntu packages ship their own profiles that load once `apparmor` is present (CUPS is one example). You get confinement for services without writing anything.
- AppArmor keeps you on the security model Ubuntu tests with, so problems look like upstream Ubuntu problems, not problems unique to your distro.

Tradeoffs to plan for:
- **Unprivileged user namespaces.** Since 23.10, Ubuntu uses AppArmor to restrict [unprivileged user namespaces](#unprivileged-user-namespaces). Programs like Chromium's sandbox, Electron apps (Obsidian, which Omarchy ships) and AppImages rely on those namespaces. The `apparmor` package ships the sysctl file above plus profiles such as `chrome`, `chromium` and `unprivileged_userns` that allow known apps. Apps without a profile can fail to start their sandbox. Test every GUI app in your meta-package, and ship small profiles in a `oaxaca-apparmor` package for any that break.
- **Hyprland, Quickshell and your `omarchy-*` scripts run unconfined.** No profiles exist for them, so AppArmor doesn't protect the desktop itself. AppArmor protects services and profiled apps.
- Rejected alternatives: **SELinux**, because Ubuntu doesn't ship or test a policy for it and you'd maintain one yourself. **No LSM userspace**, because that would give up the service confinement above to save one package.

### NVIDIA proprietary driver

**Anatomy:** the NVIDIA driver has two halves. The *kernel modules* are `nvidia`, `nvidia_modeset`, `nvidia_uvm` and `nvidia_drm`; `nvidia_drm` is the one Wayland compositors talk to. The *userspace* is the GL/EGL/Vulkan libraries, the [GSP](#gsp) firmware (code that runs on the GPU's own GSP processor), `nvidia-smi` and so on. The userspace is always proprietary. The kernel modules come in two flavors: NVIDIA's **open** modules (`-open`) or the **closed** ones. So "proprietary driver" in this plan means NVIDIA's own driver (not nouveau/NVK), with whichever module flavor your GPU needs.

**Facts checked (2026-09-24):**
- Ubuntu 26.10 `stonking` has driver branches **580** (580.178.04) and **595** (595.91.07) in the `restricted` component. Each branch has `nvidia-driver-XXX` (closed modules) and `nvidia-driver-XXX-open` metapackages.
- Canonical also publishes **prebuilt, signed modules** for the stock kernel: `linux-modules-nvidia-{580,595}[-open]-generic` (from `linux-restricted-modules`). Canonical signs those modules, so they load with [Secure Boot](#secure-boot) on and you don't have to enroll a [MOK](#mok). The [DKMS](#dkms) alternative (`nvidia-dkms-*`) compiles modules on your machine and needs MOK enrollment under Secure Boot.
- NVIDIA's open modules work on **Turing and newer** GPUs only (the open modules need the GSP; [NVIDIA open-gpu-kernel-modules README](https://github.com/NVIDIA/open-gpu-kernel-modules)). **580 is the last branch for Maxwell, Pascal and Volta** ([NVIDIA support plan](https://nvidia.custhelp.com/app/answers/detail/a_id/5676/)).
- Omarchy already splits NVIDIA users the same way. `install/hardware/nvidia.sh` installs `nvidia-open-dkms` for GSP GPUs and the `nvidia-580xx` legacy driver otherwise. Then `default/hypr/nvidia.lua` sets `NVD_BACKEND`, `LIBVA_DRIVER_NAME` and `__GLX_VENDOR_LIBRARY_NAME` per GPU class. `nvidia.sh` uses the detector scripts `bin/omarchy-hw-nvidia`, `-gsp` and `-without-gsp`, which read [sysfs](#sysfs) and aren't tied to a distro.

**Choice: Canonical's prebuilt signed modules, picked per GPU by `ubuntu-drivers`, installed on the target machine instead of baked into the image.** Package mapping:

| GPU generation | Ubuntu packages | Omarchy equivalent on Arch |
|---|---|---|
| Turing and newer (RTX 20xx+, GTX 16xx) | `nvidia-driver-595-open` + `linux-modules-nvidia-595-open-generic`, plus `nvidia-vaapi-driver` | `nvidia-open-dkms`, `nvidia-utils`, `libva-nvidia-driver` |
| Maxwell / Pascal / Volta | `nvidia-driver-580` + `linux-modules-nvidia-580-generic` (security fixes only, through Oct 2028) | `nvidia-580xx-dkms`, `nvidia-580xx-utils` |

*Correction 2026-10-08 (step 4, `4 - session.md`): in `stonking` today `nvidia-driver-595-open` is a transitional package depending on `nvidia-driver-615-open`, and `ubuntu-drivers` recommends `nvidia-driver-580-open` for this laptop's RTX 5070 Ti, because Ubuntu marks branch 580 `Support: LTSB` and 615 `NFB` and the detector prefers LTSB. The `-open` row's package is therefore the newest open branch with prebuilt modules in the archive at install time, `615-open` at the moment: `oaxaca-drivers-install` computes that from the detector's candidate list and passes it to `ubuntu-drivers install` as `nvidia:<branch>-open`, because the detector's own pick would be the older LTSB branch. The rule "don't hardcode the branch number" below is the one that holds. `ubuntu-drivers` decides "from the distro" by apt's `Origin: Ubuntu` field, not by `/etc/os-release`, so `ID=oaxaca` changes nothing.*

Why this choice:
- **Secure Boot works without asking users to enroll a MOK.** That rejects DKMS as the default; keep DKMS only as a fallback for a custom kernel.
- **`ubuntu-drivers install`** (from `ubuntu-drivers-common`) already knows which branch and flavor fits which PCI ID, so you don't write that table yourself. Omarchy's detectors stay for the Hyprland env vars.
- **Install on the target, not in the ISO.** Installing on the target keeps NVIDIA's binaries out of your published images, so you skip checking NVIDIA's redistribution license for your ISO. *(Revised 2026-10-11, `7 - image-installer.md` choice 20: the license was checked, its section 1.1(d) permits distributing the unmodified packages with the agreement text, and the medium now carries them in a pool the drivers step installs from, so an install works offline; the driver is still not installed in the image.)* That choice also keeps images small for AMD and Intel users. Run `ubuntu-drivers install` as an installer step, or on first boot if an NVIDIA GPU is found.
- **Tradeoff:** the prebuilt modules exist only for Ubuntu's own kernels (`linux-generic` and the [HWE kernels](#hwe-kernel)). If you ever ship a custom kernel, you're back to DKMS and MOK enrollment.

**Where `ubuntu-drivers install` runs.** The step is included, but automated. Users don't have to type `sudo ubuntu-drivers install` themselves.
- **Anatomy:** `ubuntu-drivers` (from `ubuntu-drivers-common`) reads the hardware IDs of the running machine and maps them to driver packages. `ubuntu-drivers` then calls apt to install the recommended package. By default `ubuntu-drivers` chooses the **prebuilt signed** `linux-modules-nvidia-*` packages, and only considers DKMS with `--include-dkms`.
- **Installer step:** the installer runs `ubuntu-drivers install` as root, against the target system, while the live session can see the real hardware. Command: `ubuntu-drivers install --no-oem --package-list /var/log/oaxaca/drivers.list`.
  - `--no-oem` stops `ubuntu-drivers` from adding Canonical's OEM enablement archives for certified machines. That flag is a choice that keeps your distro's apt sources predictable.
  - `--package-list` records what `ubuntu-drivers` picked, which helps when debugging.
- **Afterwards:** a menu entry (Install → Drivers, or similar) runs the same command, for when a user changes GPUs. `sudo ubuntu-drivers install` by hand stays the documented recovery step.
- **Don't hardcode the branch number.** On this laptop today (26.04), `ubuntu-drivers devices` recommends `nvidia-driver-595-open` even though a 610 branch exists. The recommended branch will change over time. Scripts that need the branch, like the Steam 32-bit libraries, should read it from the installed `nvidia-driver-*` package, not assume 595.

What to port or add:
- Enable the `restricted` component in the image's apt sources (the base built with `main,universe` doesn't have `restricted`). Also enable `multiverse` if you want `nvtop` and `intel-media-va-driver-non-free`.
- `oaxaca-nvidia` package, ported from Omarchy's `nvidia.sh`:
  - Ship a file under `/etc/modprobe.d/` (modprobe reads every `.conf` file there; one `options <module> <param>=<value>` line each) containing `options nvidia_drm modeset=1`, unless Ubuntu's driver package already ships that line. Check the installed files first to avoid a duplicate.
  - Swap Omarchy's early-loading `mkinitcpio` config for Ubuntu's `initramfs-tools`: list the modules in `/etc/initramfs-tools/modules` (one module name per line), then run `update-initramfs -u`.
  - Carry over `default/hypr/nvidia.lua` and the `omarchy-hw-nvidia*` detectors unchanged.
- [Hybrid laptops](#igpu-dgpu-hybrid-graphics-and-mux-mode) (Intel/AMD iGPU + NVIDIA): keep the iGPU as the main renderer, and test suspend/resume with NVIDIA's `nvidia-suspend`/`nvidia-resume` [systemd units](#udev-rules-and-systemd-units), which the driver packages ship.
- **32-bit GPU libraries, only when Steam is installed.** Why Steam needs 32-bit GPU libraries:
  - Steam runs games inside its own container, the Steam Runtime, which brings most libraries itself. But the **GPU driver's userspace has to come from the host**, because it must match the host's kernel driver.
  - Any 32-bit program in that chain (32-bit native Linux games, 32-bit Windows games under Proton's classic mode, and still some Steam client parts) needs 32-bit builds of those host GPU libraries. For example, Valve's own [issue #13015](https://github.com/ValveSoftware/steam-for-linux/issues/13015), open since March 2026, notes that even the 64-bit "RT3" beta client ships a 32-bit `reaper` process.
  - Omarchy handles 32-bit libraries the same way: `bin/omarchy-install-gaming-steam` installs `steam`, then runs `omarchy-install-gaming-gpu-lib32`. The 32-bit libraries aren't in Omarchy's base install.
  
  Choice: **mirror Omarchy's on-demand approach, not 32-bit libraries in the base image.**
  - A `oaxaca-install-gaming-steam` script runs `dpkg --add-architecture i386` and installs Steam (Ubuntu's `steam-installer` in multiverse, or Valve's deb). Installing Steam pulls in 32-bit Mesa for the Intel iGPU.
  - On NVIDIA machines, the script also adds `libnvidia-gl-<branch>:i386`, reading the branch from the installed `nvidia-driver-*` package.
  - Installing on demand keeps [i386](#multiarch) multiarch, which roughly doubles the size of GPU-library updates, off machines that never run Steam.

### App launcher

**Hyprland has no launcher.** Hyprland is only the compositor; you bind a key to whatever launcher you run. **Quickshell has no ready-made launcher either.** Quickshell is a toolkit for building desktop shells and provides only the building blocks, such as a `DesktopEntries` API that lists installed apps from their `.desktop` files.

**What Omarchy uses:** Omarchy v3 used Walker (`walker-bin`, next to Waybar). In **v4 the launcher is part of [Omarchy's own Quickshell shell](#omarchys-shell)**, so there's no separate program (checked in v4.0.4):
- **Anatomy:** Omarchy's shell is one Quickshell process running `shell/shell.qml`, which loads plugins. The launcher is the **`omarchy.menu` plugin** (`shell/plugins/menu/`: `Menu.qml`, `MenuModel.js`, `manifest.json`). The menu plugin gets its app list from the shared **`AppLibrary`** service (`shell/services/AppLibrary.qml` + `AppSearch.js`), which reads Quickshell's `DesktopEntries`.
- **Key bindings:** `Super + Space` opens the full Omarchy menu (apps, settings, install software, screenshots, and more; type to filter). `Super + Alt + Space` opens an apps-only launcher (manual `03-coming-from-mac-or-windows.md`).
- **Theming:** colors come from the `[launcher]` and `[menu]` sections of `default/themed/shell.toml.tpl`. `omarchy-theme-set` fills that template, so the launcher follows theme switches the same way the bar does.

**Choice: use Omarchy's built-in launcher. You don't need to package anything extra.** The launcher ships inside `oaxaca-shell` with the rest of `shell/`. The launcher depends only on Quickshell (in the 26.10 archive) and reads standard `.desktop` files, so apps you install with apt show up in the launcher automatically.

What to port:
- **The apps launcher works as-is.** Keep `AppLibrary.qml`/`AppSearch.js` unchanged.
- **The full menu needs pruning.** The full menu's entries (`default/omarchy/omarchy-menu.jsonc` and `MenuModel.js`) call `omarchy-*` scripts, and some of those scripts are Arch-specific: install/remove software through pacman or the AUR, refresh pacman, [Limine](#limine-snapper-and-btrfs) and Snapper actions. Point the install/remove entries at your apt-based `omarchy-pkg-*` rewrites (roadmap step 6), and drop the Arch-only entries.
- **Keep the two key bindings** in the ported `default/hypr/bindings*.lua`.

Rejected alternatives: **Walker** is what Omarchy used before, but Walker isn't in the Ubuntu archive, you'd package Walker and its Elephant backend yourself, and Walker would need its own theme template. **Fuzzel, wofi or rofi** are in the archive, but those launchers don't read Omarchy's theme tokens. You'd write and maintain a template for each launcher, and none of them would look like Omarchy's menu.

### System settings UI

**Omarchy has no single "Settings" app.** Settings are split three ways (checked in v4.0.4):

1. **Quickshell panels.** The panels are plugins in `shell/plugins/panels/` that open from the bar and are themed by the same `shell.toml` template as the menu:

   | Setting | Plugin | What it uses underneath |
   |---|---|---|
   | Bluetooth | `panels/bluetooth` | Quickshell's `Quickshell.Bluetooth` QML module, which talks to BlueZ (the Linux Bluetooth service). The panel runs device discovery and lists devices to connect/disconnect |
   | Wi-Fi | `panels/network` | `Quickshell.Networking` + `nmcli`, both talking to NetworkManager |
   | Audio | `panels/audio` | `Quickshell.Services.Pipewire`: volume, output picker, per-app mixer |
   | Battery and power profile | `panels/power` | `Quickshell.Services.UPower` + power-profiles-daemon |
   | Brightness | `panels/monitor` | Brightness slider and laptop display controls only, no resolution or layout |
   | Night light, idle | `plugins/services/{nightlight,idle}` | Background services, toggled from the bar and menu |

2. **Menu entries that open a config file in an editor.** `Super + Space` → Setup → **Monitors** runs `omarchy-launch-config-editor ~/.config/hypr/monitors.lua`, which opens that file in a text editor. Input and Keybindings work the same way. The DNS entry runs a terminal script.
3. **Separate GTK apps** from Omarchy's package list, for example `system-config-printer` for printers.

**What that means for your list:**
- **Bluetooth, Wi-Fi, audio, power: covered, nothing to package.** Those four panels ship in `oaxaca-shell`, and they need `bluez`, `network-manager`, `pipewire`/`wireplumber`, `upower` and `power-profiles-daemon` installed, and Ubuntu's `quickshell` package must include those Quickshell QML modules. The `quickshell` package's [build dependencies](README.md#build-dependencies) include PipeWire, PAM and polkit, and its package description lists Bluetooth. Check the `Bluetooth` and `Networking` directories exist under `/usr/lib/x86_64-linux-gnu/qt6/qml/Quickshell/` in a test image.
- **Display resolution and arrangement: not covered by a GUI.** Omarchy expects you to edit `hl.monitor({...})` lines in `monitors.lua`.

**Choice for displays: add `nwg-displays`** (a GTK app where you drag monitors around to set their layout, resolution, refresh rate and scale). Match nwg-displays to the theme by GTK theme only; Omarchy's templates don't cover nwg-displays.
- **You'll need to package nwg-displays.** Ubuntu 26.10 has 0.3.28 in `universe`, but Lua output for Hyprland 0.55+ arrived in **0.4.3** (2026-05-17; current is 0.4.4). Ubuntu's version would write the old `monitors.conf` format, which Omarchy's Lua config never loads. nwg-displays is a small Python app, so it's an easy package to maintain: rebuild nwg-displays at ≥0.4.3 into your repo, or backport it from Debian if Debian has a newer version by then.
- **Watch the file-name clash.** nwg-displays' Lua output file and Omarchy's hand-edited file are both `~/.config/hypr/monitors.lua`. Omarchy's version also sets `GDK_SCALE`. Launch nwg-displays with `nwg-displays -m ~/.config/hypr/monitors-gui.lua` (the `-m/--monitors_path` flag exists; check that the flag keeps Lua output at a custom path), and add `require("hypr.monitors-gui")` to Omarchy's `monitors.lua` so both files load.
- Point the menu's **Setup → Monitors** entry at nwg-displays, and keep "edit file" as a secondary entry.
- Rejected alternatives: **writing a Quickshell display-layout panel**, which would look native but is real UI work on top of Hyprland's monitor API. **Editing text only (Omarchy's default)**, which is fine for you but not for a distro others use.

Other settings to add to `oaxaca-desktop`: `system-config-printer` (printers) and `blueman` as an optional fallback for Bluetooth cases the panel doesn't handle (PIN entry, file transfer). Both apps are in the archive.

## This machine: Lenovo Legion Pro 7 16IAX10H

Read-only inventory taken 2026-09-25 from the current Ubuntu 26.04.1 install (kernel 7.0.0, KDE). Items marked **add** aren't pulled in by `minbase` and must be in `oaxaca-desktop` or a hardware package.

| Hardware | Driver / status today | What the plan needs |
|---|---|---|
| Intel Core Ultra 9 275HX (Arrow Lake-HX) | fine | nothing |
| Intel Arrow Lake iGPU (`i915`, `xe` also available) | **Drives every display**: internal eDP-1 and both DP outputs are on the Intel card | Mesa. **add** `intel-media-va-driver-non-free` (multiverse) for video decode. Hyprland should render on the iGPU (see hybrid note) |
| NVIDIA RTX 5070 Ti Mobile (GB205, **Blackwell**) | `nvidia-driver-595-open` + `linux-modules-nvidia-595-open-generic`, Secure Boot on, runtime power-down (`DynamicPowerManagement=3`) | Blackwell works **only** with the open modules, so the `-open` 595 row of the NVIDIA table is the only valid choice here. Nothing to decide |
| Audio: Intel SOF (`snd_sof_pci_intel_mtl`) | fine | **add** `firmware-sof-signed` and `alsa-ucm-conf`. Without the SOF firmware the internal speakers and mic don't work |
| Wi-Fi 7 + Bluetooth: Intel BE200 | `iwlwifi`, `btintel` | **add** `linux-firmware` (26.10 has 20260915) |
| Ethernet: Intel I226-V | `igc` | nothing |
| Thunderbolt 4 controller + a Titan Ridge TB3 bridge (inside the attached Apple Studio Display) | `thunderbolt` | **add** `bolt` (Thunderbolt device authorization; Omarchy ships it too) |
| **Apple Studio Display** (USB `05ac:1114`) | display works over TB | Omarchy already supports the Studio Display's brightness through `asdcontrol` (`bin/omarchy-brightness-display-apple`). `asdcontrol` **isn't in Ubuntu**, so package asdcontrol (small C tool; Omarchy gets it from the AUR). asdcontrol also needs a udev rule for the display's hidraw device (the raw USB HID interface its brightness is set through) |
| Lenovo platform (`ideapad_laptop`, `lenovo_wmi_gamezone`, other `lenovo_wmi_*`) | loaded | Performance/fan modes show up as the kernel's platform profile, which power-profiles-daemon and Omarchy's power panel use. Nothing to add |
| Keyboard RGB: ITE "Lenovo Lighting" (`048d:c193`) | no theming today | Omarchy only themes ASUS ROG and Framework 16 keyboards. Optional: `openrgb` is in universe. Check `openrgb --list-devices` sees this controller, then write a `theme-set-keyboard-legion` hook modeled on `bin/omarchy-theme-set-keyboard-asus-rog` |
| Internal display backlight | `intel_backlight` (0-496) is the real device, under the i915 `eDP-1` [connector](#drm-devices-and-connectors). The NVIDIA driver also registers a phantom `nvidia_0` (0-100) although the internal display isn't routed to the NVIDIA GPU, and the NVIDIA driver unregisters that device on suspend and registers a fresh one on every resume (found 2026-09-30, see `suspend-baseline.md`). Tools that take the first backlight device or rescale between devices set the wrong brightness; KDE's helper did exactly that on the current install | **add** `oaxaca-hybrid-backlight` (built in step 2): a udev rule starts a unit on every backlight device add, and its script shadows the phantom with an empty tmpfs, unless an eDP connector on the NVIDIA card is connected (MUX mode), so the hide holds across resume. Omarchy's `omarchy-hw-display` already prefers `intel_backlight`, so Omarchy's brightness keys and the monitor panel slider are right on their own; the hide protects every other writer. Re-check `omarchy-hw-display` on each Omarchy rebase: upstream moved backlight stepping into Omarchy's shell after v4.0.4 |
| FIDO2 security key (AuthenTrend ATKey.Pro, with a fingerprint sensor) | works; `sudo` uses it today through `pam_u2f.so` | systemd's built-in FIDO udev rule grants access. **add** `libfido2-1` for SSH use and, for `sudo` and polkit, `libpam-u2f` with `fido2-tools`, set up per machine by the ported `omarchy-setup-security-fido2` (policy, "Password login, no autologin", decided 2026-10-09). This is the "fingerprint" of this laptop: the sensor is on the key, not in the chassis |
| Built-in fingerprint reader | none found (2026-10-09: no USB device with a fingerprint vendor id or product string, the test `omarchy-hw-fingerprint` makes; `fprintd-list` reports no devices) | nothing for this laptop. Fingerprint support is a distro decision (policy, "Password login, no autologin"): `fprintd` and `libpam-fprintd` for `sudo`, polkit and the lock screen, set up per user by the ported `omarchy-setup-security-fingerprint` in step 6. Testing it needs a machine with a reader |
| Webcam (Syntek UVC), ambient light sensor (`hid_sensor_als`) | `uvcvideo`, loaded | nothing. `iio-sensor-proxy` is optional if you want auto-brightness |
| NVMe x2 (SK hynix P41) | `nvme` | nothing |
| Firmware updates | none | **add** `fwupd`. Check whether Lenovo publishes this model's BIOS on LVFS (the Linux firmware update service fwupd downloads from) |
| **Full-disk encryption** ([LUKS](#luks-and-plymouth) today) | not applicable | The installer ([Calamares](#image-and-installer-tools) or your own script) must set up LUKS. Add `cryptsetup-initramfs`, and use Omarchy's Plymouth theme for the unlock prompt |

**Hybrid graphics: browsers and games on the NVIDIA GPU.** Goal: games and the browser, including high-resolution video decode (for example 5K YouTube), run on the RTX 5070 Ti, while the desktop itself doesn't keep the dGPU awake.

*What Omarchy does by default (checked in v4.0.4):*
- **On a GSP-capable NVIDIA GPU, `default/hypr/nvidia.lua` sets three variables for the whole session.** `LIBVA_DRIVER_NAME=nvidia` + `NVD_BACKEND=direct` send **[VA-API](#va-api-and-nvdec) video decode** to NVIDIA's decoder (NVDEC) through `nvidia-vaapi-driver`. `__GLX_VENDOR_LIBRARY_NAME=nvidia` sends **GLX (X11 OpenGL) apps running under Xwayland** to NVIDIA.
- **Omarchy does not** set NVIDIA's [render-offload](#render-offload) variables (`__NV_PRIME_RENDER_OFFLOAD`), pick the compositor's GPU (`AQ_DRM_DEVICES`), or add GPU/VA-API flags to Chromium. `config/chromium-flags.conf` only sets Wayland, the password store and extensions.
- **Omarchy's only hybrid-laptop tooling** (`omarchy-toggle-hybrid-gpu`, `force-igpu`) drives `supergfxctl`, which is ASUS-only.
- So Omarchy's default gets you **NVIDIA video decode in apps that use VA-API**, but not deliberate dGPU rendering for browsers or native Wayland games. (Correction: an earlier draft of this plan said Omarchy's variables push *every* app to the dGPU. Those variables don't. Native Wayland EGL and Vulkan apps aren't affected by them.)

*Plan for this laptop:*
1. **Keep Omarchy's `nvidia.lua` variables unchanged.** Those variables are what routes video decode to NVDEC. The GLX line only affects Xwayland GLX apps, which on this laptop you want on the dGPU anyway.
2. **Browser:**
   - **Video decode** (the 5K YouTube case) goes through VA-API, which Omarchy already points at NVIDIA. The browser still has to be told to use VA-API. The `nvidia-vaapi-driver` README gives Chromium-based browsers `--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs --ignore-gpu-blocklist --use-gl=angle --use-angle=gl`, plus the Wayland ozone flag. Merge those flags into Omarchy's single `--enable-features=` line, because Chromium only honors the last `--enable-features=` it sees.
   - **Where the flags go:** reading `chromium-flags.conf` is an Arch wrapper feature. Ubuntu's snap Chromium and Google's Chrome deb don't read that file. Put the flags in a `.desktop` override (a copy of the browser's `.desktop` file in `/usr/local/share/applications/` with the flags on its `Exec=` line) or a small wrapper script, shipped in `oaxaca-config`.
   - **Firefox** is an alternative. `nvidia-vaapi-driver` was designed for Firefox; follow the driver README's `about:config` settings.
   - **Check** that Ubuntu's `nvidia-vaapi-driver` version includes the Chromium-compatible export path the driver README describes. If not, rebuild `nvidia-vaapi-driver` into your repo.
3. **Games:** add NVIDIA's render-offload variables (`__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia`) to Steam's launch command, and to Heroic's if you use it. Many Vulkan/DXVK games already pick the discrete GPU on their own; the variables make that choice certain.
*GPU monitoring tools:*
- **`nvidia-smi`: already included, nothing to add.** On this machine `nvidia-smi` comes from `nvidia-utils-595`, which `nvidia-driver-595-open` depends on. `nvidia-smi` is needed anyway for the verification steps below.
- **`btop` (already in Omarchy, and themed):** Omarchy ships `btop` with a theme template (`default/themed/btop.theme.tpl`), but Omarchy's `config/btop/btop.conf` shows only `cpu mem net proc`. Choice: add `gpu0 gpu1` to the `shown_boxes` line in your ported `btop.conf`, so the everyday resource monitor shows both GPUs and matches the theme. btop reads NVIDIA stats through NVIDIA's NVML library, which comes with the driver. Check whether the Intel iGPU also appears; if not, leave the config at the NVIDIA box.
- **`nvtop`: add as optional.** nvtop is in Ubuntu 26.10 **multiverse** (3.2.0), so enable that component too, or skip nvtop. nvtop is better than btop for per-process GPU use, for example checking that the browser's video decode is on NVDEC. Omarchy's templates don't theme nvtop. Rejected alternative: making nvtop the main resource monitor, because nvtop wouldn't match the theme.

4. **Compositor stays on the iGPU.** Set `AQ_DRM_DEVICES` (the environment variable Hyprland's backend reads to pick GPUs) with the Intel card first, as a `KEY=value` line in a file under `~/.config/environment.d/` or `/etc/environment.d/` (systemd's user manager reads those files, and [uwsm](#display-manager-and-uwsm) passes the result to Hyprland); `oaxaca-config` ships the `environment.d` files. Use the stable path `/dev/dri/by-path/pci-0000:00:02.0-card`, because `cardN` numbers can change between boots. All your displays are wired to the iGPU, so rendering on the iGPU avoids copying every frame across GPUs. Rendering on the iGPU also lets the dGPU power off when no game or browser is using it.
- **Tradeoff:** a browser left open with video playing keeps the dGPU awake, so battery life drops while it runs. That's the cost of wanting browser video on NVIDIA.
- **Alternative (not chosen): dGPU-only (MUX) mode** in the Legion BIOS / Legion Space. The internal display gets wired straight to NVIDIA, *everything* runs on the dGPU, and Omarchy's defaults work as-is. The catch: most battery drain, no dGPU power-off, and your Thunderbolt DP outputs (the Studio Display) currently run through the Intel iGPU, so those outputs may stop working in MUX mode. Test MUX mode before relying on it. MUX mode is worth it if this laptop mostly stays plugged in and docked.

### Sleep and resume on this machine

**What's already in your favor:**
- The firmware supports **[S3 "deep" sleep](#sleep-states)**, and deep sleep is the kernel's default choice here (`/sys/power/mem_sleep` shows `s2idle [deep]`). Deep sleep turns off almost everything and doesn't depend on every device handling modern standby.
- Ubuntu's NVIDIA packages already set up suspend correctly on this install:
  - `nvidia-suspend`, `nvidia-resume` and `nvidia-hibernate` are enabled.
  - `PreserveVideoMemoryAllocations=1` saves GPU memory across sleep, to `TemporaryFilePath=/var`.
  
  Those units and settings come with `nvidia-driver-595-open`, so the new distro gets them automatically. Verify the three units are enabled after install.

**What's missing or different:**
- **No baseline.** This machine's journal has no record of a suspend at all. Before building anything, test `systemctl suspend` on the current install (lid closed, and docked to the Studio Display). Then you'll know whether a later failure comes from the firmware or from your distro.
- **The NVIDIA driver re-creates its phantom backlight device across suspend.** `nvidia_0` disappears during `nvidia-suspend.service` and comes back as a new sysfs directory during `nvidia-resume.service`, which drops any mount or setting applied to the old directory. Anything that hides or configures `nvidia_0` must run on device add (udev), not only at boot. `oaxaca-hybrid-backlight` does exactly that; see "This machine".
- **Hibernation isn't available with Secure Boot on.** The kernel runs in lockdown `integrity` mode, and `/sys/power/disk` reads `[disabled]`. So don't port Omarchy's `omarchy-hibernation-*` scripts (they're also tied to Limine, [mkinitcpio](#initramfs) and btrfs) or suspend-then-hibernate. Choice, as first written: keep Secure Boot and drop hibernation; the rejected alternative, turning Secure Boot off to get hibernation, would also break the signed-NVIDIA-module setup. Superseded by the note below and `1 - policy.md`, section 5: hibernation is out of the first release for scope, in both Secure Boot settings.
- **Note (2026-09-30, revised 2026-10-01):** Secure Boot is off on this laptop and stays off, because the laptop dual-boots a Linux From Scratch system with an unsigned kernel, so today `/sys/power/disk` reads `[platform]` and lockdown is `[none]`. The distro supports Secure Boot without ever requiring it, and hibernation is out of the first release for scope rather than because of Secure Boot; see `1 - policy.md`, section 5. Secure Boot checks run in QEMU, with one laptop pass per release.
- **Space for GPU memory on sleep.** With `PreserveVideoMemoryAllocations`, used VRAM (up to the GPU's 12 GB) is written to `/var` on suspend. Keep that much free on the root filesystem, or point `TemporaryFilePath` at a bigger filesystem.

**What to port from Omarchy** (Omarchy has a thought-out lock-before-sleep design):
- **Anatomy:** `omarchy-sleep-lock.service` is a user unit that runs `omarchy-system-sleep-monitor`. That script takes a [logind](#logind-and-inhibitors) *delay inhibitor* (a short hold logind grants before sleeping) and listens for logind's `PrepareForSleep` signal. On that signal the monitor script calls `omarchy-system-sleep-lock`, which locks the Quickshell lock screen before the machine sleeps. The lid switch is bound in `default/hypr/bindings/utilities.lua` to `omarchy-system-lid-close`, which locks right away unless an external monitor is attached (clamshell mode).
- Port all of that unchanged into `oaxaca-config`/`oaxaca-tools`. That design depends only on systemd, logind and Hyprland.
- Keep the system-sleep hook `default/systemd/system-sleep/unmount-fuse` (Nautilus FUSE mounts can block suspend).
- Drop `force-igpu` and `keyboard-backlight`. Those two hooks are for ASUS laptops (`supergfxctl`, and ASUS keyboards during hibernate). Since 2026-10-16 `force-igpu` is back with the Hybrid GPU toggle on ASUS ROG laptops (`6 - omarchy-port.md`, choice 68); `keyboard-backlight` stays out with hibernation.
- Keep `omarchy-recover-internal-monitor.service`. That unit helps when the internal display doesn't come back after resume or undocking.

**Fallback if deep sleep misbehaves:** try `mem_sleep_default=s2idle` on the kernel command line (add it to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then run `update-grub`). Then check `/proc/driver/nvidia/params` for `EnableS0ixPowerManagement`, the NVIDIA driver's option for s2idle (currently `0`; set with an `options nvidia NVreg_EnableS0ixPowerManagement=1` line in a file under `/etc/modprobe.d/`). Change only one setting at a time, and log results.

## Roadmap (Option B)

1. **Decide policy.** Pick the distro name, the base series (26.10 now, LTS later), which Omarchy version you follow (follow a release tag such as v4.0.6 and merge each new one on purpose), and your package namespace (for example `oaxaca-*`).
2. **Build infrastructure** (done 2026-09-30, see `2 - build-infra.md`). Get a GPG signing key and an apt repo: either a Launchpad PPA, or a self-hosted `aptly`/`reprepro` repo on GitHub Pages or object storage. Build packages cleanly with `sbuild` or `pbuilder`. Set up CI to build the packages on every tag.
3. **Minimal root filesystem** (done 2026-10-07, see `3 - rootfs.md`; one deviation: netplan stays, because `stonking`'s `network-manager` depends on `netplan.io`, with NetworkManager as its renderer). Use `mmdebstrap --variant=minbase --components=main,universe stonking` (see "Exactly which Ubuntu base"), with the `-updates` and `-security` pockets added (see "Kernel and security updates"), plus Ubuntu's `linux-generic` kernel, systemd, `apparmor`, NetworkManager, PipeWire/WirePlumber, and a bootloader (GRUB is Ubuntu's default; Omarchy's Limine and Snapper setup is optional to port).
4. **Graphics/session layer.** Add Mesa, the NVIDIA install path (`restricted` component, `ubuntu-drivers-common`, `oaxaca-nvidia`; see "NVIDIA proprietary driver"), `xwayland`, `xdg-desktop-portal-hyprland` + `-gtk`, `uwsm`, and a display manager (Omarchy uses SDDM). Check that Xwayland apps (for example `xeyes`) run under Hyprland. *(done 2026-10-08, see `4 - session.md`. Deviations: `oaxaca-nvidia` ships no modprobe file, because Ubuntu's `nvidia-kernel-common-*` already carries `modeset=1`; it ships an initramfs hook instead of editing `/etc/initramfs-tools/modules`, because Ubuntu's own hook copies DKMS-built modules only; it depends on `nvidia-prime`; Omarchy's `nvidia.lua` and the `omarchy-hw-nvidia*` detectors move to step 6 with the rest of the Omarchy port. `xeyes` runs under Hyprland in the QEMU test. Added 2026-10-09: GNOME Keyring with its PAM module, as the secret store, because a session without one leaves desktop applications nowhere to keep credentials; Omarchy's passwordless keyring model is not followed, see choice 14 there.)*
5. **Hyprland + Quickshell.** Use the archive versions. If Omarchy's `hyprland.lua` or shell plugins need newer versions, backport Hyprland and its hypr* libraries and Quickshell into your repo. *(done 2026-10-09, see `5 - hyprland-quickshell.md`. Hyprland stays the archive's 0.56.2, the exact version Omarchy's recipe pins; Quickshell is backported as `quickshell 0.3.2-0oaxaca1` from Debian's packaging, because Omarchy builds 0.3.2 and the archive's 0.3.0 predates Quickshell's session lock crash fixes. `oaxaca-session` depends on it. The QEMU test runs Omarchy v4.0.4's own shell on it: IPC ping answered, bar on screen. Omarchy's `hyprland-preview-share-picker` is in neither Ubuntu nor Debian and joins step 6's packaging list.)*
6. **Port Omarchy into packages** (fork omacom/omarchy; MIT, keep the license). *(done 2026-10-10, see `6 - omarchy-port.md`. One source package `oaxaca-desktop` built from the `oaxaca` branch of `santisbon/omarchy`, renamed at build time, giving `oaxaca-desktop`, `-tools`, `-shell`, `-themes` and `-config` at `4.0.4-0oaxaca1`; `oaxaca-fonts`, `asdcontrol`, `hyprland-preview-share-picker`, `nwg-displays 0.4.4` and `oaxaca-hw-legion` beside them. Deviations from the list below: the shell, themes and config packages carry the paths of Omarchy's own two packages rather than the split sketched here; `oaxaca-config` seeds `/etc/skel` and ships no first-login copier, because Omarchy's own first-run does that; no browser is in the metapackage, see the document's choice 3; Omarchy's own applications are carried.)*
   - `oaxaca-themes`: `themes/`, `default/themed/*.tpl`, installed to `/usr/share/oaxaca/`.
   - `oaxaca-shell`: `shell/` (Quickshell plugins, including the `omarchy.menu` launcher; see "App launcher").
   - `oaxaca-config`: `config/`, `default/hypr`, `uwsm`, `environment.d`, `fontconfig`, `sddm`, delivered through `/etc/skel` or a first-login setup script.
   - `oaxaca-fonts`: Noto and Font Awesome come from the archive (`fonts-noto*`, `fonts-font-awesome`). JetBrains Mono Nerd and iA Writer aren't in Ubuntu, so repackage them (check their licenses).
   - `oaxaca-tools`: the `bin/omarchy-*` scripts, with `omarchy-pkg-*` rewritten for apt and the pacman/AUR/Limine-only ones dropped. Rename the branding (see below). Among them the fingerprint scripts (`omarchy-hw-fingerprint`, `omarchy-setup-security-fingerprint`, `omarchy-remove-security-fingerprint`, and the first-run invitation hook), and the FIDO2 scripts (`omarchy-setup-security-fido2`, `omarchy-remove-security-fido2`). Their package installs (`pacman -S libfprint-git fprintd usbutils`, `omarchy-pkg-add libfido2 pam-u2f`) and the removal scripts' uninstalls are dropped: the packages are dependencies of `oaxaca-desktop` (below), so the ported scripts only enroll or register and write or strip the PAM lines, and work offline; the PAM lines they write stay per service (`sudo`, `polkit-1`, the lock screen), never in `common-auth` (policy, "Password login, no autologin", decided 2026-10-09).
   - `nwg-displays` (≥0.4.3, rebuilt into your repo; see "System settings UI").
   - `asdcontrol` + its udev rule (Apple Studio Display brightness), `oaxaca-hybrid-backlight` (the phantom-backlight hide, already built in step 2 as the pipeline's second package), and `oaxaca-hw-legion`, a hardware package that pulls in the **add** items for this laptop (see "This machine"), including the hybrid-graphics env change and a dependency on `oaxaca-hybrid-backlight`.
   - `oaxaca-desktop`: a meta-package that pulls in everything above plus the apps you want from Omarchy's package list, mapped to Ubuntu names. Also `fprintd`, `libpam-fprintd`, `libpam-u2f` and `fido2-tools`, always installed (decided 2026-10-09): they are small and inert until a PAM line names them (`libpam-fprintd`'s `pam-auth-update` profile is `Default: no`, `libpam-u2f` adds no PAM line by itself, `fprintd` is a D-Bus activated service that idles), and installing them here instead of on demand, as Omarchy's setup scripts do, means the fingerprint and FIDO2 setup needs no network and the removal needs no apt. Rejected: on-demand `apt install` inside the setup scripts.
7. **Image and installer.** Use `mkosi` for quick VM/disk images during development. For a bootable installer ISO, use live-build or a Calamares-based ISO. Both tools are choices, not requirements. *(started 2026-10-10, see `7 - image-installer.md`: a live ISO on Ubuntu's casper with Calamares from Ubuntu's archive, booted through Ubuntu's signed shim and GRUB, built by `scripts/iso-create.sh` with xorriso; neither mkosi nor live-build, for the reasons in that document's choice 1; the QEMU boot test runs under OVMF with Secure Boot on and off. On 2026-10-11 the first hand-run install with encryption, on the Legion laptop, failed in KPMcore's cryptsetup call; Ubuntu's kpmcore is rebuilt with one patch, that document's choice 11.)*
8. **Update path.** Test `apt full-upgrade` from release N to N+1 in CI, and port Omarchy `migrations/` into your packages' `postinst` scripts or a user-level migration runner. *(done 2026-10-11, see `8 - update-path.md`: the upgrade test runs in CI against the published archive; migrations stay user-level through the ported runner, with the branch carrying only the port's own; the step also found and fixed two silent bugs, the unattended-upgrades origins and the migrations runner's wait.)*

**Branding note:** Omarchy's code is MIT, but the Omarchy name is a trademark ("Omarchy™. All rights reserved." on omarchy.org/foundation, the Omacom Foundation's page) and the MIT license covers only the code. Rebrand the scripts, the logo and the Plymouth theme so your distro isn't mistaken for Omarchy.

## Verification (when building)

- Boot the image in QEMU/virt-manager: SDDM starts a Hyprland session through uwsm, and the Quickshell bar and menus come up.
- `omarchy-theme-set tokyo-night` (or your renamed command) switches the Hyprland, terminal and shell colors live. Repeat for a light theme.
- `aa-status` shows profiles loaded. Chromium and Obsidian start with their sandboxes on (no `--no-sandbox` needed), and `journalctl -k | grep DENIED` stays clean during normal use.
- On NVIDIA hardware, with Secure Boot **on** (once per release on this laptop, which runs with it off day to day for the LFS dual boot; everything below must also pass with it off):
  - `mokutil --sb-state` reports enabled, and `ubuntu-drivers install` picks the `-open` 595 branch on a Turing+ card and 580 on a Pascal card.
  - `nvidia-smi` works, and `/sys/module/nvidia_drm/parameters/modeset` reads `Y`.
  - `hyprctl systeminfo` shows the NVIDIA GPU, and `glxinfo -B` inside Xwayland reports the NVIDIA renderer.
  - Suspend/resume keeps the session alive.
- `Super + Alt + Space` lists an app you just installed with apt, and launches that app. `Super + Space` has no leftover pacman/AUR entries. After a theme switch, the launcher's colors change along with the bar's.
- Settings: the Bluetooth panel finds and connects a device, the Wi-Fi panel joins a network, and the audio panel switches outputs. nwg-displays rearranges two monitors, the layout survives a Hyprland restart, and `GDK_SCALE` is still set.
- This laptop, before building anything: run `systemctl suspend` on the current install, with the lid open, the lid closed, and docked to the Studio Display, to set a baseline. **Done 2026-09-30, three of three passed; see `suspend-baseline.md`.**
- This laptop, on the new distro:
  - **Sleep:** 10 suspend/resume cycles each on battery, on AC, and docked. The session locks before sleep, and the internal display, Studio Display, Wi-Fi, Bluetooth and audio all come back. `journalctl -b -k -g 'PM: suspend (entry|exit)'` shows matched entry/exit pairs. `nvidia-smi` works after resume.
  - **Hybrid graphics:**
    - At idle with no browser or game open, `cat /sys/bus/pci/devices/0000:02:00.0/power/runtime_status` reads `suspended`, meaning the dGPU is off.
    - Playing a 5K YouTube video: `nvidia-smi` shows the browser process, and `chrome://gpu` shows hardware video decode enabled.
    - A game launched through Steam appears in `nvidia-smi`.
  - **Hardware:** internal speakers and mic work (SOF firmware), and Studio Display brightness keys work (`asdcontrol`).
  - **Brightness:** `cat /sys/class/backlight/nvidia_0/type` fails (the phantom is hidden) after boot and again after a resume, and `journalctl -t hide-phantom-backlight` shows a run at each. `omarchy-hw-display` prints `intel_backlight`. Brightness keys and the monitor panel slider change `intel_backlight/brightness`, the [OSD](#osd) percentage matches `brightness/max_brightness`, and a dim-then-wake cycle restores the set value.
- **Updates:** `apt policy linux-generic` on an installed system lists `stonking-security` and `stonking-updates` as sources. After Canonical publishes a kernel update, `apt upgrade` installs the new kernel along with the matching `linux-modules-nvidia-*`, and the machine boots that kernel with Secure Boot on.
- An Xwayland app runs (`xeyes`; `hyprctl clients` shows `xwayland: 1`).
- `apt install oaxaca-desktop` on a clean minbase root filesystem pulls in everything with no missing dependencies.
- A test upgrade from the previous build keeps user configs.
