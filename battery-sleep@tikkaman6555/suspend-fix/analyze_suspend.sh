#!/bin/bash

set -euo pipefail

echo "Analyzing suspend/resume issues..."

echo "--- GPU Information ---"
(lspci | grep -i vga) || true
(lsmod | grep -E "nvidia|nouveau|amdgpu|i915") || true

echo -e "\n--- Kernel Command Line ---"
cat /proc/cmdline

echo -e "\n--- Suspend/Resume Logs (last 50 lines related to suspend) ---"
if command -v journalctl &> /dev/null; then
  journalctl -b | grep -iE "suspend|resume|acpi|sleep" | tail -n 50 || true
else
  grep -iE "suspend|resume|acpi|sleep" /var/log/syslog | tail -n 50 || true
fi

echo -e "\n--- Previous Boot Suspend/Resume + i915/DRM (useful if you had to hard reboot) ---"
if command -v journalctl &> /dev/null; then
  journalctl -b -1 --no-pager 2>/dev/null \
    | grep -iE "suspending system|systemd-sleep|systemd-(suspend|hibernate)|PM: suspend|PM: resume|i915|drm|gpu hang" \
    | tail -n 120 || true
fi

echo -e "\n--- /sys/power/mem_sleep ---"
cat /sys/power/mem_sleep

echo -e "\n--- Installed systemd system-sleep hooks ---"
ls -la /usr/lib/systemd/system-sleep /lib/systemd/system-sleep 2>/dev/null | sed -n '1,200p'

echo -e "\n--- Hook logs (current boot, if present) ---"
if command -v journalctl &> /dev/null; then
  journalctl -b --no-pager -t hibear-force-s2idle 2>/dev/null | tail -n 80 || true
  journalctl -b --no-pager -t fix-smart-resume 2>/dev/null | tail -n 200 || true
fi

echo -e "\nAnalysis complete. Please share the output."