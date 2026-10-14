#!/bin/bash
# tests/gpu-env/run.sh: check the session's GPU environment generator (packages/session/gpu-env,
# rendered from gpu-env.in) against made-up machines. Each case builds a fake sysfs tree with
# PCI devices (class, vendor, boot_vga), points the generator's PCI scan at it through
# <ID>_GPU_SYSFS, and compares the hybrid-graphics lines it prints (the EGL and Vulkan
# selections and <ID>_GPU_OFFLOAD*) with the expected ones. Runs as any user, on any machine;
# nothing outside a temporary directory is read for the scan or written.
# Usage: tests/gpu-env/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
source "$here/distro.conf"
up=$(printf '%s' "$DISTRO_ID" | tr 'a-z-' 'A-Z_')
gen="$here/packages/session/gpu-env"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0

# dev <tree> <pci address> <class> <vendor> <boot_vga or ->
dev() {
  local d="$1/bus/pci/devices/$2"
  mkdir -p "$d"; echo "$3" >"$d/class"; echo "$4" >"$d/vendor"
  [[ $5 == - ]] || echo "$5" >"$d/boot_vga"
}
# check <name> <expected lines, ";"-separated, or "none"> then the devices, one "dev" line each
check() {
  local name=$1 want=$2 tree="$work/$1"; shift 2
  mkdir -p "$tree/bus/pci/devices"
  while (($#)); do dev "$tree" $1; shift; done
  got=$(env -u __EGL_VENDOR_LIBRARY_FILENAMES -u AQ_DRM_DEVICES "${up}_GPU_SYSFS=$tree" sh "$gen" 2>/dev/null \
        | grep -E "^(__EGL_VENDOR_LIBRARY_FILENAMES|VK_DRIVER_FILES|${up}_GPU_OFFLOAD|${up}_GPU_OFFLOAD_DEVICE)=" | paste -sd';')
  [[ -z $got ]] && got=none
  if [[ $got == "$want" ]]; then echo "ok   $name: $got"; else echo "FAIL $name: got [$got], want [$want]"; fail=1; fi
}
mesa_egl="__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json"
intel_vk="VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json:/usr/share/vulkan/icd.d/intel_hasvk_icd.json"
radeon_vk="VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.json"

check legion-intel-nvidia "$mesa_egl;$intel_vk;${up}_GPU_OFFLOAD=nvidia" \
  "0000:00:02.0 0x030000 0x8086 1" "0000:02:00.0 0x030000 0x10de 0" "0000:02:00.1 0x040300 0x10de -"
check amd-apu-nvidia "$mesa_egl;$radeon_vk;${up}_GPU_OFFLOAD=nvidia" \
  "0000:06:00.0 0x030000 0x1002 1" "0000:01:00.0 0x030200 0x10de 0"
check intel-amd-dgpu "${up}_GPU_OFFLOAD=amd;${up}_GPU_OFFLOAD_DEVICE=pci-0000_03_00_0" \
  "0000:00:02.0 0x030000 0x8086 1" "0000:03:00.0 0x030000 0x1002 0"
check amd-apu-amd-dgpu "${up}_GPU_OFFLOAD=amd;${up}_GPU_OFFLOAD_DEVICE=pci-0000_03_00_0" \
  "0000:06:00.0 0x030000 0x1002 1" "0000:03:00.0 0x038000 0x1002 0"
check intel-nvidia-amd "$mesa_egl;$intel_vk;${up}_GPU_OFFLOAD=nvidia" \
  "0000:00:02.0 0x030000 0x8086 1" "0000:01:00.0 0x030000 0x10de 0" "0000:03:00.0 0x030000 0x1002 0"
check amd-desktop-only none "0000:03:00.0 0x030000 0x1002 1"
check intel-only none "0000:00:02.0 0x030000 0x8086 1"
check nvidia-drives-display none "0000:01:00.0 0x030000 0x10de 1" "0000:00:02.0 0x030000 0x8086 0"
check nvidia-audio-only none "0000:00:02.0 0x030000 0x8086 1" "0000:02:00.1 0x040300 0x10de -"

# The hardware package's GPU file (<ID>_GPU_FILE replaces /etc/<id>/gpu): used only when a GPU it
# names drives the display the firmware booted on (docs/7, choice 45). A used file either yields an
# AQ_DRM_DEVICES line or, when the named device does not exist on the machine running the test,
# a "not a device" note; a skipped file yields the "ignoring <file>" note and no line.
# check_file <name> <used|skipped> then the devices, as for check
check_file() {
  local name=$1 want=$2 tree="$work/file-$1"; shift 2
  mkdir -p "$tree/bus/pci/devices"
  while (($#)); do dev "$tree" $1; shift; done
  echo "/dev/dri/by-path/pci-0000:00:02.0-card" > "$tree/gpu"
  out=$(env -u __EGL_VENDOR_LIBRARY_FILENAMES -u AQ_DRM_DEVICES "${up}_GPU_SYSFS=$tree" "${up}_GPU_FILE=$tree/gpu" sh "$gen" 2>&1 | grep -v '_GPU_OFFLOAD\|__EGL\|VK_DRIVER')
  if grep -q "ignoring $tree/gpu" <<<"$out"; then got=skipped; else got=used; fi
  if [[ $got == skipped ]] && grep -q '^AQ_DRM_DEVICES=' <<<"$out"; then got="skipped but printed AQ_DRM_DEVICES"; fi
  if [[ $got == "$want" ]]; then echo "ok   gpu file, $name: $got"; else echo "FAIL gpu file, $name: got [$got], want [$want]: $out"; fail=1; fi
}
check_file hybrid-mode used "0000:00:02.0 0x030000 0x8086 1" "0000:02:00.0 0x030000 0x10de 0"
check_file mux-nvidia-intel-present skipped "0000:00:02.0 0x030000 0x8086 0" "0000:02:00.0 0x030000 0x10de 1"
check_file mux-nvidia-intel-gone skipped "0000:02:00.0 0x030000 0x10de 1"
exit $fail
