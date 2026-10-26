# Minimal root filesystem (roadmap step 3)

Built 2026-10-07. This document covers what roadmap step 3 of [plan.md](0%20-%20plan.md) asks for: a [root filesystem](#root-filesystem) built with `mmdebstrap --variant=minbase` from the `stonking` archive with the `-updates` and `-security` [pockets](README.md#suite-and-pocket), plus Ubuntu's `linux-generic` kernel, systemd, AppArmor, NetworkManager, PipeWire with WirePlumber and the GRUB and shim packages. The step produces two things: the [metapackage](README.md#metapackage) `oaxaca-base`, which names everything the base system needs, and a tarball of the root filesystem with that metapackage installed. A QEMU boot test proves the tarball's kernel and services come up. Every decision below is a choice with reasons and a rejected alternative, not a vendor best practice, unless a source is cited.

## Terms

Each entry uses only terms defined above it, in the developer README's [Terms](README.md#terms), in the plan's [Terms](0%20-%20plan.md#terms) or in the policy's [Terms](1%20-%20policy.md#terms). The first use of each term in the rest of this document links to its entry.

### Root filesystem

The directory tree a Linux system boots from: `/usr`, `/etc`, `/var`, `/boot` and the rest, with every file dpkg installed. A root filesystem is not yet an [image](1%20-%20policy.md#image): it has no partition table, no boot partition and no bootloader written anywhere. This step stores the root filesystem as a tar archive, `build/rootfs/oaxaca-26.10-amd64-base.tar`, which the image step (roadmap step 7) will unpack onto a disk.

### Manifest

A text file next to the tarball, `build/rootfs/oaxaca-26.10-amd64-base.manifest`, listing every installed package and its version, one per line, as `dpkg-query -W` prints them. The manifest is the answer to "what exactly is in this build" without unpacking the tarball.

### Diversion

dpkg's mechanism for letting one package replace a file that another package owns. `dpkg-divert --add --rename` records that file `A` from package X is to live at `A.ubuntu` instead, and renames the installed copy; the diverting package then installs its own `A`. dpkg keeps honouring the record on every later upgrade of X, so X's file keeps landing at `A.ubuntu`. `dpkg-divert --remove` undoes the record. The `oaxaca-base` package diverts `/usr/lib/os-release`, which the `base-files` package owns (see the policy's [os-release](1%20-%20policy.md#os-release) term).

### debconf and preseeding

debconf is the question-and-answer system Debian packages use at install time (which locale to generate, which time zone). A preseed is a set of answers given before the questions are asked, as lines of `<package> <question> <type> <value>` fed to `debconf-set-selections`, so a non-interactive install gets the answers you chose instead of the defaults. The root filesystem build preseeds the locale and the time zone.

### netplan

Ubuntu's network configuration layer: YAML files under `/etc/netplan/` that netplan turns into configuration for one of two back ends, called renderers: systemd-networkd or NetworkManager. In `stonking`, the `network-manager` package depends on `netplan.io` (fact table below), so netplan is present on every system with NetworkManager. A netplan file whose only content is `renderer: NetworkManager` hands every interface to NetworkManager and makes netplan generate nothing for systemd-networkd.

### Stub resolver

`systemd-resolved`'s local DNS listener on `127.0.0.53`. Ubuntu points `/etc/resolv.conf` at the stub resolver through the symlink `/etc/resolv.conf -> ../run/systemd/resolve/stub-resolv.conf`, and NetworkManager hands the DNS servers it learns to `systemd-resolved`. The root filesystem build creates that symlink in place of the `resolv.conf` that mmdebstrap copies from the build host.

### Subordinate uids

The range of user ids that `/etc/subuid` grants an unprivileged user for use inside a user namespace (see [unshare mode](2%20-%20build-infra.md#unshare-mode)). mmdebstrap's unshare mode maps the root user inside the namespace to your own user and the rest of the namespace's users to subordinate uids. apt inside that namespace runs as one of those subordinate uids, which is why a `.deb` file apt must read has to be readable by everyone, not just by you.

### Direct kernel boot

QEMU's `-kernel` and `-initrd` options load a kernel and an [initramfs](1%20-%20policy.md#initramfs) straight from files on the host, with the kernel command line given by `-append`. No firmware, bootloader, partition table or boot partition is involved, so a direct kernel boot tests the root filesystem's kernel, initramfs and services while leaving the boot chain to the image step.

### KVM

The kernel's hardware virtualization interface, `/dev/kvm`. With `-enable-kvm`, QEMU runs the guest's instructions on the CPU directly instead of emulating them, and a boot that would take minutes under emulation takes seconds. On this workstation an access control list on `/dev/kvm` grants the logged-in user read and write access, so the boot test needs no root privileges.

### Oneshot unit

A [systemd unit](0%20-%20plan.md#udev-rules-and-systemd-units) with `Type=oneshot`: systemd runs its `ExecStart` command once and the unit is done when that command exits. The boot test injects a oneshot unit, wanted by `multi-user.target`, that runs the checks and powers the guest off.

## Anatomy

Three `make` targets, each running one script, each script driving one tool:

*Since step 4 the root filesystem script takes a profile: `make rootfs PROFILE=base` builds the tarball this document describes, `make rootfs` alone builds the newest layer (`session`, see [4 - session.md](4%20-%20session.md#profile)), and the tarball names carry the profile as a suffix. The names below are the current ones.*

| You run | Script | Tool underneath | Result |
|---|---|---|---|
| `make build PKG=packages/base` | `scripts/build.sh` | `sbuild` and `lintian`, as in [build-infra.md](2%20-%20build-infra.md#anatomy) | `build/oaxaca-base_0.1.0_all.deb`, the base metapackage: a dependency list plus three files (table under "Files inside the root filesystem") |
| `make rootfs` | `scripts/rootfs-create.sh` | `mmdebstrap` in unshare mode | `build/rootfs/oaxaca-26.10-amd64-base.tar`, the root filesystem tarball, and its [manifest](#manifest). mmdebstrap installs the `minbase` variant from the Ubuntu archive, then the three `.deb` files of ours from `build/` (`oaxaca-archive-keyring`, `oaxaca-apt-source`, `oaxaca-base`); the base metapackage's dependency list pulls in the kernel and the rest from the archive; hooks write the hostname, `hosts`, the resolver symlink, apt's `ubuntu.sources` and the manifest |
| `make rootfs-test` | `scripts/rootfs-boot-test.sh` | `tar`, `mke2fs -d` inside `unshare`, then `qemu-system-x86_64` with [KVM](#kvm) | the tarball's kernel and initramfs pulled out with `tar`, the tarball unpacked and turned into a raw ext4 disk image with a [oneshot unit](#oneshot-unit) injected, and a [direct kernel boot](#direct-kernel-boot) of that image with the serial console logged to `build/rootfs/boot-test/serial.log`. The script prints the checks' output and exits non-zero if any check failed |

The order is `make build` (all packages, or just `PKG=packages/base`), then `make rootfs`, then `make rootfs-test`. `make rootfs` refuses to run without the three `.deb` files in `build/`.

## What the base metapackage pulls in

`oaxaca-base` is a metapackage: a `Depends:` line that names the base system, plus files of its own (`/usr/lib/os-release`, apt's pins for two blocked Recommends, the netplan file and the loader fallback; see [Files inside the root filesystem](#files-inside-the-root-filesystem)). The names are Ubuntu's; apt resolves each to its [dependency closure](README.md#build-dependencies).

| Group | Packages | Why these |
|---|---|---|
| Boot chain | `linux-generic`, `initramfs-tools`, `grub-efi-amd64-signed`, `shim-signed`, `secureboot-db`, `efibootmgr` | Ubuntu's signed kernel, GRUB and shim, so the policy's "Secure Boot supported, never required" holds without a MOK. `linux-generic` as the plan says, which brings the headers along with the image; `linux-image-generic` in `stonking` depends on `linux-firmware`, `intel-microcode` and `amd64-microcode`, so firmware and microcode arrive with the kernel. `secureboot-db` is shim's Recommends, carrying the UEFI revocation list; with Recommends off it has to be named |
| Encrypted root | `cryptsetup-initramfs` | the policy's full-disk encryption requirement: the initramfs can unlock a LUKS root. Plymouth, for the passphrase prompt with a theme, comes with the image step |
| Init, buses, policy | `systemd-sysv`, `udev`, `kmod`, `dbus-broker`, `dbus-user-session`, `libpam-systemd`, `polkitd` | systemd as PID 1, a system bus (`dbus-broker` is what provides `default-dbus-system-bus` in `stonking`; the `dbus` package itself sits in universe), a user bus for PipeWire and the later portals, logind sessions through PAM, and polkit for NetworkManager's per-user permissions |
| Network | `network-manager`, `wpasupplicant`, `wireless-regdb`, `systemd-resolved`, `systemd-timesyncd`, `netbase`, `iproute2`, `iputils-ping`, `ca-certificates` | NetworkManager as the plan says, with Wi-Fi (`wpasupplicant` and the regulatory database are NetworkManager's Recommends, so they must be named), DNS through the [stub resolver](#stub-resolver), time sync, and TLS roots so apt and curl can reach HTTPS repositories |
| Sound | `pipewire-audio`, `alsa-ucm-conf`, `alsa-topology-conf`, `firmware-sof-signed` | `pipewire-audio` is Ubuntu's metapackage for PipeWire as the sound server: `pipewire-pulse`, `pipewire-alsa`, WirePlumber and the Bluetooth plugin. The ALSA configuration files and the signed Sound Open Firmware are what laptop speakers and microphones need, this laptop included (plan, "This machine") |
| Security | `apparmor` | the user-space half of AppArmor, so the profiles other packages ship get loaded (plan, "AppArmor") |
| Administration | `sudo`, `locales`, `tzdata`, `kbd`, `console-setup`, `less`, `e2fsprogs`, `dosfstools` | a working console, locale generation, `fsck` for ext4 and for the FAT boot partition |
| Ours | `oaxaca-archive-keyring`, `oaxaca-apt-source` | every base system trusts and lists the Oaxaca apt repository |

Not in the base, on purpose: a text editor, `curl`, Bluetooth's `bluez`, `thermald`, `unattended-upgrades`. Those belong to the desktop and hardware packages of roadmap step 6, or stay optional.

## Files inside the root filesystem

Three come from the `oaxaca-base` package and the rest are written by `scripts/rootfs-create.sh` through mmdebstrap hooks. The split follows Debian policy as lintian enforces it: apt preferences are the administrator's, so a package may not ship them, while apt configuration under `apt.conf.d` may be shipped.

| Path in the root filesystem | Written by | Content |
|---|---|---|
| `/usr/lib/os-release` | `oaxaca-base`, through a [diversion](#diversion) of `base-files`' copy to `/usr/lib/os-release.ubuntu` | `NAME="Oaxaca"`, `ID=oaxaca`, `ID_LIKE="ubuntu debian"`, `VERSION_ID="26.10"`, `VERSION_CODENAME=stonking`, `UBUNTU_CODENAME=stonking`, the home and bug URLs from `distro.conf`. `/etc/os-release` stays `base-files`' symlink to this path |
| `/etc/apt/preferences.d/oaxaca-blocked-recommends` | `oaxaca-base` | apt pins (`Pin-Priority: -1`) for `xdg-desktop-portal-gnome` and `sudo-rs`, the two Recommends kept out (choice 4). Until `oaxaca-base` 0.1.6 (2026-10-14) this row was `/etc/apt/apt.conf.d/50oaxaca-no-recommends`, `APT::Install-Recommends "false";` |
| `/etc/netplan/01-oaxaca-network-manager.yaml` | `oaxaca-base`, mode 0600 | `renderer: NetworkManager` (see [netplan](#netplan)) |
| `/etc/apt/sources.list.d/ubuntu.sources` | `scripts/rootfs-create.sh` | the deb822 stanzas below. mmdebstrap writes two files of its own into the chroot, `/etc/apt/sources.list` (the one-line form of the mirror arguments on its command line) and `/etc/apt/apt.conf.d/99mmdebstrap` (the build-time `Install-Recommends` setting), and the build deletes both, so no setting of the build tool survives into the installed system. The complete list of apt files in the tarball follows the table |
| `/etc/hostname`, `/etc/hosts` | `scripts/rootfs-create.sh` | `oaxaca`, and the loopback lines for it. mmdebstrap would otherwise copy the build host's hostname |
| `/etc/resolv.conf` | `scripts/rootfs-create.sh` | the symlink to the [stub resolver](#stub-resolver), replacing the build host's `resolv.conf` that mmdebstrap copies in |
| `/etc/machine-id` | mmdebstrap's cleanup | empty, so every installed system generates its own id at first boot |
| locale and time zone | debconf [preseed](#debconf-and-preseeding) in an essential hook | `en_US.UTF-8` generated and set as the default, time zone `Etc/UTC`. The installer (roadmap step 7) asks the user and overrides both |

Every file under `/etc/apt` in the tarball built on 2026-10-07, and which package or script put it there, from `tar -tf build/rootfs/oaxaca-26.10-amd64-base.tar ./etc/apt`:

| File under `/etc/apt` | Owner | Role |
|---|---|---|
| `apt.conf.d/01-vendor-ubuntu`, `apt.conf.d/01autoremove` | Ubuntu's `apt` package | Ubuntu's defaults: `Acquire::Changelogs::AlwaysOnline "true"` plus a non-interactive User-Agent setting, and the list of package patterns (kernels among them) that `apt autoremove` never removes |
| `apt.conf.d/70debconf` | Ubuntu's `debconf` package | makes apt pre-ask debconf questions before unpacking |
| `preferences.d/oaxaca-blocked-recommends` | `oaxaca-base` | the two blocked Recommends (row above) |
| `sources.list.d/ubuntu.sources` | `scripts/rootfs-create.sh` | the Ubuntu archive (row above) |
| `sources.list.d/oaxaca.sources` | `oaxaca-apt-source` | the Oaxaca repository ([build-infra.md](2%20-%20build-infra.md)) |
| `keyrings/oaxaca-archive-keyring.gpg` | `oaxaca-archive-keyring` | the public key `oaxaca.sources` names in `Signed-By` |
| `trusted.gpg.d/ubuntu-keyring-2018-archive.gpg` | Ubuntu's `ubuntu-keyring` package | the key that verifies the Ubuntu archive |

The `ubuntu.sources` file as the build writes it on 2026-10-07, in deb822 format, the same two-stanza layout Ubuntu's own installer writes (archive mirror for the release and `-updates` pockets, security mirror for `-security`):

```
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: stonking stonking-updates
Components: main restricted universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: stonking-security
Components: main restricted universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

## Choices

1. **A metapackage names the base, not a package list inside the script.** `oaxaca-base` is a real package in the apt repository, so an installed system can be checked (`apt policy oaxaca-base`) and updated: adding a package to the base later means a new `oaxaca-base` version that every system picks up on `apt upgrade`. A list inside `scripts/rootfs-create.sh` would only reach systems built after the change. Rejected: `--include=` with the whole list.
2. **The system's identity comes from a diversion of `/usr/lib/os-release`, and `/etc/lsb-release` stays Ubuntu's.** `base-files` owns both files. Diverting one file is the dpkg-sanctioned way for a package to replace another package's file, survives every `base-files` update, and is undone cleanly on removal. `lsb_release`, which `ubuntu-drivers`, `add-apt-repository` and third-party install scripts call, keeps reporting `Ubuntu` and the `stonking` codename, so those tools keep working. **Correction, 2026-10-11 (step 8):** that sentence was wrong for the `Ubuntu` half. stonking's `lsb-release 12.1-2build1` ships `lsb_release` as a shell script that reads `/etc/os-release`, so on an Oaxaca system `lsb_release -is` prints `Oaxaca` (verified by running stonking's script against the live tarball's `os-release`); the codename stays `stonking`. `base-files` in stonking ships no `/etc/lsb-release` at all. The one consumer that broke is `unattended-upgrades`, whose allowed origins are built from `lsb_release -i -s`; `oaxaca-base 0.1.1` repairs that with an apt configuration file, see [docs/8 - update-path.md](8%20-%20update-path.md). `ubuntu-drivers` was verified in step 4 and reads apt's `Origin` field, not `lsb_release`. Users see Oaxaca where `os-release` is read: the login banner, `hostnamectl`, fetch tools, the Omarchy shell. Rejected: rebuilding `base-files`, which would mean carrying a fork of a core package across every Ubuntu update of it. Rejected: also diverting `/etc/lsb-release`, which buys consistency at the cost of the tool compatibility the policy asks step 3 to verify. The `ubuntu-drivers` check itself waits for step 4, when the NVIDIA packages arrive.
3. **netplan stays, with NetworkManager as its renderer.** The plan expected to skip netplan. In `stonking` the `network-manager` package depends on `netplan.io`, so netplan cannot be skipped without rebuilding NetworkManager. The one-line netplan file turns netplan into a pass-through. Rejected: a rebuilt `network-manager` without the dependency, for the same fork cost as above.
4. **Recommends on, except two packages kept out by apt pins (changed 2026-10-14, `oaxaca-base` 0.1.6).** mmdebstrap gets `--aptopt='APT::Install-Recommends "true"'` and a setup hook that puts `packages/base/apt-blocked-recommends.pref` in place before apt resolves anything; `oaxaca-base` installs the same pins as `/etc/apt/preferences.d/oaxaca-blocked-recommends`, so installs after first boot behave like the build. The pins (`Pin-Priority: -1`, never install) keep out `xdg-desktop-portal-gnome`, which Files recommends and which recommends `gnome-shell` (GNOME Shell, `gdm3`, the Ubuntu GNOME session, IBus), and `sudo-rs`, which `sudo` recommends and whose `/usr/bin/sudo` alternative (priority 50, in `sudo-rs 0.2.14-1ubuntu4`'s postinst) outranks classic sudo's (40, `sudo 1.9.17p2-7ubuntu5`), while the menus' sudoers rules need classic sudo. A customize hook fails the build if `gnome-shell`, `gdm3`, the GNOME portal or `sudo-rs` got in anyway.
   *History.* Until 2026-10-14 Recommends were off at build time and in the installed system (`50oaxaca-no-recommends`), to keep GNOME and KDE pieces out. Every test round then found another package a stock Ubuntu gets through Recommends (the TPM tools, `rtkit`, `usbmuxd`, `steam-devices`, printer discovery; docs/7 choice 47). Measured on 2026-10-14 against the live image (1280 packages, 4175 MB installed): its installed packages left 89 Recommends unsatisfied; apt's simulation of installing them added 464 packages, 1519 MB installed (521 MB of `.deb` files), of which 622 MB came from the GNOME portal alone; with the two pins, 327 packages, 978 MB installed (295 MB of `.deb` files), and nothing from GNOME Shell or Plasma (SDDM's theme Recommends resolves to `budgie-sddm-theme`, 18 MB, under apt 3.2 and 3.3's default solver). Rejected: keeping Recommends off and naming each missing package, which kept costing a test round per package; and Recommends on with no pins, which brings GNOME Shell with `gdm3` and replaces `sudo`. The packages our metapackages already name in place of Recommends stay named.
5. **Components `main restricted universe` in the image's sources; `multiverse` off.** `restricted` is where the NVIDIA driver lives (step 4), so listing it now avoids editing the sources file then. `multiverse` holds software with licensing restrictions we have no package from. The build itself fetches from the same three components. Rejected: Ubuntu's default of all four, because nothing we install comes from `multiverse`.
6. **The tarball is the artifact; the boot test makes its own disk image.** A tar archive is what the image tools of step 7 consume, mmdebstrap writes it without root privileges (unshare mode, see [subordinate uids](#subordinate-uids)), and a tar archive keeps file ownership. The boot test unpacks it inside a user namespace, so files owned by the root user keep that ownership, and `mke2fs -d` builds a raw ext4 image from the unpacked tree, again without root privileges. Rejected: `mmdebstrap --format=ext4` as the artifact, which would make the tarball a second build. Rejected: `systemd-nspawn` as the test, which needs root privileges and skips the kernel and initramfs.
7. **Direct kernel boot in the test, no bootloader yet.** The question step 3 has to answer is whether the kernel, initramfs, systemd, AppArmor, NetworkManager and apt come up on the packages chosen. A direct kernel boot answers that with the tarball's own kernel and initramfs. Partitioning, GRUB, shim and the policy's Secure Boot boot in OVMF belong to the image step, where there is a disk to install them on. Rejected: building a bootable disk image already in step 3.
8. **Our three packages enter the build as local `.deb` files from `build/`, not from the published apt repository.** `make rootfs` then works on a branch before anything is published, and the installed system still gets the repository through `oaxaca-apt-source`. The staging copy under `/tmp` exists because the home directory's mode 0750 blocks the [subordinate uid](#subordinate-uids) apt runs as. Rejected: `--include=oaxaca-base` from the published repository, which would force a publish before every rootfs test.
9. **`linux-generic`, headers included.** The plan names it, and it is what Ubuntu installs. The headers cost disk and are only needed by DKMS, which the policy keeps as a fallback. Revisit as `linux-image-generic` if image size matters later.
10. **One apt package cache, `build/apt-cache/`, shared by every mmdebstrap run of `scripts/rootfs-create.sh` and `scripts/upgrade-test.sh` (added 2026-10-22).** `make release` installs Ubuntu's packages four times: the desktop, live and published desktop root filesystems, then the upgrade test's chroot. Each install downloaded every package again, because mmdebstrap keeps no cache between runs. On 2026-10-22 the three root filesystems held 1547, 1645 and 1544 packages from Ubuntu's archive, about 2 GB each (summed from the `Size:` fields of that day's `stonking` indexes), and one desktop build's apt reported `Fetched 2169 MB in 5min 43s (6320 kB/s)`. Both scripts now give mmdebstrap three hooks from its manual's own example:
    - a setup hook, `sync-in build/apt-cache /var/cache/apt/archives/`, which copies the cache into the chroot before apt downloads anything;
    - a last customize hook, `sync-out /var/cache/apt/archives build/apt-cache`, which copies the chroot's archives back out before mmdebstrap's cleanup empties them, so no `.deb` file reaches the tarball;
    - `--skip=essential/unlink`, without which mmdebstrap deletes the essential packages' files once dpkg has installed them.

    apt downloads only the files the cache lacks, so the build installs the same versions with or without the cache. apt reuses a cached file whose name (package, version and architecture) and size match the index, and does not check the cached file's hash (`apt-pkg/acquire-item.cc`, "Check if we already downloaded the file", Debian's apt repository read on 2026-10-22; the workstation runs apt 3.3.3). Every file in the cache is one that apt downloaded and checked against the index's hash itself, and only the scripts write to `build/apt-cache/`. A cached file changed on disk without changing its size would be installed unchecked, so after a disk error, `rm -rf build/apt-cache` resets the cache. After each run, `scripts/apt-cache-prune.sh` keeps only the newest version of each package (dpkg's version order, read from apt's file names), so the cache stays the size of one install plus the packages that only the live profile and the upgrade test install. Measured on 2026-10-22 on the workstation, with `/tmp` as mmdebstrap's temporary directory as in a release:
    - a desktop build with an empty cache took 221 s, and the same build with the cache filled took 125 s;
    - a verbose rerun of the warm build printed `Need to get 0 B/29.9 MB of archives.` for the essential packages and `Need to get 0 B/2313 MB of archives.` for the rest;
    - the upgrade test then took 146 s with the cache;
    - the cache held 1676 files, 2.3 GB, after the desktop build and the upgrade test;
    - `/tmp` peaked at 8061 MB.

    The download time varies with the archive's speed: the cold build above downloaded faster than the same build an hour earlier, so the saving per build is between about 100 s and the 5 min 43 s that run's download took. `make clean` deletes the cache with the rest of `build/`.

    Rejected:
    - **A bind mount of `build/apt-cache/`** onto the chroot's `/var/cache/apt/archives/`, which would skip both copies: apt in the chroot runs as a [subordinate uid](#subordinate-uids), which cannot enter a home directory of mode 0750 (choice 8). mmdebstrap's own process, running as the user, does the `sync-in` and `sync-out` copies.
    - **apt-cacher-ng, a caching proxy daemon,** which mmdebstrap's manual names first ("If, for some reason, you cannot use a caching proxy like apt-cacher or apt-cacher-ng, you can use the sync-in and sync-out special hooks"). Pointing `UBUNTU_MIRROR` at the proxy would write the proxy's address into the image's `/etc/apt/sources.list.d/ubuntu.sources`, so the proxy would have to be apt's `Acquire::http::Proxy` instead. The proxy also cannot cache the two https sources, the xtradeb PPA (Chromium) and mise's repository, and it adds a service that listens on all interfaces by default and must be set up on every build workstation.

## Running it

```
make build                 # all packages, lintian clean, into build/
make rootfs PROFILE=base   # build/rootfs/oaxaca-26.10-amd64-base.tar and .manifest
make rootfs-test PROFILE=base   # boots that tarball in QEMU, prints the checks
```

`make rootfs` downloads the packages from the Ubuntu archive every run; mmdebstrap keeps no cache. `make rootfs-test` leaves nothing behind on success; `KEEP=1 make rootfs-test` keeps `build/rootfs/boot-test/` with the kernel, initramfs, ext4 image and `serial.log` for a look. `QEMU_TIMEOUT` (seconds, default 600) and `QEMU_MEM` (MiB, default 2048) are the other knobs.

What the test checks inside the guest, and the line each check must print: `system: running` from `systemctl is-system-running --wait`, `failed units: []`, the `os-release` line with `PRETTY_NAME=Oaxaca 26.10 ID=oaxaca ID_LIKE=ubuntu debian VERSION_CODENAME=stonking`, `unit apparmor: active`, `unit NetworkManager: active`, `unit systemd-resolved: active`, `network: connected` from `nmcli general` on QEMU's user-mode network, `apt update: ok` against both the Ubuntu archive and the Oaxaca repository (which also proves the installed keyring verifies our `InRelease`), an `oaxaca-base candidate:` line, and a `snapd candidate:` line with a version.

## Verified on 2026-10-07

All on the Legion laptop, then running Kubuntu 26.04.1 (24 CPUs, KVM), with the archive mirror delivering around 1 MB/s that afternoon.

- `make build PKG=packages/base`: the metapackage builds in the clean chroot, lintian quiet. The `.deb` installs three files besides its docs: `/usr/lib/os-release`, `/etc/apt/apt.conf.d/50oaxaca-no-recommends` and `/etc/netplan/01-oaxaca-network-manager.yaml` (mode 0600). The package's preinst and postrm maintainer scripts, which add and remove the diversion, ride in the `.deb`'s control archive and are not installed as files.
- `make rootfs`: 8 min 56 s, 1.6 GB tarball, 325 packages in the manifest. Inside the tarball: kernel `7.3.0-9-generic` with its initramfs under `/boot`, `oaxaca-base 0.1.0`, `network-manager 1.58.1-1ubuntu3` with `netplan.io 1.2.2-3`, `apparmor 6.0.0~alpha1-0ubuntu4`, `pipewire 1.6.8-1ubuntu4` with `wireplumber 0.5.17-1ubuntu1`, `shim-signed 1.59+15.8-0ubuntu2`, `grub-efi-amd64-signed 1.215+2.14-2ubuntu1`, `dbus-broker 37-5ubuntu5`. The hook-written files read as designed: `hostname` is `oaxaca`, `resolv.conf` is the stub-resolver symlink, `ubuntu.sources` is the two-stanza file shown above, `/etc/locale.conf` (which `/etc/default/locale` now links to) holds `LANG=en_US.UTF-8`, `/etc/localtime` points at `Etc/UTC`, `/etc/machine-id` is empty. dpkg's diversion table lists `/usr/lib/os-release` diverted to `/usr/lib/os-release.ubuntu` by `oaxaca-base`, and that `.ubuntu` file still says `Ubuntu Stonking Stingray (development branch)`.
- `make rootfs-test`: the guest boots the tarball's kernel and initramfs, systemd reaches `multi-user.target`, and the checks print, in the guest's own words:
  ```
  kernel: 7.3.0-9-generic
  os-release: PRETTY_NAME=Oaxaca 26.10 ID=oaxaca ID_LIKE=ubuntu debian VERSION_CODENAME=stonking
  hostname: oaxaca
  pending jobs: []
  system: starting
  failed units: []
  unit apparmor: active
  unit NetworkManager: active
  unit systemd-resolved: active
  unit systemd-timesyncd: active
  unit dbus-broker: active
  apparmor profiles: 162
  network: connected
  device: enp0s2:ethernet:connected
  resolv.conf: ../run/systemd/resolve/stub-resolv.conf
  apt sources: oaxaca.sources ubuntu.sources
  apt update: ok
  oaxaca-base candidate: 0.1.0
  ```
  `system: starting` rather than `running` is expected and explained in the script: systemd counts startup as finished only once its job queue first drains, and the test unit's own job is in that queue, so the test waits for every other job instead and reports no failed units. 162 AppArmor profiles loaded means the `apparmor` service found the profiles shipped by the installed packages. `apt update: ok` covers both the Ubuntu archive and the Oaxaca repository on GitHub Pages, verified with the installed keyring. The whole test, image creation included, takes 41 s on this workstation (the `mke2fs` copy of the 1.8 GB tree is most of that).
- Four problems found and fixed on the way, each now a comment in the script that hit it: a make variable named `PKG` in `debian/rules` was overridden by the `make build PKG=...` command line through `MAKEFLAGS`, leaving the package empty; the host shell's `LOCPATH` made the `locales` package fail its own check inside the chroot; a hook's redirect into the home directory was denied in unshare mode, so the manifest is fetched with mmdebstrap's `download` hook; and `systemctl is-system-running --wait` inside the test unit waited for itself.

## Open work

What is left from this step is in the developer README's [To do](README.md#to-do), the one list of open work.

## Facts checked on 2026-10-07

| Fact | Value | Source |
|---|---|---|
| `network-manager` in `stonking` | 1.58.1-1ubuntu3, `Depends: netplan.io (>= 1.2~)`; Recommends `wpasupplicant`, `wireless-regdb`, `polkitd`, `modemmanager` | `stonking/main/binary-amd64/Packages` |
| `linux-generic` / `linux-image-generic` in `stonking` | 7.3.0-9.9; `linux-image-generic` depends on `linux-firmware`, `intel-microcode`, `amd64-microcode`, recommends `thermald` | same |
| What provides `default-dbus-system-bus` | `dbus-broker` 37-5ubuntu5 (main); the `dbus` package is in universe | same |
| `shim-signed` / `grub-efi-amd64-signed` | 1.59+15.8-0ubuntu2 / 1.215+2.14-2ubuntu1, both recommend `secureboot-db` | same |
| `pipewire-audio` | 1.6.8-1ubuntu4, depends on `pipewire-alsa`, `pipewire-pulse`, `wireplumber`, `libspa-0.2-bluetooth` | same |
| `ubuntu-minimal` in `stonking` depends on | `netplan.io`, `ubuntu-pro-client`, `sudo-rs`, `python3`, `chrony \| time-daemon`, `dhcpcd-base` among others; not used here | same |
| lintian on apt preferences | `package-installs-apt-preferences`, error: "This directory is under the control of the local administrator" | `lintian-explain-tags` |
| mmdebstrap `--include` with a `.deb` path | the `.deb` must be readable by the unshared user and present at the same path inside the chroot; `--hook-dir=/usr/share/mmdebstrap/hooks/file-mirror-automount` does the copying | `man mmdebstrap`, 1.5.7 |
| Owner of `/etc/os-release`, `/usr/lib/os-release`, `/etc/lsb-release` | `base-files`; `/etc/os-release` is a symlink to `../usr/lib/os-release` | `dpkg -S` on this workstation (resolute) |
| `/dev/kvm` access on this workstation | ACL entry `user:<user>:rw-` for the maintainer's account | `getfacl` |
| `LOCPATH` set in the build host's environment | glibc then looks only in that directory for per-locale directories and ignores `locale-archive`, so the `locales` package's postinst check `update-locale LANG=en_US.UTF-8` fails inside the chroot with "invalid locale settings". The shell this was built from had `LOCPATH=/usr/lib/locale`; the script unsets it | first `make rootfs` run, 2026-10-07, and `locale(7)` |
| A make command-line variable reaches sub-makes | `make build PKG=...` overrode a `PKG` variable inside `debian/rules` through `MAKEFLAGS`, so `debian/rules` files here avoid that name | observed, first build of `oaxaca-base` |
