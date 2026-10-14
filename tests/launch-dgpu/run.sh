#!/bin/bash
# tests/launch-dgpu/run.sh <fork checkout>: check the port's discrete-GPU launch path, un-renamed,
# from a checkout of the Omarchy fork (default ~/Projects/omarchy). Two programs from the fork's
# bin/: omarchy-launch-desktop, which the menu runs and which decides whether an application
# goes to the discrete GPU (--print shows the decision without starting anything), and
# omarchy-launch-dgpu, which sets the variables for that GPU and runs the command (here "env",
# so the variables can be read). Desktop entries and the app lists live in a temporary
# XDG_DATA_HOME and XDG_CONFIG_HOME; nothing is launched (docs/7, choice 43).
set -u
fork=${1:-$HOME/Projects/omarchy}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/data/applications" "$work/config/omarchy"
printf '[Desktop Entry]\nName=Game\nExec=game\nPrefersNonDefaultGPU=true\n' > "$work/data/applications/game.desktop"
printf '[Desktop Entry]\nName=Editor\nExec=editor\n' > "$work/data/applications/editor.desktop"
printf '[Desktop Entry]\nName=Recorder\nExec=recorder\n' > "$work/data/applications/recorder.desktop"
printf '[Desktop Entry]\nName=Files\nExec=files\n' > "$work/data/applications/files.desktop"
printf 'recorder\n' > "$work/config/omarchy/dgpu-apps"
printf 'editor\n' > "$work/config/omarchy/nvidia-apps"
run() { env -u OMARCHY_GPU_OFFLOAD -u OMARCHY_GPU_OFFLOAD_DEVICE PATH="$fork/bin:$PATH" XDG_DATA_HOME="$work/data" XDG_DATA_DIRS=/nonexistent XDG_CONFIG_HOME="$work/config" "$@"; }
fail=0
expect() { # expect <label> <pattern> <output>
  if grep -qE -- "$2" <<<"$3"; then echo "ok   $1"; else echo "FAIL $1: wanted /$2/ in: $3"; fail=1; fi
}
for app in game editor recorder; do
  out=$(run omarchy-launch-desktop --print $app)
  expect "not hybrid: $app on the display GPU" "runs on the display GPU \(not a hybrid" "$out"
  out=$(run OMARCHY_GPU_OFFLOAD=amd OMARCHY_GPU_OFFLOAD_DEVICE=pci-0000_03_00_0 omarchy-launch-desktop --print $app)
  expect "amd: $app on the AMD GPU" "runs on the AMD discrete GPU \(DRI_PRIME=pci-0000_03_00_0\)" "$out"
  expect "amd: $app through omarchy-launch-dgpu" "command: uwsm-app -- omarchy-launch-dgpu gtk-launch $app.desktop" "$out"
  out=$(run OMARCHY_GPU_OFFLOAD=nvidia omarchy-launch-desktop --print $app)
  expect "nvidia: $app on the NVIDIA GPU" "runs on the NVIDIA GPU" "$out"
done
out=$(run OMARCHY_GPU_OFFLOAD=amd omarchy-launch-desktop --print files)
expect "amd: files (not asking, not listed) on the display GPU" "runs on the display GPU \(its entry does not ask" "$out"
expect "amd: files started without the launcher" "command: uwsm-app -- gtk-launch files.desktop" "$out"
printf 'recorder\n-game\n' > "$work/config/omarchy/dgpu-apps"
out=$(run OMARCHY_GPU_OFFLOAD=amd omarchy-launch-desktop --print game)
expect "amd: game kept on the display GPU by -game" "runs on the display GPU \(kept there by .*dgpu-apps\)" "$out"
out=$(run OMARCHY_GPU_OFFLOAD=amd OMARCHY_GPU_OFFLOAD_DEVICE=pci-0000_03_00_0 omarchy-launch-dgpu env)
expect "amd launcher sets DRI_PRIME to the address" "^DRI_PRIME=pci-0000_03_00_0$" "$out"
out=$(run OMARCHY_GPU_OFFLOAD=amd omarchy-launch-dgpu env)
expect "amd launcher without an address uses DRI_PRIME=1" "^DRI_PRIME=1$" "$out"
out=$(run OMARCHY_GPU_OFFLOAD=nvidia VK_DRIVER_FILES=x omarchy-launch-dgpu env)
expect "nvidia launcher sets PRIME render offload" "^__NV_PRIME_RENDER_OFFLOAD=1$" "$out"
grep -q '^VK_DRIVER_FILES=' <<<"$out" && { echo "FAIL nvidia launcher kept VK_DRIVER_FILES"; fail=1; } || echo "ok   nvidia launcher drops the Mesa-only Vulkan list"
grep -q '^DRI_PRIME=' <<<"$out" && { echo "FAIL nvidia launcher set DRI_PRIME"; fail=1; } || echo "ok   nvidia launcher leaves DRI_PRIME unset"
out=$(run omarchy-launch-dgpu env 2>&1)
expect "no discrete GPU: runs unchanged with a note" "no discrete GPU beside the display GPU" "$out"
exit $fail
