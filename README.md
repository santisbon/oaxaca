<!-- Generated from README.md.in by scripts/render.py. Edit the .in file, not this one. -->
# Oaxaca

Oaxaca is Ubuntu 26.10 with the desktop of [Omarchy](https://omarchy.org). What Oaxaca offers, the ISO download and the manual are on Oaxaca's website, <https://oaxaca.page>. This repository holds the source the distro is built from.

## What Oaxaca runs on

- A 64-bit Intel or AMD PC that starts in UEFI mode. Computers that start only in the older BIOS mode are not supported; on a computer whose firmware offers both modes, Oaxaca starts when UEFI mode is selected. To see which mode a computer's current system started in: on Windows, System Information (`msinfo32`) shows "BIOS Mode: UEFI" or "BIOS Mode: Legacy"; on Linux, the folder `/sys/firmware/efi` exists only after a start in UEFI mode, and `[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS` prints which.
- At least 4 GB of memory and 20 GB of disk space.
- The first computer Oaxaca is made for, and the one Oaxaca is tested on, is a Lenovo Legion Pro 7 laptop with Intel and NVIDIA graphics. The fixes Omarchy carries for other laptops (ASUS, Dell XPS, Framework, Microsoft Surface, MacBooks) are applied at installation on the models they are for.

## Apple hardware

Oaxaca has not been tried on a Mac yet. The Mac support below is Omarchy's, adapted to Ubuntu, and the installer applies each Mac fix only on the models it is for.

- **Apple Studio Display:** brightness works, from the keyboard's brightness keys and the desktop's controls. Linux has no standard way to set the Studio Display's brightness; Oaxaca includes a program that sets the brightness over the display's USB connection.
- **MacBooks from 2012 and early 2013:** the installer sets up the Wi-Fi chip (Broadcom BCM4331), which needs a network connection during installation to download the chip's firmware.
- **Macs from 2015 on with Broadcom Wi-Fi:** Wi-Fi connects to networks that accept both WPA2 and WPA3. On these Macs the Wi-Fi chip's own firmware fails the connection handshake with such networks, which looks like a rejected password, so Oaxaca has the system perform the handshake instead.
- **The 12-inch MacBook (2015 to 2017) and the 2016 and 2017 MacBook Pros:** the keyboard, which connects over SPI rather than USB, works at the disk encryption prompt during startup, and the built-in SSD wakes up after sleep.
- **Not supported:** Macs with Apple's T2 chip (most Macs from 2018 to 2020), Macs with Apple silicon (M1 and later), and the Broadcom BCM4360 Wi-Fi of 2013 to 2015 MacBooks, for which Oaxaca installs no driver.

## License

Oaxaca's own files, the build scripts, configuration, packaging and documentation in this repository, are under the MIT license, copyright 2026 santisbon: see [LICENSE](LICENSE). The software Oaxaca installs keeps its own licenses. Ubuntu's packages carry theirs, and each package built in this repository lists its licenses, file by file, in its `debian/copyright`: the Omarchy desktop is MIT, like Omarchy itself, and the third-party programs Oaxaca packages keep their upstream licenses, such as GPL-2+ for `asdcontrol`, LGPL-3.0 for Quickshell and the SIL Open Font License for the fonts. The license covers the code, not the name Oaxaca.

## More

- [docs/README.md](docs/README.md): the developer README. How Oaxaca is built, how the installed system differs from a stock Ubuntu in detail (software recommendations, Secure Boot, graphics, the Omarchy desktop and how Omarchy's plugins run on Ubuntu), and the status of each part of the project.
- [docs/0 - plan.md](docs/0%20-%20plan.md): the plan and the reasoning behind Oaxaca's choices.
