<!-- Generated from packages/hw-legion/README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# oaxaca-hw-legion

The hardware package for the first machine Oaxaca is built for, the Lenovo Legion Pro 7 16IAX10H (roadmap step 6; the inventory is in `docs/0 - plan.md`, "This machine"). It holds only what this model needs and other machines must not get: one file, `/etc/oaxaca/gpu`. The installer's hardware step (`packages/installer/hardware-install`, run by Calamares's `shellprocess@hardware`) installs this package from the installation medium's package pool when the firmware's DMI strings name this model (`sys_vendor` `LENOVO`, `product_version` `Legion Pro 7 16IAX10H`); nothing in `oaxaca-desktop` depends on it.

What the inventory lists for this laptop and every other machine gets too comes from other packages (`docs/7 - image-installer.md`, choice 44):

| Package | Comes with | What it does |
|---|---|---|
| `fwupd`, `fwupd-signed` | `oaxaca-base` | firmware updates, including UEFI capsule updates through the Canonical-signed EFI program |
| `firmware-sof-signed`, `alsa-ucm-conf` | `oaxaca-base` | the Sound Open Firmware and the mixer profiles the internal speakers and microphone need |
| `linux-firmware` | the kernel (`linux-image-generic`) | the Intel BE200 Wi-Fi and Bluetooth firmware |
| `intel-media-va-driver-non-free` | `oaxaca-session` | video decode on Intel GPUs (multiverse) |
| `oaxaca-hybrid-backlight` | `oaxaca-nvidia` | hides the NVIDIA driver's phantom backlight device on hybrid laptops |
| `nvidia-vaapi-driver` | `oaxaca-drivers-install`, after an NVIDIA driver | video decode on the NVIDIA GPU, for applications started on that GPU (`oaxaca-launch-dgpu`) |
| `bolt`, `asdcontrol` | `oaxaca-desktop` | Thunderbolt device authorization; Apple Studio Display brightness |

| Installed path | Purpose |
|---|---|
| `/etc/oaxaca/gpu` | one line, `/dev/dri/by-path/pci-0000:00:02.0-card`: the GPU list `oaxaca-session`'s user environment generator (`50-oaxaca-gpu`) resolves to the card's node and exports to Hyprland as `AQ_DRM_DEVICES` at login, so Hyprland renders on the Intel GPU, to which every display of this laptop is wired, and the NVIDIA GPU can power down. Until 2026-10-11 this was a static `environment.d` file naming the by-path symlink, which aquamarine does not accept (`docs/7 - image-installer.md`, choice 17). The file applies only while the Intel GPU drives the display the firmware booted on; with the laptop's GPU switch set to the NVIDIA GPU in the firmware, the session skips the file and Hyprland chooses for itself (`docs/7 - image-installer.md`, choice 45) |
