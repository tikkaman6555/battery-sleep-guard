#!/usr/bin/env bash

# One-shot entrypoint for the "final" bundle.
# Default: install smart resume hook.
# Optional: add --s2idle.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo ./final/apply.sh [options]

Options:
  --s2idle          Also install the force-s2idle hook
  --no-smart-resume  Skip installing the smart resume hook
  -h, --help         Show this help

Examples:
  sudo ./final/apply.sh
  sudo ./final/apply.sh --s2idle
EOF
}

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DO_SMART_RESUME=1
DO_S2IDLE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --s2idle)
      DO_S2IDLE=1
      ;;
    --no-smart-resume)
      DO_SMART_RESUME=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [ "$DO_SMART_RESUME" -eq 1 ]; then
  "$SCRIPT_DIR/install_smart_resume_hook.sh"
fi

if [ "$DO_S2IDLE" -eq 1 ]; then
  "$SCRIPT_DIR/install_force_s2idle_hook.sh"
fi

echo
printf 'Done. Active hooks (system-sleep):\n'
ls -la /usr/lib/systemd/system-sleep /lib/systemd/system-sleep 2>/dev/null | sed -n '1,120p' || true

echo
printf 'Logs:\n'
printf '  smart resume: journalctl -b -t fix-smart-resume\n'
printf '  force s2idle : journalctl -b -t hibear-force-s2idle\n'
