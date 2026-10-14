#!/usr/bin/env bash
# suspend-baseline.sh: run one suspend/resume cycle on the current install and keep evidence.
#
# Anatomy: you run this script. It (1) records device state, (2) asks root to set an RTC
# wake alarm with `rtcwake -m no`, so the machine wakes itself, (3) runs `systemctl suspend`,
# which goes through logind, systemd-suspend.service, the nvidia-suspend/resume units and
# the /usr/lib/systemd/system-sleep/ hooks exactly as a key press or a menu entry would,
# (4) waits for the kernel's "PM: suspend exit" line, then (5) records device state again
# and pulls the journal lines for that window. Full logs go to a state dir outside the repo;
# only the printed summary is meant for docs/suspend-baseline.md.
#
# Usage: scripts/suspend-baseline.sh --label <name> [--alarm <sec>] [--delay <sec>] [--no-alarm] [--dry-run]
#   --label     scenario name, e.g. lid-open-docked, lid-closed-docked, lid-open-undocked
#   --alarm     seconds between the suspend command and the RTC alarm (default 90)
#   --delay     seconds to wait before suspending, so you can close the lid first (default 0)
#   --no-alarm  suspend without a wake alarm; you wake the machine yourself
#   --dry-run   record state and journal checks only, no alarm, no suspend
#   --snapshot  print the device state and exit, no log (for a check after opening the lid)
#
# Logs: $SUSPEND_BASELINE_DIR or ~/.local/state/oaxaca/suspend-baseline/
set -uo pipefail

label="" alarm=90 delay=0 use_alarm=1 dry_run=0 snapshot_only=0
while (($#)); do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --alarm) alarm="$2"; shift 2 ;;
    --delay) delay="$2"; shift 2 ;;
    --no-alarm) use_alarm=0; shift ;;
    --dry-run) dry_run=1; shift ;;
    --snapshot) snapshot_only=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
((snapshot_only)) || [[ -n "$label" ]] || { echo "--label is required" >&2; exit 2; }

outdir="${SUSPEND_BASELINE_DIR:-$HOME/.local/state/oaxaca/suspend-baseline}"
((snapshot_only)) || mkdir -p "$outdir"
stamp=$(date +%Y%m%dT%H%M%S)
log="$outdir/$stamp-$label.log"
summary="$outdir/$stamp-$label-summary.txt"

dgpu=$(lspci -D -d 10de: 2>/dev/null | awk '/VGA|3D/ {print $1; exit}')

say() { printf '%s\n' "$*" | tee -a "$log"; }
logonly() { printf '%s\n' "$*" >> "$log"; }

# One line per device, so pre/post can be diffed.
snapshot() {
  echo "lid=$(awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null | head -1)"
  for p in /sys/class/power_supply/*; do
    [[ $(cat "$p/type") == Mains ]] && echo "ac=$(cat "$p/online")"
  done
  for p in /sys/class/power_supply/BAT*; do
    [[ -d $p ]] && echo "battery=$(cat "$p/status") $(cat "$p/capacity")%"
  done
  echo "mem_sleep=$(cat /sys/power/mem_sleep)"
  for c in /sys/class/drm/card*-*; do
    [[ $(cat "$c/status") == connected ]] && echo "connector=$(basename "$c") enabled=$(cat "$c/enabled")"
  done
  echo "studio_display_usb=$(lsusb -d 05ac:1114 >/dev/null 2>&1 && echo present || echo absent)"
  echo "thunderbolt_devices=$(ls /sys/bus/thunderbolt/devices 2>/dev/null | grep -c -v domain)"
  echo "wifi=$(nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$1=="wifi" {print $2; exit}')"
  echo "bluetooth_powered=$(bluetoothctl show 2>/dev/null | awk '/Powered/ {print $2; exit}')"
  echo "audio_default_sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.description/ {print $2; exit}')"
  if [[ -n $dgpu ]]; then
    echo "dgpu_runtime_status=$(cat "/sys/bus/pci/devices/$dgpu/power/runtime_status") control=$(cat "/sys/bus/pci/devices/$dgpu/power/control")"
  fi
  echo "nvidia_smi=$(nvidia-smi --query-gpu=name,memory.used --format=csv,noheader 2>/dev/null || echo FAILED)"
  echo "prime=$(prime-select query 2>/dev/null || echo n/a)"
  echo "failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)"
}

if ((snapshot_only)); then snapshot; exit 0; fi

say "# suspend baseline: $label  ($stamp)"
say "# host kernel $(uname -r), $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2), session ${XDG_SESSION_TYPE:-?}/${XDG_CURRENT_DESKTOP:-?}"
say "## pre"
pre=$(snapshot); say "$pre"
logonly "## inhibitors (pre)"
systemd-inhibit --list --no-legend >> "$log" 2>&1
logonly "## nvidia units"
for u in nvidia-suspend nvidia-resume nvidia-hibernate; do logonly "$u: $(systemctl is-enabled "$u" 2>&1)"; done
logonly "## nvidia params"
grep -E 'PreserveVideoMemoryAllocations|TemporaryFilePath|EnableS0ixPowerManagement|DynamicPowerManagement' /proc/driver/nvidia/params >> "$log" 2>&1
logonly "## nvidia power"
cat "/proc/driver/nvidia/gpus/$dgpu/power" >> "$log" 2>&1

if ((dry_run)); then
  say "## dry run: not suspending. Log: $log"
  exit 0
fi

if ((use_alarm)); then
  total=$((delay + alarm))
  say "## setting RTC wake alarm for $total s from now (sudo: touch the fingerprint reader)"
  if ! sudo rtcwake -m no -s "$total" >> "$log" 2>&1; then
    say "!! could not set the wake alarm (sudo failed). Not suspending. Re-run with --no-alarm to suspend anyway."
    exit 3
  fi
  say "wakealarm=$(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null) (epoch)"
else
  say "## no wake alarm: wake the machine yourself (key press, power button, or lid open)"
fi

if ((delay > 0)); then
  say "## suspending in $delay s. Close the lid now if this is a lid-closed run."
  for ((i = delay; i > 0; i--)); do printf '\r%3d ' "$i"; sleep 1; done; echo
  say "lid_at_suspend=$(awk '{print $2}' /proc/acpi/button/lid/*/state 2>/dev/null | head -1)"
fi

t0=$(date '+%Y-%m-%d %H:%M:%S')
say "## systemctl suspend at $t0"
systemctl suspend || { say "!! systemctl suspend failed"; exit 4; }

# Iterations only tick while awake, so a long sleep doesn't exhaust them.
i=0
until journalctl -b -k --since "$t0" -q -g 'PM: suspend exit' 2>/dev/null | grep -q .; do
  sleep 3; i=$((i + 1))
  if ((i > 400)); then say "!! no 'PM: suspend exit' seen after ~20 min awake. Giving up the wait."; break; fi
done
sleep 10  # let USB, Thunderbolt, Wi-Fi and audio settle
t1=$(date '+%Y-%m-%d %H:%M:%S')

say "## post ($t1)"
post=$(snapshot); say "$post"
say "## pre/post differences"
diff <(echo "$pre") <(echo "$post") | tee -a "$log" || true

logonly "## kernel log $t0 .. $t1"
journalctl -b -k --since "$t0" --until "$t1" -o short-iso --no-pager -q >> "$log" 2>&1
logonly "## sleep units and hooks"
journalctl -b --since "$t0" --until "$t1" -u systemd-suspend.service -u nvidia-suspend.service -u nvidia-resume.service \
  -u systemd-logind.service -t systemd-sleep -t suspend -o short-iso --no-pager -q >> "$log" 2>&1
logonly "## inhibitors (post)"
systemd-inhibit --list --no-legend >> "$log" 2>&1

{
  echo "# $label  $stamp"
  echo "## PM lines"
  journalctl -b -k --since "$t0" --until "$t1" -o short-iso --no-pager -q -g 'PM: |Timekeeping suspended|suspended for' | sed 's/^\([^ ]*\) [^ ]* kernel: /\1 /'
  entry=$(journalctl -b -k --since "$t0" --until "$t1" -o short-iso --no-pager -q -g 'PM: suspend entry' | head -1 | cut -d' ' -f1)
  exit_=$(journalctl -b -k --since "$t0" --until "$t1" -o short-iso --no-pager -q -g 'PM: suspend exit' | tail -1 | cut -d' ' -f1)
  if [[ -n $entry && -n $exit_ ]]; then
    echo "asleep: $(( $(date -d "$exit_" +%s) - $(date -d "$entry" +%s) )) s (wall clock from PM entry to PM exit)"
  else
    echo "asleep: unknown (missing PM entry or exit line)"
  fi
  echo "## sleep units"
  journalctl -b --since "$t0" --until "$t1" -u systemd-suspend.service -u nvidia-suspend.service -u nvidia-resume.service -o short-iso --no-pager -q | sed 's/^\([^ ]*\) [^ ]* /\1 /'
  echo "## counts"
  echo "kernel err: $(journalctl -b -k --since "$t0" --until "$t1" -p err -q --no-pager | wc -l)"
  echo "kernel warning: $(journalctl -b -k --since "$t0" --until "$t1" -p warning..warning -q --no-pager | wc -l)"
  echo "userspace err: $(journalctl -b --since "$t0" --until "$t1" -p err -q --no-pager | grep -v -c ' kernel: ')"
  echo "## kernel err lines (first 20)"
  journalctl -b -k --since "$t0" --until "$t1" -p err -q --no-pager -o short-iso | sed 's/^\([^ ]*\) [^ ]* kernel: /\1 /' | head -20
  echo "## userspace err lines (first 10)"
  journalctl -b --since "$t0" --until "$t1" -p err -q --no-pager -o short-iso | grep -v ' kernel: ' | sed 's/^\([^ ]*\) [^ ]* /\1 /' | head -10
  echo "## devices after resume"
  echo "$post"
  echo "## changed vs before"
  changes=$(diff <(echo "$pre") <(echo "$post") | grep -E '^[<>]' || true)
  echo "${changes:-(no differences)}"
} | tee "$summary"
say "## full log: $log"
say "## summary: $summary"
