<!-- Generated from packages/base/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-base

The base system metapackage: roadmap step 3. Installing `oaxaca-base` on a minbase root filesystem pulls in the kernel, boot chain, init, network, sound and the Oaxaca apt repository. `scripts/rootfs-create.sh` does exactly that to build the root filesystem tarball. See `docs/3 - rootfs.md`.

Files this package installs besides its dependency list:

| Installed path | Purpose |
|---|---|
| `/usr/lib/os-release` (base-files' copy diverted to `/usr/lib/os-release.ubuntu`) | the system identifies as Oaxaca: `ID=oaxaca`, `ID_LIKE="ubuntu debian"` |
| `/usr/libexec/oaxaca/loader-fallback`, dpkg triggers on `/usr/lib/grub/x86_64-efi-signed` and `/usr/lib/shim` | on an EFI System Partition shared with another Ubuntu-family system (named in `/etc/oaxaca/previous-loader` by the installer), rewrites the `/EFI/ubuntu/grub.cfg` stub so it tries this system's `/boot` and falls back to the other system's GRUB when this one is gone; re-applied after every GRUB or shim upgrade, which runs `grub-install` (`docs/7 - image-installer.md`, choice 24) |
| `/etc/apt/preferences.d/oaxaca-blocked-recommends` | apt pins (`Pin-Priority: -1`) that keep two Recommends out: `xdg-desktop-portal-gnome` (Files recommends it, and it recommends `gnome-shell`, which would bring GNOME Shell, `gdm3`, the Ubuntu GNOME session and IBus) and `sudo-rs` (`sudo` recommends it, and its `/usr/bin/sudo` alternative, priority 50, outranks classic sudo's 40; the menus' sudoers rules need classic sudo). apt installs every other Recommends, as on a stock Ubuntu. |
| `/etc/netplan/01-oaxaca-network-manager.yaml` | netplan hands all interfaces to NetworkManager |

The dependency list also names what stonking's `systemd` and `udev` recommend, added while this package set Recommends off (before 0.1.6) and kept so the base system does not rely on Recommends: the TPM tools (`systemd-cryptsetup`, which carries `systemd-cryptenroll`; `systemd-tpm`, `tpm-udev`, `libtss2-rc0t64`), `systemd-hwe-hwdb` (Ubuntu's updated hardware database: key mappings and sensors of newer machines), `libnss-systemd` and `linux-sysctl-defaults` (`docs/7 - image-installer.md`, choice 47). The TPM tools do not turn on TPM unlock of the disk; that is still to be designed.

