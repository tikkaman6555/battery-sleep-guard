#!/bin/bash

# Force s2idle for upcoming suspend cycles.
# Installs a systemd system-sleep hook that writes "s2idle" into /sys/power/mem_sleep right before suspend.
#
# Logs:
# - journalctl -b -t hibear-force-s2idle

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

SYSTEM_SLEEP_DIR="/lib/systemd/system-sleep"
if [ -d "/usr/lib/systemd/system-sleep" ]; then
  SYSTEM_SLEEP_DIR="/usr/lib/systemd/system-sleep"
fi

HOOK_PATH="$SYSTEM_SLEEP_DIR/98-hibear-force-s2idle"

echo "Installing force-s2idle hook to $HOOK_PATH..."

cat << 'EOF' > "$HOOK_PATH"
#!/usr/bin/env bash
set -euo pipefail

TAG="hibear-force-s2idle"

log() {
  if command -v systemd-cat >/dev/null 2>&1; then
    echo "$*" | systemd-cat -t "$TAG"
  else
    echo "$TAG: $*" >&2
  fi
}

case "${1:-}" in
  pre)
    if [[ -w /sys/power/mem_sleep ]]; then
      before="$(cat /sys/power/mem_sleep 2>/dev/null || true)"
      if grep -qw s2idle <<<"$before"; then
        echo s2idle > /sys/power/mem_sleep || true
        after="$(cat /sys/power/mem_sleep 2>/dev/null || true)"
        log "set mem_sleep: '$before' -> '$after'"
      else
        log "s2idle not advertised in /sys/power/mem_sleep: '$before' (no change)"
      fi
    else
      log "/sys/power/mem_sleep not writable (no change)"
    fi
    ;;
  *)
    ;;
esac

exit 0
EOF

chmod +x "$HOOK_PATH"

echo "Installed. Next suspend will prefer s2idle (if supported)."