<!-- Generated from packages/base/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-base

The base system metapackage: roadmap step 3. Installing `oaxaca-base` on a minbase root filesystem pulls in the kernel, boot chain, init, network, sound and the Oaxaca apt repository. `scripts/rootfs-create.sh` does exactly that to build the root filesystem tarball. See `docs/3 - rootfs.md`.

Files this package installs besides its dependency list:

| Installed path | Purpose |
|---|---|
| `/usr/lib/os-release` (base-files' copy diverted to `/usr/lib/os-release.ubuntu`) | the system identifies as Oaxaca: `ID=oaxaca`, `ID_LIKE="ubuntu debian"` |
| `/usr/libexec/oaxaca/loader-fallback`, dpkg triggers on `/usr/lib/grub/x86_64-efi-signed` and `/usr/lib/shim` | on an EFI System Partition shared with another Ubuntu-family system (named in `/etc/oaxaca/previous-loader` by the installer), rewrites the `/EFI/ubuntu/grub.cfg` stub so it tries this system's `/boot` and falls back to the other system's GRUB when this one is gone; re-applied after every GRUB or shim upgrade, which runs `grub-install` (`docs/7 - image-installer.md`, choice 24) |
| `/etc/apt/apt.conf.d/50oaxaca-no-recommends` | apt installs no Recommends |
| `/etc/netplan/01-oaxaca-network-manager.yaml` | netplan hands all interfaces to NetworkManager |

