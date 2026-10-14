<!-- Generated from packages/nvidia/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-nvidia

The NVIDIA install path: roadmap step 4. The driver is not installed in a Oaxaca image; since 2026-10-11 the installation medium carries its packages in a pool (`/cdrom/pool`, `scripts/driver-pool.sh`, `docs/7 - image-installer.md` choice 20) and this package's command installs from that pool when it is there; this package makes installing it on the target machine one command and makes the installed driver load early. See `docs/4 - session.md`.

| Installed path | Purpose |
|---|---|
| `/usr/sbin/oaxaca-drivers-install`, `man 8 oaxaca-drivers-install` | runs `ubuntu-drivers install --no-oem --package-list /var/log/oaxaca/drivers.list nvidia:<branch>-open`, where `<branch>` is the newest NVIDIA open branch whose prebuilt signed modules (`linux-modules-nvidia-<branch>-open-*`) exist for the installed kernel, so Secure Boot needs no MOK enrollment. Ubuntu's detector on its own would pick the long-term branch (LTSB) over the newer one (NFB). With no NVIDIA GPU, or one the open modules do not support, the detector's own choice applies. `--show` prints the choice and the package list without installing |
| (dependency) `nvidia-prime` | after an NVIDIA driver install, `ubuntu-drivers` runs `prime-select on-demand` if that command exists, which enables runtime power management for the GPU on hybrid laptops. The driver packages only recommend it; the dependency makes sure `prime-select` is present even where Recommends are turned off |
| `/usr/share/initramfs-tools/hooks/oaxaca-nvidia` | copies the `nvidia`, `nvidia_modeset`, `nvidia_uvm` and `nvidia_drm` modules into the initramfs when they are installed (early KMS). Ubuntu's own hook only handles DKMS-built modules |

`ubuntu-drivers` decides whether a package is "from the distro" by the `Origin: Ubuntu` field of the apt release file it comes from, not by `/etc/os-release`, so `ID=oaxaca` does not change what it picks (checked in `UbuntuDrivers/detect.py`, the Python module from `ubuntu-drivers-common` 1:0.10.13 that the `ubuntu-drivers` command calls for detection and ranking).
