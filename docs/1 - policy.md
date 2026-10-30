# Policy (roadmap step 1)

*Wording revised 2026-10-05 to follow the documentation guidelines (terms defined before use, subjects named); decisions, facts and dates unchanged.*

Decided 2026-09-30. This document records the choices roadmap step 1 of [the plan](0%20-%20plan.md) asks for: the distro's name, the Ubuntu series to build on, the Omarchy version to follow, and the package namespace. Each choice comes with reasons and the rejected alternative, not a vendor best practice. Facts were re-checked on 2026-09-30 (see the last section).

## Terms

Each entry uses only terms defined above it, or terms the [README](README.md#terms) defines: [package](README.md#package), [source package](README.md#source-package), [suite and pocket](README.md#suite-and-pocket), [component](README.md#component), [archive](README.md#archive), [metapackage](README.md#metapackage), [build dependencies](README.md#build-dependencies) and [chroot](README.md#chroot). The first use of each term in the rest of this file links to its entry.

### Series, LTS and interim release

An Ubuntu series is one versioned Ubuntu, named by a codename and a year.month number: `stonking` is Ubuntu 26.10. Every two years the April series is an LTS (long-term support), maintained for five years; the series in between are interim releases, maintained for nine months. "Release day" is the day Canonical publishes a series; after that day its release pocket is frozen.

### The word "release" in this document

"Release" means four different things, so each use is qualified: an *Ubuntu release* is a series reaching release day; an *Omarchy release* is a tagged version of the Omarchy repository; an *Oaxaca release* is a versioned build of this distro; and the *`Release` file* is the signed index at the top of an archive (`InRelease` in its inline-signed form, see the developer README's [archive](README.md#archive) entry).

### Launchpad

Canonical's hosting and build service, where the Ubuntu archive is built and where each series' status (such as "Pre-release Freeze") and package versions are published through an API.

### Backport

Taking a newer version of a package from a later series or from upstream and rebuilding it for an older series. A backport lives in the backporter's own archive, here ours, and the backporter maintains it from then on.

### Fork, tag and merge

Git terms. A *fork* is our own copy of the Omarchy repository. A *tag* is a fixed name for one commit, which upstream uses for its releases (`v4.0.6`). To *merge* a new tag into our branch is to add a commit whose parents are our branch's last commit and the tag's commit, so the branch gains upstream's changes while every commit already on it keeps its hash. To *rebase* our branch onto a new tag would instead replay our commits on top of the tag's commit as new commits with new hashes.

### Omarchy shell

Omarchy's desktop user interface: one long-lived Quickshell process that hosts the bar, panels, menus and overlays as plugins, written in QML and JavaScript. In this document "shell" always means this program, never a command-line shell such as bash; command-line programs are called scripts.

### Migrations

Omarchy's `migrations/` directory: a script per change that must run once on an installed system to move user configuration from one Omarchy version to the next. Our packages must carry the same changes forward.

### Hyprland libraries

Hyprland is built on about eight libraries of its own (`hyprlang`, `hyprutils`, `aquamarine` and others, the "hypr* stack"). A newer Hyprland usually needs newer versions of several of them, so backporting Hyprland means backporting the set.

### Version string

A Debian package version is `<upstream version>-<Debian revision>`. The upstream version is the software's own; the Debian revision counts rebuilds of the packaging and is reset when the upstream version changes. A *native* version has no revision, for software whose packaging and source are one thing. A distributor marks its own rebuilds with a suffix inside the revision: Ubuntu's `-1ubuntu1` means "Debian's revision 1, Ubuntu's first change", and `-0ubuntu1` means "never in Debian". Our suffix is `oaxaca`.

### Transitional package

An empty package kept under an old name whose only job is to depend on the new name, so that systems that installed the old name are moved to the new one on their next upgrade.

### Template and rendering

A file whose name ends in `.in` and contains tokens such as `@DISTRO_ID@`. `make render` (`scripts/render.py`) replaces every token with its value from `distro.conf` and writes the result next to the template without the `.in`. Rendered files are committed.

### os-release

`/etc/os-release`, a file of `KEY=value` lines (`ID`, `ID_LIKE`, `NAME`, `VERSION_ID`, `PRETTY_NAME`) that identifies the distribution to programs and users. Ubuntu's `base-files` package ships it; our image builder will ship ours (roadmap step 3).

### Origin field and apt pin

`Origin` and `Label` are fields in an archive's `Release` file, set by whoever publishes the archive (aptly, for ours). An apt *pin* is a rule in `/etc/apt/preferences.d/` that raises or lowers the priority of packages from a source, and `Pin: release o=Oaxaca` selects a source by its `Origin` value, which is why the value must stay stable.

### Archive signing key

The GPG key whose signature on the `Release` file makes apt trust an archive. Its public half is what `oaxaca-archive-keyring` installs into `/etc/apt/keyrings/`. A GPG key carries one or more *user IDs*, each a name and optional email, and a rebrand can add a new user ID to the same key instead of replacing the key.

### Secure Boot and shim

Secure Boot is a firmware (UEFI) feature: the firmware only runs boot programs signed by a key it trusts, by default Microsoft's. *shim* is a small Microsoft-signed first-stage loader that then verifies GRUB and the kernel against Canonical's key, so a stock Ubuntu boots with Secure Boot on without any key enrollment.

### MOK

Machine Owner Key: a key the user adds to shim's trust list through `mokutil`, confirmed in the firmware at the next boot. A MOK lets locally built kernels or modules load under Secure Boot, at the cost of a manual enrollment step on every machine.

### DKMS

Dynamic Kernel Module Support: a framework that compiles an out-of-tree kernel module (the NVIDIA driver, for example) on the machine itself for each installed kernel. Under Secure Boot the result is unsigned unless a MOK signs it, which is why the plan prefers Canonical's prebuilt signed modules.

### Lockdown

A Linux Security Module (an LSM, a set of hooks inside the kernel that can veto operations) that Ubuntu's kernel enables automatically when it boots under Secure Boot. In its `integrity` mode it blocks anything that would let root alter the running kernel. The mode is readable at `/sys/kernel/security/lockdown`. The subsection "Suspend, hibernate and Secure Boot" below explains its effect on sleep.

### Suspend and hibernate

Two ways to pause a machine, defined fully in the subsection "Suspend, hibernate and Secure Boot" below. *Suspend* (suspend to RAM, ACPI state S3 "deep" or the firmware-less s2idle) keeps the machine's state in powered RAM. *Hibernate* (suspend to disk, ACPI state S4) writes a saved copy of RAM to swap and powers off. In this document "image" never means that saved copy; see the next entry.

### Image

A bootable disk image or ISO produced by the build pipeline (roadmap step 7): a *test image* is one booted in a virtual machine to verify a change. The saved copy of RAM that hibernation writes to swap is never called an image here.

### Initramfs

The small compressed root filesystem the bootloader hands the kernel first, containing the tools to find and unlock the real root filesystem. Ubuntu builds it with `initramfs-tools` from hooks in `/etc/initramfs-tools/`; Arch and Omarchy use `mkinitcpio` for the same job.

### LUKS

Linux Unified Key Setup, the standard on-disk format for an encrypted block device, managed by `cryptsetup`. A LUKS2 root filesystem is unlocked by the initramfs with a passphrase before boot continues. `cryptsetup-initramfs` is the Ubuntu package that adds that unlocking step to the initramfs.

### Plymouth

The program that draws the graphical boot screen and, with an encrypted root, the passphrase prompt. Omarchy ships a theme for it.

### TPM

Trusted Platform Module, a chip that can hold a secret and hand that secret out only when the boot measurements match. `systemd-cryptenroll` can bind a LUKS volume to it so the root unlocks without a passphrase.

### QEMU and OVMF

QEMU is the virtual machine program used to boot test images. OVMF is the open-source UEFI firmware for QEMU, shipped by Ubuntu's `ovmf` package in several variants; the `secboot` variant with the `ms` variable file has Secure Boot on with Microsoft's keys enrolled, so a guest booting it sees the same checks as real hardware.

### iGPU and dGPU

On a hybrid laptop the integrated GPU (iGPU, part of the CPU, Intel here) drives the displays, and the discrete GPU (dGPU, NVIDIA here) is a separate chip used on demand. The dGPU loses power in S3, which is why the NVIDIA driver has to save its video memory before suspend.

### Limine, btrfs and Snapper

Omarchy's boot and rollback stack on Arch: Limine is its bootloader, btrfs its root filesystem, and Snapper takes btrfs snapshots so a bad update can be rolled back from the boot menu. Oaxaca uses GRUB, ext4 by default with btrfs offered, and Timeshift in place of Snapper on btrfs installs (section 6), so Omarchy scripts tied to Limine and Snapper are not ported.

### Timeshift

A snapshot tool from Linux Mint (`timeshift` in Ubuntu's archive): on a btrfs root filesystem with Ubuntu's subvolume layout (`@` for `/`, `@home` for `/home`), it saves the `@` subvolume as a read-only btrfs snapshot and restores one by swapping subvolumes, finished by a reboot. It has a window (`timeshift-gtk`) and a command line (`timeshift`).

## 1. Distro name

**Oaxaca.** Decided 2026-09-30. Identifier `oaxaca`, display name `Oaxaca`.

**The distro's name lives in exactly one file, `distro.conf`, and every other occurrence of the name is generated from that file.** That rule is what keeps a rebrand cheap:

- `distro.conf`, a shell-syntax file of `KEY=value` lines at the repository root, holds `DISTRO_ID` (the lowercase identifier used in [package](README.md#package) names, commands, paths, systemd units and the `OAXACA_` environment-variable prefix), `DISTRO_NAME` (the display name), the GitHub owner and repository names, the apt [`Origin`, `Label`](#origin-field-and-apt-pin) and URL, the [archive signing key](#archive-signing-key)'s user ID and the maintainer string. The URLs are derived from the owner and repository names inside `distro.conf`.
- Any file that carries the distro's name is a [template](#template-and-rendering) with `@DISTRO_ID@`-style tokens. `make render` writes the real file next to the template and stamps the rendered file with a "generated, edit the .in" header where the file format allows comments. Rendered files are committed so a checkout is complete, and `make check-render` fails if the rendered files drift from `distro.conf`.
- Directory names never carry the distro's name (`packages/archive-keyring/`, not `packages/oaxaca-archive-keyring/`). Only the contents of rendered files carry the name.
- Scripts and systemd units that need the distro's name at runtime read the display name from [`/etc/os-release`](#os-release) or use the `DISTRO_ID`-derived paths baked in at build time; no script body hardcodes "oaxaca".
- The Omarchy rename (roadmap step 6, done 2026-10-10) is a script on the port branch, `port/rename.sh`, that takes the identity from `distro.conf` (through `packages/desktop/debian/rules`) and runs on a copy of the tree inside every build, so the rename re-runs after every [merge](#fork-tag-and-merge) and after any rebrand, and the branch itself keeps Omarchy's names.

What a rebrand costs anyway, and how to pay that cost, is in [the build-infrastructure doc](2%20-%20build-infra.md), "Rebrand playbook": [transitional packages](#transitional-package) for installed users, a new user ID on the archive signing key, and a changed apt URL, which is why a custom domain is recommended once one exists.

The distro's name is not "Omarchy" or a play on that name. Omarchy's code is MIT-licensed, but the Omarchy name is a trademark: omarchy.org/foundation states "Omarchy™. All rights reserved." and names the Omacom Foundation as the nonprofit behind the project (plan, "Branding note").

## 2. Base series

**Ubuntu 26.10 `stonking` now. Move to a newer [series](#series-lts-and-interim-release) on a trigger, not on a whim.**

- Status on 2026-09-30: `stonking` is in Pre-release Freeze on [Launchpad](#launchpad) with no release date set yet. Ubuntu 26.10 is due in October 2026. Development starts against the frozen [archive](README.md#archive) now; nothing changes on the [Ubuntu release](#the-word-release-in-this-document) day except that the `-updates` and `-security` [pockets](README.md#suite-and-pocket) start receiving packages.
- Status on 2026-10-18: Ubuntu 26.10 was released on 2026-10-15; Launchpad's API gives `stonking` the status "Current Stable Release", `datereleased` `2026-10-15T13:06:23Z`, and names `tenacious` as Ubuntu's development series. As planned, nothing in the build or the installed system changed with the release: both already read the release, `-updates` and `-security` pockets. One thing became more likely: Ubuntu's fixes now arrive as stable updates in `-updates` and `-security`, and an update to a source package the distro rebuilds with a patch (`plymouth`, `calamares`) outranks the rebuild (section 4, Version scheme), so `make upstream-check` reports such an update (docs/README.md, "`curl` with GitHub's and Launchpad's APIs").
- The apt sources entries from the first build onward, in the build [chroot](README.md#chroot)'s `/etc/apt/sources.list` and in the distro image's `/etc/apt/sources.list.d/ubuntu.sources`: suites `stonking`, `stonking-updates` and `stonking-security`, [components](README.md#component) `main restricted universe multiverse` (plan, "Kernel and security updates come from Ubuntu"). `restricted` is needed for the NVIDIA packages and `multiverse` for `nvtop` and `intel-media-va-driver-non-free`.
- **Move triggers.** Move to the next series when either happens first:
  1. `stonking` has three months of support left. Its 9-month window ends around July 2027, so that is about April 2027, which is when 27.04 ships.
  2. An LTS ships with `quickshell` and `hyprland` at or above what the pinned Omarchy release needs. Then that LTS becomes the base series and the interim-release churn stops.
- Rejected: **26.04 LTS as the base series** with Hyprland 0.56 and Quickshell [backported](#backport) into our archive. Rejected because 26.04 has Hyprland 0.53.3, below Omarchy's 0.55.0 minimum, and no Quickshell at all. Backporting the whole set of [Hyprland libraries](#hyprland-libraries) plus a Qt6-based Quickshell onto an LTS is exactly the maintenance load the plan avoids. An LTS stays the future base series, once an LTS ships both Hyprland and Quickshell natively.

## 3. Omarchy version to follow

**Follow the Omarchy release [tag](#fork-tag-and-merge) `v4.0.6`, commit `237f1b4071a0bff2296c6d740ba2b9fd695ebfa0` (published 2026-10-19, MIT), named as `OMARCHY_TAG` in `distro.conf`.** `v4.0.6` is the newest Omarchy release on 2026-10-23 (GitHub API, `repos/omacom/omarchy/releases/latest`); `v4.5.0-rc1`, a newer tag, is a release candidate, not a release. Omarchy's `master` branch moves past each tag within days, so `master` is not a stable base to track.

- **The version's source of truth is the git tag, not Omarchy's `version` file.** At tag `v4.0.6` the Omarchy repository's `version` file still reads `4.0.0.alpha`, so any script that derives a version from that file is wrong.
- **Merge policy.** The GitHub fork `santisbon/omarchy`, named in `distro.conf` as `OMARCHY_FORK`, carries the branch `oaxaca`; a checkout of `santisbon/omarchy` adds `omacom/omarchy` as the remote `upstream`, and step 6's document describes the branch and its rename script. Every change we make is a commit on that branch, and the branding rename (section 4) is a re-runnable script committed on that branch, not a hand edit. On each new Omarchy release tag: merge the tag into `oaxaca`, never rebase (the branch's commit hashes are recorded in published package versions and in this repository's release commits, and a rebase would replace them), push the tag to `santisbon/omarchy` as well as the branch (`scripts/build.sh` fetches the tag from `santisbon/omarchy` to count the branch's commits since it), set `OMARCHY_TAG` in `distro.conf`, re-run the rename, port or delete each migration the new tag adds to Omarchy's [`migrations/`](#migrations) (the branch carries only the port's own migrations; Omarchy's call pacman, limine and snapper, so none is kept as it comes), list what the merge leaves out in `santisbon/omarchy`'s `PORT-REMOVALS.md`, rebuild, and run the plan's verification list and the upgrade test (step 8). When the new Omarchy release builds a newer Quickshell (its `pkgbuilds/quickshell/PKGBUILD` in `omacom/omarchy-pkgs`), bump our `quickshell` [backport](#backport) to that Quickshell version: a new `URL=` and `SHA256=` in `packages/quickshell/upstream` and a changelog entry, the path step 5 set up. When the new release needs a Hyprland newer than the archive's, the choice is between skipping that Omarchy release until the archive catches up and backporting Hyprland together with its [Hyprland libraries](#hyprland-libraries) on the same packaging path; that choice is made per release and recorded here, and until that case comes up Hyprland stays the archive's.
- **Build up, never strip.** The port follows the rule the Ubuntu base follows (plan, "build up from the Ubuntu archive"): nothing of Omarchy's is shipped and then removed or turned off. The port branch starts from Ubuntu's configuration plus the parts of Omarchy the desktop needs to run, and each further Omarchy feature is added as a change written for Ubuntu, recorded as a choice in step 6's document with its reason. `santisbon/omarchy`'s `PORT-REMOVALS.md` lists the Omarchy features the port does not have and which of them are candidates to add.
- **The first machine, not the only one (2026-10-16).** Oaxaca is built and tested first on a Lenovo Legion Pro 7, and it is meant to work on other PCs too. Omarchy's fixes for other machines belong in the port: each one written for Ubuntu and applied only where its own device check matches (DMI vendor and model, PCI or USB id, CPU model), the way Omarchy gates it. The requirements in this document still decide how a fix is made: no DKMS module and so no MOK (section 5), Ubuntu's signed kernel and GRUB, packages from Ubuntu's archive, vendor apt repositories, the Snap Store, Flathub or this distro's own apt repository. A fix that cannot meet them stays out and is listed in `santisbon/omarchy`'s `PORT-REMOVALS.md` with the reason. The rule "Ubuntu's configuration unless a reason specific to this desktop" (docs/6) counts a reason specific to hardware the desktop runs on, not only to this laptop. Until 2026-10-16 the port dropped fixes for other machines as out of scope; step 6's choice 48 records the change.
- **Version gates today.** The minimum Hyprland for Omarchy v4.0.4 is 0.55.0 (plan); `git diff v4.0.4 v4.0.6` in `santisbon/omarchy` (2026-10-23) changes neither `install/omarchy-base.packages` nor any Hyprland or Quickshell version; `stonking` has 0.56.2, and Omarchy's own recipe (`omacom/omarchy-pkgs`, `pkgbuilds/hyprland/PKGBUILD`, read 2026-10-09) pins exactly 0.56.2. Omarchy's package list does not pin a Quickshell version, but the same recipes repository builds Quickshell 0.3.2 (`pkgbuilds/quickshell/PKGBUILD`); `stonking` has 0.3.0, and Quickshell's 0.3.1 changelog lists session lock crash fixes the shell's lock screen needs. Step 5 (`5 - hyprland-quickshell.md`, 2026-10-09) therefore keeps the archive's Hyprland and backports Quickshell 0.3.2 as `quickshell 0.3.2-0oaxaca1`, and a booted [test image](#image) running Omarchy's shell on it is the proof.
- Rejected: **tracking Omarchy's `master` branch** (it breaks weekly, and Omarchy moves faster than our packaging). **Copying one Omarchy checkout into our tree without its git history** (loses the ability to merge upstream's changes at all). **Rebasing `oaxaca` onto each new tag** (it rewrites every commit hash that published package versions name).

## 4. Package namespace and naming rules

**Prefix `oaxaca-` on everything we own; keep upstream names for software we only rebuild.**

| What | Rule | Examples |
|---|---|---|
| Our binary and [source packages](README.md#source-package) | `oaxaca-<part>` | `oaxaca-desktop`, `oaxaca-shell`, `oaxaca-config`, `oaxaca-themes`, `oaxaca-fonts`, `oaxaca-tools`, `oaxaca-nvidia`, `oaxaca-hw-legion`, `oaxaca-apparmor` |
| Third-party software we package, rebuild or publish unchanged | keep the upstream source and binary names | `nwg-displays`, `asdcontrol`, `localsend`, `voxtype`, `iphonebridge`, `quickshell` (backported in step 5), and `hyprland` if we ever backport it |
| System paths | `/usr/share/oaxaca/`, `/etc/oaxaca/`, `/var/log/oaxaca/` | themes and templates under `/usr/share/oaxaca/` (plan, step 6) |
| User paths | `~/.config/oaxaca/`, `~/.local/state/oaxaca/`; since 2026-10-17 each user also gets `~/.config/omarchy`, `~/.local/state/omarchy` and `~/.local/share/omarchy` as links to the distro's (`6 - omarchy-port.md`, choice 86) | the migrations' state files; the suspend baseline logs already use the state directory |
| Commands | every `omarchy-*` script becomes `oaxaca-*`, and every reference to that script (the [Omarchy shell](#omarchy-shell)'s QML and JavaScript, the Hyprland Lua config, the menu JSON, systemd units) is rewritten by the same rename script. Since 2026-10-17 `oaxaca-tools` also ships an `omarchy-<name>` link for every `oaxaca-<name>` command and `omarchy` for the `oaxaca` dispatcher, for plugins and themes written for Omarchy (`6 - omarchy-port.md`, choice 86) | `omarchy-theme-set` becomes `oaxaca-theme-set`, and `omarchy-theme-set` links to it |
| Names users do not see | kept as Omarchy spells them, for plugins and themes written for Omarchy (since 2026-10-17, `6 - omarchy-port.md`, choice 86): the built-in plugins' IDs and IPC targets, `OMARCHY_*` environment variables, Wayland app IDs and native-messaging host names, the `omarchy` section of a plugin manifest, the menu's entry keys and the icon font's family | `omarchy.clock`, `OMARCHY_PATH`, `org.omarchy.terminal` |
| systemd units | `oaxaca-*.service` | `oaxaca-sleep-lock.service` |
| apt repository | `Origin: Oaxaca` and `Label: Oaxaca` in the archive's `Release` file, the [suite](README.md#suite-and-pocket) named after the Ubuntu series, one component `main` | the apt sources entry `deb [signed-by=...] <url> stonking main` |
| `/etc/os-release` | `ID=oaxaca`, `ID_LIKE="ubuntu debian"`, `VERSION_ID` follows the base series. Verified in step 4 (`4 - session.md`): `ubuntu-drivers` tests apt's `Origin: Ubuntu` field, not `/etc/os-release`, and recommends a driver on this laptop with `ID=oaxaca`; apt behaved in steps 3 and 4 | |

- **Why a full command rename, with compatibility links since 2026-10-17.** The Omarchy shell and its menu call scripts by name. Until 2026-10-17 this section rejected `omarchy-*` links, because a layer of them would hide the references the rename missed, and those missed references are exactly the bugs we want to find. The distro's maintainer then made compatibility with Omarchy's plugins and themes a requirement (`6 - omarchy-port.md`, choice 86): of 30 plugins sampled from Omarchy's plugin marketplace, 22 failed on the renamed system, because they call `omarchy-*` commands, use `~/.config/omarchy` or `OMARCHY_PATH`, or name built-in plugins such as `omarchy.weather`. So the rename still renames everything users see, and the packaging adds `omarchy-*` links beside the commands; the objection is answered by a check instead: `port/rename.sh` fails the build when any file of the port still says omarchy outside its keep list and Omarchy's own addresses, so nothing the distro ships depends on the links. Names users do not see (the row above) are not renamed at all, since links cannot cover strings inside the shell's code and users' bar layouts. The `omarchy` names are a compatibility layer, not the distro's identity, and the plan's branding note (rebrand so the distro is not mistaken for Omarchy) still holds for everything users meet: the commands the menu, bindings and docs use are `oaxaca-*`; the menu, messages, `/etc/os-release`, the boot splash, the login screen and the logo say Oaxaca; and the dispatcher presents itself as Oaxaca's even when called as `omarchy`. A user meets an Omarchy name only by typing one or by running code written for Omarchy (choice 86). Rejected: keeping `omarchy-*` as the scripts' real names and rebranding only the visible parts (users would see `omarchy-*` in error messages and process lists); links without keeping the hidden names (plugins that name built-in plugins would still fail, 8 of the 30).

### Version scheme

| Package kind | Format | Example | Why |
|---|---|---|---|
| Ported Omarchy content (`oaxaca-shell`, `-themes`, `-config`, `-tools`, and `oaxaca-desktop`, the metapackage, since 2026-10-10: it is built from the same source and its dependency list is Omarchy's package list ported, which changes with the tag) | `<omarchy tag>+git<commit date>.<count>.<commit>-0oaxaca<N>` | `4.0.4+git20261014.20.0559194c-0oaxaca1` | The Omarchy version stays visible as the upstream part of the [version string](#version-string), and the `+git` part names the commit of `santisbon/omarchy` the packages are built from, so each change to `santisbon/omarchy` is a new upstream version with its own orig tarball (the orig tarball is made from `santisbon/omarchy`'s tree and is named after the upstream version). The part has three fields: the commit's date (UTC, `YYYYMMDD`), for people; the number of commits in `santisbon/omarchy` since the Omarchy tag (`git rev-list --count v4.0.4..<commit>`), which grows with every commit and so orders any number of changes to `santisbon/omarchy` in one day; and the commit's hash abbreviated to 8 hex digits, which names the commit exactly. A hash alone cannot order versions, and dpkg must know which is newer. Ubuntu's own `sddm 0.21.0+git20251101.dfa5315-1ubuntu2` uses the same date-then-hash form; the count is ours. The three values are `OMARCHY_PORT_DATE`, `OMARCHY_PORT_COUNT` and `OMARCHY_PORT_COMMIT` in `distro.conf`; `scripts/build.sh` fails when the commit it fetches does not match them and prints the right values. From 2026-10-13 to 2026-10-14 the part was `+git<date>` alone (`4.0.4+git20261014-0oaxaca1` is the last of those), which allowed one change to `santisbon/omarchy` a day; `4.0.4+git20261014.20.0559194c` sorts above it. The Debian revision is ours. The `0` marks "never in Debian", following Ubuntu's `0ubuntu1` convention |
| Our own packages with no upstream (`oaxaca-hw-legion`, `-nvidia`, `-apparmor`) | native version, starting at `0.1.0` | `0.1.0` | We are the upstream, so a Debian revision would carry no information |
| Third-party we package from source (`nwg-displays`, `asdcontrol`, `hyprland-preview-share-picker`, `quickshell`, and `oaxaca-fonts`, whose content is third-party fonts: step 6 moved it here from the native row), or from a project's own release builds (`localsend`, since 2026-10-14) | `<upstream>-0oaxaca<N>` | `nwg-displays 0.4.4-0oaxaca1` | Same reasoning as the first row |
| Third-party release `.deb` published unchanged (`iphonebridge`, since 2026-10-27) | the project's own version | `iphonebridge 0.20.1` | The repository serves the release's own file, so the version is the one inside it; changing the version would mean rebuilding the package (6 - omarchy-port.md, choice 109) |
| Third-party we rebuild from a Debian or Ubuntu source package | `<their version>oaxaca<N>` | `calamares 3.3.14-0ubuntu30oaxaca2` (step 7: Ubuntu's `3.3.14-0ubuntu30` with two patches) | Mirrors how Ubuntu marks a rebuilt Debian package (`-1ubuntu1`), and sorts above the original version so apt prefers our build |
| Oaxaca releases and their [images](#image) | `<base YY.MM>.<N>` | `26.10.0` for the first image on `stonking` | The base series defines what is inside and when support ends, so the version hides neither. Rejected: an independent semantic-versioning scheme, which would hide the Ubuntu series |

**Bump rule (2026-10-11, step 8).** A package whose content changes gets a new version before it is published, because apt identifies a package by name and version: a rebuilt file under a version users already have is never offered to them, and a client holding the previous index fails the download hash check. `make check-versions` (CI's prepare job) fails when a package directory changed since the newest `v*` tag without a changelog entry, and `make publish` refuses a file whose name and version are already published with different content.

## 5. Requirements every later step must keep

Two requirements on what the distro must support, stated 2026-09-30 and clarified 2026-10-01, and one rule on how a user logs in, stated 2026-10-09. The two requirements are about the distro's capabilities, not demands on a user's firmware or disk layout. All three are already assumed in parts of the plan; this section makes them explicit so no later choice quietly drops them.

### Secure Boot supported, never required

**The distro must install, boot and run with [Secure Boot](#secure-boot-and-shim) enabled, with no [MOK](#mok) enrollment by the user in the default path. The distro must work just as well with Secure Boot off, and the distro never requires or changes the firmware's Secure Boot setting.** Support, not enforcement: a user who dual-boots an unsigned kernel, as this laptop does with Linux From Scratch, keeps Secure Boot off and loses nothing.

- **What that means in practice.** Ubuntu's shim, GRUB and kernel are Microsoft- and Canonical-signed, so we ship those three from the Ubuntu archive unchanged (plan, "Kernel and security updates come from Ubuntu"). The NVIDIA kernel modules come from Canonical's signed `linux-modules-nvidia-*` packages (plan, "NVIDIA proprietary driver"). No package of ours may depend on an unsigned or out-of-tree kernel module. [DKMS](#dkms) stays a documented fallback that needs a MOK, never the default, with one exception: the installer installs the BCM4360 Wi-Fi driver of 2013 to 2015 Macs, which only DKMS provides, on a Mac whose firmware is not enforcing Secure Boot. That install-time check is the one place the distro reads the Secure Boot state; on a machine with Secure Boot on, nothing changes ([docs/6](6%20-%20omarchy-port.md), choice 113).
- **Consequences to accept.** With Secure Boot on, the kernel runs in [lockdown](#lockdown) `integrity` mode, so [hibernation](#suspend-and-hibernate) is unavailable in that mode (the kernel file `/sys/power/disk` reads `[disabled]`) and so is suspend-then-hibernate. The subsection "Suspend, hibernate and Secure Boot" below explains why. Custom kernels are out, because a custom kernel would break the signed boot path for the users who do run Secure Boot. **Hibernation is out of the first Oaxaca release in every configuration, for scope, not because of Secure Boot:** hibernation needs swap sized to RAM on the encrypted disk, resume wiring in the [initramfs](#initramfs), and a port of Omarchy's hibernation scripts away from [Limine, btrfs and mkinitcpio](#limine-btrfs-and-snapper). A later Oaxaca release can offer hibernation as an opt-in on systems whose kernel allows it, which today means Secure Boot off (a kernel change that may lift that limit is noted under "Suspend, hibernate and Secure Boot" below); hibernation stays off by default because the distro must behave the same in both Secure Boot settings.
- **Verification.** Every test image boots in [QEMU](#qemu-and-ovmf) both ways: with Secure Boot on, using the `ovmf` package's firmware files with Microsoft's keys enrolled (`OVMF_CODE_4M.secboot.fd` with `OVMF_VARS_4M.ms.fd`), where `mokutil --sb-state` inside the guest reports enabled, and with Secure Boot off. Those QEMU boots are the routine check. The laptop gets one Secure Boot pass per Oaxaca release for the NVIDIA checks in the plan's verification list (signed modules loading under lockdown): toggle Secure Boot on in the firmware, test, toggle Secure Boot back off. The QEMU method is a choice of test method, not a vendor requirement.
- **This laptop today.** Secure Boot is off and stays off: the laptop dual-boots a Linux From Scratch system whose kernel is unsigned, and GRUB only loads signed kernels while Secure Boot is on. That dual boot is exactly the "supported, never required" case. The suspend baseline in [suspend-baseline.md](suspend-baseline.md) was taken with Secure Boot off; S3 suspend does not depend on Secure Boot, hibernation availability does.

### Suspend, hibernate and Secure Boot

[Suspend and hibernate](#suspend-and-hibernate) differ in where the machine's state lives while the machine is off.

| | Suspend to RAM (the baseline tests) | Hibernate (suspend to disk) |
|---|---|---|
| ACPI state | S3 "deep" on this laptop, or s2idle on machines without S3 | S4 |
| Where the machine's state goes | stays in RAM, which is kept powered and refreshed | written to swap as a saved copy of RAM, then the machine powers off fully |
| Power while off | small but not zero, so a battery drains over days | zero |
| Resume | seconds; the kernel never stopped existing | a normal boot that finds the saved copy in swap and jumps back into that saved kernel |
| Needs | nothing extra | swap at least as large as the compressed saved copy, and a `resume=` parameter on the kernel command line (set through the bootloader's configuration, `/etc/default/grub` on Ubuntu) pointing the kernel at that swap |

On this laptop the kernel file `/sys/power/state` offers `freeze mem disk`, and `mem` maps to `deep` through the kernel file `/sys/power/mem_sleep`. The NVIDIA driver saves the video memory to `/var` on the way down because the [dGPU](#igpu-and-dgpu) loses power in S3, and the systemd units `nvidia-suspend` and `nvidia-resume` restore the video memory on the way up (see [suspend-baseline.md](suspend-baseline.md)).

**Secure Boot reaches sleep through kernel lockdown.** Secure Boot itself only verifies the boot chain: the firmware checks shim, shim checks GRUB and the kernel, and the kernel checks module signatures. Secure Boot's promise is that only signed code runs in kernel mode. To keep that promise after boot, Ubuntu's kernel turns on lockdown when the kernel finds Secure Boot enabled.

- **Anatomy:** lockdown is a Linux Security Module, a set of hooks inside the kernel. Lockdown's mode shows in the kernel file `/sys/kernel/security/lockdown`. In `integrity` mode lockdown blocks anything that would let root alter the running kernel: unsigned modules, raw memory access, kexec of unsigned kernels, and hibernation.
- **Why hibernation is on that list.** Resume from hibernation loads the saved copy of RAM from swap and executes that copy. The saved copy is kernel memory, and the kernel has no way to verify who wrote the copy. Anyone who can write to swap, whether root or someone with the disk in hand, could craft a saved copy that resumes into a modified kernel, and every check Secure Boot did at boot would be bypassed. So lockdown disables hibernation outright, and `/sys/power/disk` reads `[disabled]`. That `[disabled]` value is what the plan's inventory saw with Secure Boot on.
- **Why suspend is not on the list.** Suspend reloads nothing from disk, so there is nothing to forge. The kernel that wakes up is the kernel that was verified at boot. The same reason explains why the baseline results were the same with Secure Boot off.
- **Disk encryption does not lift the block.** Encrypted swap keeps the saved copy private from an offline attacker, but the kernel still cannot authenticate the saved copy and root can still write to the swap, so lockdown makes no exception for encrypted swap.

**What follows for the distro.** With the kernel as it is today, hibernation cannot be part of the Secure Boot path: the two ways around lockdown both break the support requirement, since disabling validation in shim through a MOK turns Secure Boot into a formality, and a custom kernel with lockdown removed also breaks the signed NVIDIA modules. With Secure Boot off the kernel allows hibernation, so a later Oaxaca release can offer hibernation as an opt-in on such systems. The first Oaxaca release ships deep S3 as the only sleep state in both Secure Boot settings, and the baseline shows S3 works docked, undocked, lid open, lid closed, on AC and on battery.

**Hibernation under lockdown may be supported in the future (noted 2026-10-17).** On 2026-10-08 Matthew Garrett, at NVIDIA, posted a request for comments (an RFC: patches sent to a kernel mailing list for review, not merged) to the linux-pm list that lets hibernation work while the kernel is in lockdown (`https://lore.kernel.org/linux-pm/20261008132532.1155166-1-matthewg@nvidia.com/`). Phoronix's report of 2026-10-09 (`phoronix.com/news/Linux-Hibernation-With-Lockdown`) describes today's saved copy of RAM as "unencrypted and unauthenticated", and says the patches add audited [TPM](#tpm) sessions in the kernel and a TPM signing key, so that the saved copy is "securely signed to ensure that it wasn't tampered with". A signed saved copy answers the reason above that lockdown blocks hibernation: the kernel could check who wrote the copy before resuming into it. The patches themselves were not read for this note (lore.kernel.org turned away the request), and Phoronix names no kernel version they target. Before hibernation can join the Secure Boot path, the patches have to be merged upstream, reach the kernel of the Ubuntu series the distro is built on, and work with the laptop's TPM; hibernation's scope work in section 5 (swap sized to RAM on the encrypted disk, resume wiring in the initramfs, a port of Omarchy's scripts) is needed either way. Until then this section's conclusion stands.

### Full-disk encryption

**The installer must offer full-disk encryption as a first-class option, and the test images must prove an encrypted root boots and sleeps correctly.** Users who decline encryption get a plain install; the distro never requires encryption.

- **What that means in practice.** [LUKS2](#luks) on the root filesystem, set up by the installer (Calamares, a graphical installer framework, or our own script; roadmap step 7). The `cryptsetup-initramfs` package so the initramfs unlocks the root filesystem with a passphrase, and [Plymouth](#plymouth) (with Omarchy's theme, rebranded) for the passphrase prompt (plan, "This machine" table). The boot partition stays unencrypted, as on Ubuntu, because the signed shim and GRUB read the boot partition before anything is unlocked.
- **Not required now.** [TPM](#tpm)-backed unlock without a passphrase. Ubuntu's own TPM path is built on snaps, which the plan keeps off the system. Since 2026-10-16 the desktop offers an opt-in TPM unlock through Clevis instead (`6 - omarchy-port.md`, choice 37); `systemd-cryptenroll`, considered here first, needs a systemd-based initramfs, which Oaxaca does not use. Encrypted swap for hibernation is moot while hibernation is out.
- **Interaction with the NVIDIA sleep setup.** The NVIDIA kernel module parameter `PreserveVideoMemoryAllocations` makes the driver write the video memory to a file under `/var` on suspend (plan, "Sleep and resume"). Ubuntu's driver package sets that parameter and its companion `TemporaryFilePath` as module options; the values in force are readable in `/proc/driver/nvidia/params`. With an encrypted root the video memory file lands on the encrypted filesystem, which is what we want; keep `TemporaryFilePath` on the root filesystem rather than on an unencrypted partition.
- **Verification.** A test image installed with encryption boots to the Plymouth passphrase prompt, unlocks, and `lsblk -o NAME,TYPE,FSTYPE` shows the root filesystem under a `crypt` device. Suspend scenario 1 from the baseline passes on that install too, since the video memory file now lives on the encrypted root.

### Password login, no autologin

**A user logs in with a password. Oaxaca configures no autologin, on encrypted installs or plain ones.** Omarchy's ISO writes an SDDM `autologin.conf` for encrypted installs, on the reasoning that the disk passphrase already authenticated the user; Oaxaca does not follow it (`4 - session.md`, choice 14, and its Facts table for the Omarchy ISO source).

- **What that means in practice.** SDDM's greeter asks for the password on every boot and after every logout; the installer (roadmap step 7) creates the user with a password and writes no `[Autologin]` section into `/etc/sddm.conf.d/`. The only `[Autologin]` file in the project is the one `scripts/rootfs-boot-test.sh` writes into the QEMU test image, so the graphical test needs no greeter interaction; that file never enters a root filesystem tarball or an image.
- **Why the keyring depends on it.** GNOME Keyring's PAM module, `pam_gnome_keyring.so`, receives the password SDDM collected and unlocks the `login` keyring with it, so applications get their saved credentials with no second prompt (`4 - session.md`, "Secret Service and keyring"). An autologin collects no password, which is why Omarchy pairs its autologin with a passwordless keyring. Oaxaca keeps the keyring encrypted with the login password instead.
- **Fingerprint support, decided 2026-10-09, with Omarchy's scope.** Oaxaca supports a fingerprint reader for `sudo`, polkit prompts and the lock screen, and not for the login screen, which keeps asking for the password. That is exactly what Omarchy v4.0.4 does: its `bin/omarchy-setup-security-fingerprint` enrolls a finger with `fprintd-enroll`, then adds `auth sufficient pam_fprintd.so` to `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` and writes `/etc/pam.d/omarchy-lock-fingerprint` for the lock screen, each behind a "lid closed" gate that skips the reader when the laptop is shut; it never touches SDDM's PAM file. The login stays a password login, so the `login` keyring is unlocked at login as above, and the fingerprint only replaces retyping that password later in the session. Ubuntu's packages for it are `fprintd` and `libpam-fprintd` (`stonking`: 1.94.5-4maysync1, with `libfprint-2-2` 1:1.95.2+tod1-1ubuntu2). Oaxaca must not enable Ubuntu's `pam-auth-update` profile for the module (`/usr/share/pam-configs/fprintd`, "Fingerprint authentication", `Default: no`, `Auth-Type: Primary`), because that profile puts `pam_fprintd.so` into `common-auth`, which every service including SDDM's login includes, and that would turn the login screen into a fingerprint login. Oaxaca ships its own profile for the module instead, `oaxaca-fprintd`, whose first line skips the reader for every service except `sudo`, `sudo -i` and polkit, so the login screen keeps the password (docs/6, choices 53 and 103). The port of Omarchy's setup, removal and detection scripts (`omarchy-setup-security-fingerprint`, `omarchy-remove-security-fingerprint`, `omarchy-hw-fingerprint`) and the first-run invitation belong to roadmap step 6, and the lock screen's PAM file to the lock screen's package there. The packages are dependencies of step 6's `oaxaca-desktop`, installed on every system, not installed on demand by the scripts as Omarchy does (plan, step 6, decided 2026-10-09).
- **FIDO2 security key, decided 2026-10-09, same scope.** A FIDO2 key with a fingerprint sensor, such as the AuthenTrend ATKey.Pro this laptop uses, is the second way to replace retyping the password for `sudo` and polkit, and the login screen stays a password login here too. The PAM module is `pam_u2f.so` from `libpam-u2f` (`stonking` `universe`: 1.4.0-3build2, with `pamu2fcfg` from the same source, `libfido2-1` 1.17.0-2build1 and `fido2-tools` 1.17.0-2build1 for `fido2-token -L`). Omarchy v4.0.4 has this path too: `bin/omarchy-setup-security-fido2` registers the key with `pamu2fcfg` into the root-owned file `/etc/fido2/fido2` and adds `auth sufficient pam_u2f.so cue authfile=/etc/fido2/fido2` as the first line of `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1`; `bin/omarchy-remove-security-fido2` undoes both. It does not cover the lock screen, and neither does Oaxaca until Omarchy does. Oaxaca follows Omarchy's root-owned `authfile` rather than the module's default registration file, `~/.config/Yubico/u2f_keys`, so that a user cannot register a key for root's benefit by editing a file in their own home. Both scripts port in step 6 beside the fingerprint ones, with their package install and uninstall dropped, since `libpam-u2f` and `fido2-tools` are dependencies of `oaxaca-desktop` (plan, step 6). Oaxaca puts the key into `common-auth` through its own `pam-auth-update` profile, `oaxaca-u2f`, behind the same first line as the fingerprint profile, so only `sudo`, `sudo -i` and polkit take the key (docs/6, choice 103). The two paths can coexist: with both profiles enabled, PAM tries the key, then the reader, before falling back to the password.

## 6. Boot loader and snapshots

Decided 2026-10-16, writing down why GRUB was kept from the start (the plan's roadmap step 3 only said "GRUB is Ubuntu's default; Omarchy's Limine and Snapper setup is optional to port").

### GRUB, not Limine

**Oaxaca boots with Ubuntu's shim and GRUB. [Limine](#limine-btrfs-and-snapper), Omarchy's boot loader, is a rejected alternative.** Limine is not Arch-only (a standalone boot loader that Arch packages); the reasons are about Ubuntu and this project's requirements:

- **Secure Boot without a MOK** (section 5, "Secure Boot supported, never required"). Ubuntu's chain is shim, signed by Microsoft, then GRUB and the kernel, signed by Canonical, and Ubuntu's shim trusts only Canonical's signature or a key the user enrolls as a [MOK](#mok). A Limine binary is not signed by Canonical, so with Secure Boot on every install would need a signing key of this project's and a MOK enrollment at the first boot.
- **Not in Ubuntu's archive.** Launchpad has no `limine` source package in stonking (checked 2026-10-16), so Oaxaca would build and maintain the package itself.
- **Not in Calamares.** The `bootloader` module of stonking's Calamares (`bootloader/main.py`, calamares 3.3.14-0ubuntu30, read from the live image 2026-10-16) installs `grub`, `sb-shim`, `systemd-boot`, `refind` or `clr-boot-manager`; Limine would need an installer step of our own.
- **Kernel updates.** Ubuntu's kernel packages run `/etc/kernel/postinst.d/zz-update-grub` (from `grub2-common`) after every kernel install or removal; Limine would need hooks of our own for the same job.
- **What is given up.** Omarchy's boot menu of Snapper snapshots comes from Limine with `limine-snapper-sync`, an Arch package; Oaxaca restores snapshots from the running system or the installation USB stick instead (next subsection).

### Timeshift snapshots on btrfs installs

**On a btrfs install, [Timeshift](#timeshift) takes a snapshot of `/` before every `oaxaca-update`; ext4 and xfs installs have no snapshots; btrfs is the installer's default since docs/7 choice 52.** The installer keeps Timeshift and `btrfs-progs` on btrfs installs and configures Timeshift (`7 - image-installer.md`, choice 51); the desktop's `oaxaca-snapshot` takes and prunes the snapshots (`6 - omarchy-port.md`, choice 38). Timeshift was chosen over Snapper because Timeshift is made for the `@`/`@home` layout the installer creates and restores by itself, while Snapper's rollback does not take effect on Ubuntu's layout; the subvolume layout requirement and LUKS support are from Timeshift's README (`github.com/linuxmint/timeshift`, read 2026-10-16). Snapshots do not cover the separate `/boot` partition.

## Facts checked on 2026-09-30

| Fact | Value | Source |
|---|---|---|
| Newest Omarchy release tag | `v4.0.6`, published 2026-10-19, MIT (checked 2026-10-23) | GitHub API, `omacom/omarchy` |
| `stonking` status | Pre-release Freeze, `datereleased` empty; since 2026-10-15, Current Stable Release (checked 2026-10-18) | Launchpad API |
| `stonking` `hyprland` | 0.56.2+ds-1 (universe) | Launchpad API |
| `stonking` `quickshell` | 0.3.0-1build1 (universe); Debian sid 0.3.1-1; upstream 0.3.2 released 2026-10-08; Omarchy builds 0.3.2 | Launchpad API; Debian's `Packages` index; GitHub releases; `omacom/omarchy-pkgs` (2026-10-09) |
| `stonking` `uwsm` / `xdg-desktop-portal-hyprland` / `sddm` | 0.26.6 / 1.4.1 / 0.21.0+git20251101 (universe) | Launchpad API |
| `stonking` `nwg-displays` | 0.3.28-1 (universe), still below the 0.4.3 the plan needs | Launchpad API |
| `stonking` `nvidia-vaapi-driver` | 0.0.16-1 (universe) | Launchpad API |
| `stonking` `mmdebstrap` / `mkosi` | 1.5.7-3 / 27-1ubuntu1 (universe) | Launchpad API |
| `asdcontrol` | not in the Ubuntu archive, as the plan says | Launchpad API |
