# Suspend/resume baseline on the current install

*Wording revised 2026-10-05 to follow the documentation guidelines (terms defined before use, subjects named); measurements, facts and dates unchanged.*

The plan says: before building anything, run `systemctl suspend` on the current Ubuntu 26.04.1 install with the lid open, with the lid closed, and docked to the Studio Display. Then a later sleep failure on the new distro can be blamed on the firmware or on the distro. This file holds that baseline. Raw logs stay outside the repo in `~/.local/state/oaxaca/suspend-baseline/`; only summaries go into this file.

## Terms

Each entry uses only terms defined above it. The first use of each term in the rest of this file links to its entry here.

### sysfs and procfs

Two virtual filesystems through which the kernel exposes its state as files: `/sys` (sysfs, one directory per device and driver) and `/proc` (procfs, process and driver information). Reading a file there is a query; writing to some of them is a command. Every path under `/sys` and `/proc` in this document is one of those files.

### Internal panel and Studio Display

The two screens in play. The internal panel is the laptop's built-in display. The Studio Display is an Apple 5K monitor attached over Thunderbolt; the same cable carries the monitor's USB hub (its USB device ID is `05ac:1114`) and its audio. "Docked" in this document means the Studio Display's cable is plugged in.

### PCI device and DRM connector

A PCI device is addressed as `0000:02:00.0` (domain, bus, device, function); the NVIDIA GPU is `0000:02:00.0` and the Intel GPU is `0000:00:02.0`. Each GPU driver registers a DRM card under `/sys/class/drm/`: `card1` is the Intel GPU (driver `i915`) and `card2` is the NVIDIA GPU. Each card has connectors, named `card1-eDP-1` (the internal panel, on the Intel GPU), `card1-DP-1` and `card1-DP-2` (the two DisplayPort paths over Thunderbolt, where the Studio Display appears), and `card2-eDP-2` (an NVIDIA-side panel connector that is wired to nothing on this laptop). A connector's `status` file reads `connected` or `disconnected`, and its `enabled` file says whether the compositor is driving it.

### Suspend states: S3 "deep" and s2idle

Two ways the kernel can suspend to RAM. S3, which Linux calls `deep`, is the firmware's sleep state: almost everything is powered off and RAM is kept refreshed. s2idle is "suspend to idle": the kernel keeps running in a low-power idle loop and relies on every device, and on a platform state called S0ix, to save power. `/sys/power/mem_sleep` is the kernel's list of the modes the machine supports, with the default in brackets; on this laptop that file reads `s2idle [deep]`. `/sys/power/state` lists the sleep kinds a program can request by writing to `/sys/power/state` (`freeze`, `mem`, `disk`); `systemctl suspend` ends up writing `mem`, and the kernel then uses the `mem_sleep` default. The NVIDIA driver's own flag for s2idle support, `EnableS0ixPowerManagement`, is a module parameter visible in `/proc/driver/nvidia/params`.

### Wake and resume

Wake is the hardware event that ends the sleep: a key press, the lid opening, or the RTC alarm firing. Resume is what follows: the kernel restores device state and writes `PM: suspend exit`, then systemd's sleep units and hooks run their "after" half, then the user session carries on. The systemd unit named `nvidia-resume.service` is one step of resume, never the whole thing.

### Hibernation

Suspend to disk: the kernel writes RAM to swap and powers off fully. `/sys/power/disk` lists the hibernation methods, or reads `[disabled]` when the kernel forbids hibernation. Why Secure Boot forbids it, and why this project leaves hibernation out of the first release, is explained in [policy.md, "Suspend, hibernate and Secure Boot"](1%20-%20policy.md#suspend-hibernate-and-secure-boot).

### Secure Boot and lockdown

Secure Boot is the firmware feature that only boots signed boot loaders and kernels. Lockdown is the kernel mode Ubuntu's kernel enters when Secure Boot is on; `/sys/kernel/security/lockdown` shows the mode (`[none]`, `integrity` or `confidentiality`). Lockdown `integrity` is what makes `/sys/power/disk` read `[disabled]`. Both are explained in [policy.md, section 5](1%20-%20policy.md#5-requirements-every-later-step-must-keep).

### Journal and the kernel's PM lines

The journal is systemd's log, read with `journalctl`. The kernel writes two lines to the journal around every suspend: `PM: suspend entry (deep)` when the suspend begins and `PM: suspend exit` when resume begins. One matched pair per cycle is this document's pass/fail signal. "err" and "warning" counts in the results are journal entries at those priorities in the window between the suspend command and the after-resume snapshot.

### logind

`systemd-logind`, the systemd service that manages login sessions, seats and power events. `systemctl suspend` asks logind, and logind decides when the machine may sleep. logind announces an upcoming sleep to every interested program with a D-Bus signal, `PrepareForSleep(true)`, and announces the resume with `PrepareForSleep(false)`.

### Inhibitor

A hold a program registers with logind to influence a sleep or shutdown. A *block* inhibitor prevents the action, or, for key and lid events, claims them so logind leaves them to the program; KDE's PowerDevil holds one of those for the lid switch and the power keys. A *delay* inhibitor only asks for a few seconds before the sleep proceeds, so the program can save state or lock the screen. `systemd-inhibit --list` prints the current inhibitors.

### systemd-sleep and the system-sleep hooks

`systemd-sleep` is the program that `systemd-suspend.service` runs to perform the sleep. Before writing to `/sys/power/state` it runs every executable in `/usr/lib/systemd/system-sleep/` with the argument `pre`, and after resume it runs them again with `post`. Those executables are the system-sleep hooks; on this install they are `hdparm`, `nvidia`, `sysstat.sleep` and `unattended-upgrades`. `systemd-sleep` reads an environment variable, `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS`, that decides whether user sessions are frozen during sleep; the NVIDIA driver package sets it to `false` through a drop-in file, `/usr/lib/systemd/system/systemd-suspend.service.d/nvidia-suspend-nofreeze.conf`.

### NVIDIA sleep units and PreserveVideoMemoryAllocations

Three systemd units shipped by the NVIDIA driver package: `nvidia-suspend.service`, ordered before `systemd-suspend.service`; `nvidia-resume.service`, ordered after it; and `nvidia-hibernate.service`. The first two run `nvidia-sleep.sh suspend` and `nvidia-sleep.sh resume`. Because the dGPU loses power in S3, the driver has to save video memory somewhere; two module parameters control that, set in `/etc/modprobe.d/nvidia-graphics-drivers-kms.conf` as `options nvidia NVreg_PreserveVideoMemoryAllocations=1` and `NVreg_TemporaryFilePath=/var`, and readable in `/proc/driver/nvidia/params`. With `PreserveVideoMemoryAllocations=1`, used VRAM is written to a file under `/var` on suspend and restored on resume.

### RTC wake alarm

The real-time clock chip can wake the machine at a set time. `rtcwake -m no -s N` programs an alarm `N` seconds ahead and exits without suspending; `/sys/class/rtc/rtc0/wakealarm` shows the programmed time. `scripts/suspend-baseline.sh` uses that alarm so the machine wakes by itself and a test needs no one at the keyboard. `rtcwake -m mem` would instead suspend directly by writing to `/sys/power/state`, bypassing logind, the inhibitors and the sleep units, which is why the script never uses that mode.

### Snapshot (of device state)

In this document, a snapshot is the device-state record that `scripts/suspend-baseline.sh` prints: lid state, power source, battery, the enabled DRM connectors, whether the Studio Display's USB device is present, the count of Thunderbolt devices, Wi-Fi state, Bluetooth power, the default audio sink, the dGPU's power state, `nvidia-smi` output, the `prime-select` mode, and `failed_units`, the number of systemd units in the `failed` state. The script takes one snapshot before suspending and one after resume and prints the difference. The word has nothing to do with aptly snapshots.

### PCI runtime power management and prime-select

The kernel can power a PCI device down while it is idle. Two sysfs files under `/sys/bus/pci/devices/<address>/power/` show the state: `runtime_status` (`active` or `suspended`) and `control` (`auto` lets the kernel power that PCI device down, `on` forbids that). `prime-select` is Ubuntu's tool for choosing the hybrid-graphics mode; `prime-select query` prints the mode. In `nvidia` mode Ubuntu keeps the dGPU's `control` at `on`, so the dGPU never powers down; `on-demand` mode allows it. "Runtime D3" is the NVIDIA driver's name for the same power-down, reported in `/proc/driver/nvidia/gpus/<address>/power`.

### PCIe AER

PCI Express Advanced Error Reporting: a mechanism by which a PCIe device reports bus errors to the kernel, which logs them with a severity (`Non-Fatal` means the reporting device recovered or can be reset) and an error type such as `ACSViol`, an access-control violation. The kernel then tries to recover the reporting device through its driver; "device recovery failed" means the driver had no recovery callback, not that the device stopped working.

### Thunderbolt bridge

Inside the Studio Display sits a Thunderbolt controller (an Intel Titan Ridge, PCI ID `8086:15ef`) that bridges the monitor's USB hub and audio onto the PCIe bus. On this laptop that bridge is the PCI device `0000:05:02.0`, with the Studio Display's USB controller behind it. The laptop's own Thunderbolt controllers are separate PCI devices (`0000:00:0d.0` is the laptop's Thunderbolt USB host controller).

### udev rule

A line in a file under `/etc/udev/rules.d/` or `/usr/lib/udev/rules.d/` that tells udev, the kernel-device event handler, what to do when a device appears or disappears. A rule can tag a device for systemd and name a unit to start whenever the device is added.

### Phantom backlight device

The NVIDIA driver registers a backlight device, `/sys/class/backlight/nvidia_0`, even though the internal panel is wired to the Intel GPU; the real backlight device is `/sys/class/backlight/intel_backlight`, which sits under the `card1-eDP-1` connector. Brightness tools that pick the first backlight device, or rescale between the two, set the wrong brightness. The workaround on this install shadows `nvidia_0`'s sysfs directory with an empty tmpfs mount; the full analysis is in the homelab repo, `laptop/laptop-backlight-wake-fix.md`.

### KDE session pieces

Names from the current install that appear in the results. PowerDevil is KDE's power-management daemon; its settings live in `~/.config/powerdevilrc` (INI format), where the `LidAction` key in the `[AC][SuspendAndShutdown]` group sets what closing the lid does. kwin is KDE's compositor. kscreenlocker is KDE's lock screen. None of them exist on the new distro, where Hyprland and the ported Omarchy units take those jobs.

### obexd

BlueZ's OBEX daemon, the user-session service that implements Bluetooth file transfer. Its systemd unit is `obex.service` in the user manager. Bluetooth itself (pairing, audio, mice) works without obexd.

### thermald

Intel's thermal daemon, a system service that reads platform thermal tables. On this laptop it logs "Unable to read odvp..." lines continuously; those lines are unrelated to suspend and only inflate the error counts.

## How a suspend runs on this install

You run `systemctl suspend` (or press a key bound to that command). The pieces that run, in order:

1. `systemctl` asks [logind](#logind). logind checks *block* [inhibitors](#inhibitor), sends `PrepareForSleep(true)` to the session, and gives *delay* inhibitors a few seconds (KDE's kwin uses a delay inhibitor to lock the screen; 1Password, VS Code and others use one to save state).
2. logind starts `systemd-suspend.service`. The [NVIDIA sleep unit](#nvidia-sleep-units-and-preservevideomemoryallocations) `nvidia-suspend.service` runs first (`Before=`) and calls `nvidia-sleep.sh suspend`, which writes used video memory to `/var` because `PreserveVideoMemoryAllocations=1`.
3. `systemd-sleep suspend` runs every [system-sleep hook](#systemd-sleep-and-the-system-sleep-hooks) in `/usr/lib/systemd/system-sleep/` with `pre` (`hdparm`, `nvidia`, `sysstat.sleep`, `unattended-upgrades` today), then writes `mem` to `/sys/power/state`. The kernel uses `deep` ([S3](#suspend-states-s3-deep-and-s2idle)), the default in `/sys/power/mem_sleep`.
4. On [wake](#wake-and-resume) the same hooks run with `post`, `nvidia-resume.service` calls `nvidia-sleep.sh resume`, and logind sends `PrepareForSleep(false)`.

The kernel writes `PM: suspend entry (deep)` and `PM: suspend exit` to the [journal](#journal-and-the-kernels-pm-lines) around step 3. Those two lines are the pass/fail signal.

**Waking the machine.** `scripts/suspend-baseline.sh` sets an [RTC wake alarm](#rtc-wake-alarm) with `rtcwake -m no` before suspending, so the machine wakes by itself. Setting the alarm needs root once per run. The alarm path (`rtcwake -m no` then `systemctl suspend`) keeps the full logind path above; `rtcwake -m mem` would skip that logind path, which is why the script does not use `rtcwake -m mem`.

## State before any test (2026-09-30)

| Item | Value | Note |
|---|---|---|
| OS, kernel, session | Ubuntu 26.04.1 LTS, 7.0.0-34-generic, KDE Plasma on Wayland | |
| Suspend history | none in 19 recorded boots | Confirms the plan's "no baseline" |
| `/sys/power/mem_sleep`, the kernel's suspend-to-RAM modes | `s2idle [deep]` | S3 (`deep`) is the default |
| Lid, power | open, on AC, battery 100% | |
| Docked | yes. [Studio Display](#internal-panel-and-studio-display) on the Intel GPU's [DRM connector](#pci-device-and-drm-connector) `DP-1`, the Studio Display's USB device `05ac:1114` present, 3 Thunderbolt devices | `DP-2` shows connected but disabled; `DP-2` is the second Thunderbolt DisplayPort path |
| Display outputs | `eDP-1` (the internal panel) and `DP-1` enabled, both on the Intel iGPU (`card1`, driver `i915`). The NVIDIA GPU is `card2` with nothing connected | matches the plan's inventory |
| NVIDIA | driver 595.91.07, the three NVIDIA sleep units `nvidia-suspend`/`-resume`/`-hibernate` enabled, module parameters `PreserveVideoMemoryAllocations=1` and `TemporaryFilePath=/var` (622 GB free on that filesystem), 384 MiB VRAM in use | |
| dGPU [runtime power management](#pci-runtime-power-management-and-prime-select) | `runtime_status=active`, `control=on`, `runtime_enabled=forbidden` under the dGPU's `power/` directory; `prime-select query` says `nvidia` | **Differs from the plan.** Ubuntu's `prime-select nvidia` mode keeps the dGPU always on. The NVIDIA driver itself reports fine-grained runtime D3 enabled, so switching `prime-select` to `on-demand` should allow the dGPU to power off. The mode was not changed for the baseline |
| [Secure Boot, lockdown](#secure-boot-and-lockdown) | **off for now**, lockdown `[none]` | The plan's 2026-09-25 inventory (Secure Boot on, lockdown `integrity`) was correct at the time. Secure Boot was turned off afterwards for an unrelated Linux From Scratch exercise, now finished. The distro must support Secure Boot (see [policy.md](1%20-%20policy.md), section 5). S3 suspend does not depend on Secure Boot or lockdown, and the NVIDIA modules are Canonical-signed either way, so the results below stand. Hibernation availability does depend on Secure Boot (next row). Secure Boot stays off on this laptop while the laptop dual-boots LFS; the distro supports Secure Boot without requiring it. Re-run scenario 1 with Secure Boot on during the per-release Secure Boot pass to confirm nothing changes |
| [Hibernation](#hibernation) | `/sys/power/disk` reads `[platform]`, so hibernation is available today, and an 8 GB swapfile exists | Only because Secure Boot is off. With Secure Boot on, lockdown `integrity` makes `/sys/power/disk` read `[disabled]`, as the plan says. 8 GB swap is too small for 30 GiB RAM anyway. Hibernation is out of the first release for scope (policy.md, section 5) |
| S0ix | the NVIDIA driver reports platform support "Not Supported", and its module parameter `EnableS0ixPowerManagement` is `0` | The plan's s2idle fallback would run without NVIDIA's S0ix support |
| Sleep inhibitors | delay: NetworkManager, rtkit, UPower, kwin (screen lock), 1Password, VS Code, Mullvad, Claude desktop. block: none for sleep | [KDE's PowerDevil](#kde-session-pieces) holds a block inhibitor on the lid switch and power keys, meaning KDE handles those events itself, not logind |
| KDE lid action (`LidAction` in `~/.config/powerdevilrc`) | `LidAction=32` = lock screen only; "inhibit lid action when an external monitor is present" is off | **Closing the lid never suspends on this install.** For the lid-closed scenario the script's `--delay` option is needed, so `systemctl suspend` runs after the lid is shut |
| Wi-Fi, Bluetooth, audio | Wi-Fi connected, Bluetooth powered, default sink is the Studio Display | |
| Failed systemd units before test | 1 (`user@107.service`, unrelated) | so `failed_units=1` in the script's [snapshot](#snapshot-of-device-state) is the baseline, not a regression |
| ACPI wake sources enabled (from `/proc/acpi/wakeup`) | USB host controller (`XHCI`), Thunderbolt (`TXHC`, `TDM0`, `TRP0`), root ports for Wi-Fi and NVMe, `AWAC` (the RTC alarm path) | The NVIDIA dGPU's PCIe port is disabled as a wake source |

## Scenarios

| # | Scenario | How to run | Result |
|---|---|---|---|
| 1 | Lid open, docked to the Studio Display, on AC | `scripts/suspend-baseline.sh --label lid-open-docked` | see below |
| 2 | Lid closed, docked, on AC | `scripts/suspend-baseline.sh --label lid-closed-docked --delay 30`. Touch the fingerprint reader first (the reader is under the lid), close the lid during the 30 s countdown, leave the lid closed until the alarm wakes the machine and the Studio Display shows the lock screen, then open the lid. Run `scripts/suspend-baseline.sh --snapshot` after opening the lid to record whether the internal panel came back | pass, see below |
| 3 | Lid open, undocked, on battery | unplug the Thunderbolt cable and the charger, then `scripts/suspend-baseline.sh --label lid-open-undocked` | pass, see below |

Scenarios 2 and 3 need hands on the machine (lid, cables). All three were run on 2026-09-30 with the user doing the physical steps.

## Results

### Scenario 1: lid open, docked, on AC. Run 2026-09-30 15:34. **Pass.**

Command: `scripts/suspend-baseline.sh --label lid-open-docked` (RTC alarm 90 s). Log: `~/.local/state/oaxaca/suspend-baseline/20260930T153428-lid-open-docked.log`.

| Check | Result |
|---|---|
| Kernel PM lines | `PM: suspend entry (deep)` at 15:34:36, `ACPI: PM: Waking up from system sleep state S3`, `PM: suspend exit` at 15:36:08. One matched pair, S3 confirmed, 92 s asleep |
| Woken by | the RTC alarm, no key press |
| NVIDIA sleep units | `nvidia-suspend.service` finished before `systemd-suspend.service`, `nvidia-resume.service` finished after `systemd-suspend.service`, all successful |
| Display outputs | `eDP-1` and `DP-1` enabled before and after. Studio Display USB device present, 3 Thunderbolt devices, both before and after |
| Wi-Fi, Bluetooth, audio | Wi-Fi connected, Bluetooth powered, default sink still the Studio Display. The Bluetooth mouse reconnected 8 s after resume |
| NVIDIA | `nvidia-smi` works after resume, VRAM in use 384 MiB before, 390 MiB after |
| Session | KDE locked the screen before sleep; the KDE session and the terminal running the script survived |
| Journal counts in the window | kernel err 7, kernel warning 4, userspace err 99 (85 of them [thermald](#thermald)) |

Issues and noise seen. All belong to the current install and are the "known before the distro" list:

- **[obexd](#obexd) crashes at suspend, and stays down.** BlueZ's OBEX daemon (Bluetooth file transfer, a user service) aborted with `SIGABRT` at 15:34:36, the moment obexd's Bluetooth transport disconnected for sleep. obexd's core-dump handling was frozen through the sleep. After resume, Ubuntu's `apport-coredump-hook@` failed (exit 1, process gone) and KDE's `drkonqi-coredump-processor@` timed out 5 minutes later, which is why `failed_units` went from 1 to 3. The user session tried to restart `obex.service` five times during resume ("obex_server_init failed", Bluetooth wasn't back yet) and left it `failed`. Bluetooth itself is fine. Compare on the new distro: Omarchy's Bluetooth panel doesn't need obexd, only `blueman` (optional) does.
- **[PCIe AER](#pcie-aer) non-fatal error on the Studio Display's [Thunderbolt bridge](#thunderbolt-bridge) at resume.** `pcieport 0000:05:02.0` (PCI ID `8086:15ef`, the Titan Ridge bridge inside the Studio Display) reported an ACS violation. The kernel logged "device recovery failed" because the USB controller behind the bridge has no recovery callback. The Studio Display's USB hub, audio and Thunderbolt link all still work, so treat the AER error as noise unless the Studio Display's USB devices ever go missing after sleep.
- Ethernet (`igc`, I226-V): three `Timeout reading IGC_PTM_STAT register` lines and "can't disable ASPM; OS doesn't have ASPM control" at resume. No cable is plugged in. Harmless.
- `i915` (the Intel GPU driver): "PHY A failed to request refclk" once before sleep and once after. The same line also appears in normal operation, so the line is not a resume symptom.
- `ACPI: button: The lid device is not compliant to SW_LID` at resume. The kernel re-reads the lid switch after wake and complains about the firmware's reporting. Watch for that line in scenario 2, since a misread lid switch can affect lid-state detection after wake.
- `systemd-sleep` logged `User sessions remain unfrozen on explicit request ($SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0)` with its own "not recommended" warning. Ubuntu's NVIDIA driver package ships that setting as the drop-in file `/usr/lib/systemd/system/systemd-suspend.service.d/nvidia-suspend-nofreeze.conf`. Decide on purpose for the new distro whether to keep that setting (NVIDIA's documentation favors unfrozen sessions) or use systemd's default of freezing sessions.
- thermald: 85 "Unable to read odvp..." lines in the window. The same spam happens without a suspend. Ignore those lines.
- kscreenlocker: `pam_sss.so` missing. That message happens on every screen lock, unrelated to suspend.

### Scenario 2: lid closed, docked, on AC. Run 2026-09-30 15:58. **Pass.**

Command: `scripts/suspend-baseline.sh --label lid-closed-docked --delay 30` (RTC alarm 120 s from the sudo step, 90 s after the suspend command). Log: `~/.local/state/oaxaca/suspend-baseline/20260930T155831-lid-closed-docked.log`.

Timeline, from logind and the kernel:

| Time | Event |
|---|---|
| 15:58:41 | `Lid closed.` (logind). KDE locked the screen; the script's countdown kept running |
| 15:59:05 | `systemctl suspend`, lid reported `closed` at that moment |
| 15:59:06 | `PM: suspend entry (deep)` |
| 16:00:40 | `ACPI: PM: Waking up from system sleep state S3`, `PM: suspend exit`. Woken by the RTC alarm with the lid still closed. 94 s asleep |
| 16:00:53 | after-resume snapshot, lid still closed: every tracked device back, `eDP-1` connector still enabled |
| 16:02:01 | `Lid opened.` (logind), 80 s after resume |
| 16:04:33 | snapshot after opening the lid: `eDP-1` and `DP-1` enabled, Studio Display USB present, audio sink unchanged |

| Check | Result |
|---|---|
| Kernel PM lines | one matched entry/exit pair, S3 confirmed |
| NVIDIA sleep units | `nvidia-suspend` and `nvidia-resume` ran and finished successfully, same order as scenario 1 |
| Display outputs | `DP-1` (Studio Display) and `eDP-1` enabled before, after resume with the lid closed, and after opening the lid. KDE kept the internal panel's connector active with the lid closed; only the internal panel's backlight was off |
| Wi-Fi, Bluetooth, audio, Thunderbolt | all unchanged before and after |
| NVIDIA | `nvidia-smi` works after resume, VRAM 384 MiB before, 390 MiB after |
| obexd | did not crash this time; obexd's `obex.service` is still `failed` from scenario 1 because nothing restarted that unit |
| Journal counts in the window | kernel err 7 (same Thunderbolt AER and Ethernet PTM lines as scenario 1), kernel warning 2, userspace err 85 (all thermald) |

Differences from scenario 1:
- The `ACPI: button: The lid device is not compliant to SW_LID` warning did not appear in this run, even though scenario 2 is the run where the lid state mattered. logind reported the lid close and the lid open correctly.
- No obexd crash, so the `failed_units` count stayed at 3. The crash in scenario 1 is not reproducible every time.
- Visual check after opening the lid: the internal panel came back showing content, with no key press needed (user's observation, 2026-09-30).

### Scenario 3: lid open, undocked, on battery. Run 2026-09-30 16:08. **Pass.**

Command: `scripts/suspend-baseline.sh --label lid-open-undocked` (RTC alarm 90 s). Log: `~/.local/state/oaxaca/suspend-baseline/20260930T160817-lid-open-undocked.log`. Before the run: charger and Thunderbolt cable unplugged, only `eDP-1` connected, audio on the internal codec, Thunderbolt showing the host controller only.

| Check | Result |
|---|---|
| Kernel PM lines | `PM: suspend entry (deep)` at 16:08:24, `ACPI: PM: Waking up from system sleep state S3`, `PM: suspend exit` at 16:09:57. One matched pair, S3 confirmed, 93 s asleep |
| Woken by | the RTC alarm, no key press |
| NVIDIA sleep units | `nvidia-suspend` and `nvidia-resume` ran and finished successfully, same order as before |
| Display output | `eDP-1` enabled before and after |
| Wi-Fi | disconnected for sleep at 16:08:22, reconnected at 16:10:07, 10 s after resume |
| Bluetooth, audio | powered and unchanged; default sink still the internal codec |
| Battery | 100% before, 99% after, for about 2 minutes including the sleep |
| NVIDIA | `nvidia-smi` works after resume, VRAM 264 MiB before, 270 MiB after |
| Journal counts in the window | kernel err 3 (all Ethernet PTM timeouts), kernel warning 2, userspace err 70 (68 thermald, 2 kscreenlocker) |

Differences from scenarios 1 and 2:
- **No PCIe AER error.** With the Studio Display unplugged, the `pcieport 0000:05:02.0` ACS violation did not occur. That absence pins the error to the Studio Display's Thunderbolt bridge.
- **New warning:** `xhci_hcd 0000:00:0d.0: xHC error in resume, USBSTS 0x401, Reinit`. That line is the laptop's Thunderbolt USB host controller reinitializing itself at resume with nothing attached. No USB device was affected. Watch for that warning on the new distro when something is plugged into that port after resume.
- No obexd crash; `failed_units` stayed at 3.

## Conclusions

- **The firmware and kernel handle S3 in all three states.** Three of three cycles passed, docked and undocked, lid open and closed, on AC and on battery. The internal panel, the Studio Display over Thunderbolt, the Studio Display's USB hub, Wi-Fi, Bluetooth, audio and the NVIDIA driver came back every time, and `nvidia-suspend`/`nvidia-resume` ran cleanly with `PreserveVideoMemoryAllocations=1`. A suspend failure on the new distro is therefore the distro's problem, not the hardware's, unless the failure is one of the known items below.
- **Known noise to expect on the new distro, not regressions:** the non-fatal PCIe AER error from the Studio Display's Thunderbolt bridge at resume; the Ethernet `igc` PTM timeouts and ASPM warning when no cable is plugged in; the `i915` "PHY A failed to request refclk" line; the Thunderbolt USB controller's "xHC error in resume, Reinit" when undocked; and the occasional `ACPI: button: The lid device is not compliant to SW_LID` line.
- **Side effect found afterwards: suspend undoes the boot-time `nvidia_0` backlight hide.** The workaround from the homelab repo (`laptop/laptop-backlight-wake-fix.md`) shadows the [phantom backlight device](#phantom-backlight-device) `nvidia_0` with a tmpfs mount once at boot. The NVIDIA driver unregisters that device during `nvidia-suspend.service` (the journal shows the mount unit deactivating at 15:34:35, one second into the first suspend) and registers it again in `nvidia-resume.service` (the sysfs directory's timestamp is 16:09:58, the second the last resume ran). The new directory is not shadowed, so the KDE brightness bug the workaround prevents is back after any suspend. This laptop had never suspended before 2026-09-30, which is why the boot-time hide held until then. Fixed the same day with a [udev rule](#udev-rule) that starts the hide unit on every add of the backlight device, verified with one more suspend cycle (the homelab note has the details); on the new distro the phantom backlight device still exists, and whatever sets brightness on the new distro (Omarchy's shell backlight step, `brightnessctl`) must be checked to pick `intel_backlight`.
- **Known regression on the current install:** obexd can crash at suspend (seen once in three runs) and obexd's user service is not restarted. Omarchy's Bluetooth panel does not need obexd, so the new distro is only affected if `blueman` is installed for file transfer.
- **Waking:** the RTC alarm wakes the machine from S3 in every state, including with the lid closed. That reliability makes an unattended suspend test possible on the new distro (plan's 10-cycle test), with the same script and `rtcwake -m no`.
- **Reproduce on the new distro** with `scripts/suspend-baseline.sh`, which only needs systemd, `rtcwake`, `nmcli`, `bluetoothctl`, `wpctl`, `nvidia-smi` and `lspci`. `prime-select` is Ubuntu-only and reports `n/a` elsewhere.
- **Baseline caveats:** taken with Secure Boot off (see the state table) and with KDE handling the lid, screen lock and the sleep inhibitors. On the new distro those three jobs come from Hyprland, the ported `omarchy-sleep-lock.service` and the lid binding, so the userspace half of the sleep path changes; the kernel and firmware half is what this baseline proves.
