#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Fix Linux Mint suspend/wake hang by forcing "deep" (S3) sleep instead of s2idle.

What it does (safe + reversible):
- Creates a timestamped backup of /etc/default/grub
- Adds mem_sleep_default=deep to GRUB_CMDLINE_LINUX_DEFAULT (if missing)
- Adds a systemd sleep drop-in: /etc/systemd/sleep.conf.d/99-force-deep.conf
- Runs update-grub and systemctl daemon-reload

Run:
  sudo bash fix-mint-sleep-wake-deep.sh

After running, reboot and test suspend/resume.

Rollback:
- Restore the backup it prints (copy it back to /etc/default/grub, then run update-grub)
- Remove /etc/systemd/sleep.conf.d/99-force-deep.conf
USAGE
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage
  exit 0
fi

if [[ "$(id -u)" != "0" ]]; then
  echo "ERROR: Please run as root (use: sudo bash $0)" >&2
  exit 1
fi

if [[ ! -r /sys/power/mem_sleep ]]; then
  echo "ERROR: /sys/power/mem_sleep not readable; cannot determine supported sleep modes." >&2
  exit 1
fi

mem_sleep_contents="$(cat /sys/power/mem_sleep)"
if ! grep -q "\bdeep\b" <<<"$mem_sleep_contents"; then
  echo "ERROR: This system does not advertise 'deep' sleep mode. Current: $mem_sleep_contents" >&2
  echo "Nothing changed." >&2
  exit 1
fi

echo "Detected supported sleep modes: $mem_sleep_contents"

# 1) systemd drop-in to prefer deep
mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/99-force-deep.conf <<'CONF'
[Sleep]
SuspendState=mem
SuspendMode=deep
CONF

echo "Wrote /etc/systemd/sleep.conf.d/99-force-deep.conf"

# 2) Add kernel parameter via GRUB
if [[ ! -f /etc/default/grub ]]; then
  echo "ERROR: /etc/default/grub not found." >&2
  echo "Nothing changed." >&2
  exit 1
fi

ts="$(date +%Y%m%d-%H%M%S)"
backup="/etc/default/grub.bak.$ts"
cp -a /etc/default/grub "$backup"
echo "Backed up /etc/default/grub -> $backup"

# Edit GRUB_CMDLINE_LINUX_DEFAULT in a minimal, idempotent way.
# - If the variable exists: append mem_sleep_default=deep if missing.
# - If it does not exist: create it.
python3 - <<'PY'
import re
from pathlib import Path

grub_path = Path('/etc/default/grub')
text = grub_path.read_text(encoding='utf-8', errors='replace').splitlines(True)

param = 'mem_sleep_default=deep'
key = 'GRUB_CMDLINE_LINUX_DEFAULT'

out = []
changed = False
found = False

for line in text:
    m = re.match(r'^(\s*' + re.escape(key) + r')=(.*)$', line)
    if not m:
        out.append(line)
        continue

    found = True
    prefix, rhs = m.group(1), m.group(2).rstrip('\n')

    # Keep comments on same line? GRUB typically doesn't, but preserve trailing whitespace.
    # Expect a quoted string; if not, do best-effort.
    qm = re.match(r'^(".*")\s*$', rhs)
    if qm:
        value_quoted = qm.group(1)
        value = value_quoted[1:-1]
        parts = value.split()
        if param not in parts:
            parts.append(param)
            changed = True
        new_value = '"' + ' '.join(parts) + '"'
        out.append(f"{prefix}={new_value}\n")
    else:
        # Unquoted: append if missing
        if param not in rhs.split():
            rhs = (rhs + ' ' + param).strip()
            changed = True
        out.append(f"{prefix}={rhs}\n")

if not found:
    out.append(f"{key}=\"quiet splash {param}\"\n")
    changed = True

grub_path.write_text(''.join(out), encoding='utf-8')
print('UPDATED' if changed else 'NO_CHANGE')
PY

echo "Updated /etc/default/grub (mem_sleep_default=deep)"

if command -v update-grub >/dev/null 2>&1; then
  update-grub
else
  echo "ERROR: update-grub not found. On some systems use: grub-mkconfig -o /boot/grub/grub.cfg" >&2
  echo "I did not generate a new GRUB config." >&2
  exit 1
fi

systemctl daemon-reload

echo
echo "Done. Next steps:"
echo "1) Reboot." 
echo "2) After reboot, verify default is deep: cat /sys/power/mem_sleep (should show: s2idle [deep])"
echo "3) Test suspend: systemctl suspend"
echo
echo "If something goes wrong, rollback:" 
echo "- cp -a $backup /etc/default/grub && update-grub"
echo "- rm -f /etc/systemd/sleep.conf.d/99-force-deep.conf && systemctl daemon-reload"
