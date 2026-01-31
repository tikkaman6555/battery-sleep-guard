#!/usr/bin/env bash
set -euo pipefail

APPLET_DIR_NAME="battery-sleep@tikkaman6555"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="$HOME/.local/share/cinnamon/applets"
DEST_DIR="$DEST_ROOT/$APPLET_DIR_NAME"

usage() {
  cat <<EOF
Usage: $0 [-u]

Options:
  -u    Uninstall the applet from $DEST_DIR
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "-u" ]]; then
  if [[ -d "$DEST_DIR" ]]; then
    rm -rf "$DEST_DIR"
    echo "Uninstalled from: $DEST_DIR"
  else
    echo "Not installed: $DEST_DIR"
  fi
  exit 0
fi

mkdir -p "$DEST_ROOT"

if [[ -d "$DEST_DIR" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="$DEST_DIR.bak.$ts"
  mv "$DEST_DIR" "$backup"
  echo "Existing applet moved to: $backup"
fi

cp -a "$SRC_DIR" "$DEST_DIR"

# Avoid nesting the installer itself inside a copy of the applet folder
if [[ -d "$DEST_DIR/$APPLET_DIR_NAME" ]]; then
  rm -rf "$DEST_DIR/$APPLET_DIR_NAME"
fi

chmod +x "$DEST_DIR/install.sh" || true
chmod +x "$DEST_DIR/suspend-fix/apply.sh" || true
chmod +x "$DEST_DIR/suspend-fix/analyze_suspend.sh" || true
chmod +x "$DEST_DIR/suspend-fix/install_smart_resume_hook.sh" || true
chmod +x "$DEST_DIR/suspend-fix/install_force_s2idle_hook.sh" || true

# Clear Cinnamon applet cache to ensure changes are picked up,
# but preserve existing settings across Cinnamon restarts.
SETTINGS_DIR="$HOME/.config/cinnamon/spices/$APPLET_DIR_NAME"
SETTINGS_FILE="$SETTINGS_DIR/$APPLET_DIR_NAME.json"
TMP_SETTINGS=""
if [[ -f "$SETTINGS_FILE" ]]; then
  TMP_SETTINGS="$(mktemp)"
  cp -a "$SETTINGS_FILE" "$TMP_SETTINGS"
fi

rm -rf "$SETTINGS_DIR" 2>/dev/null || true

if [[ -n "$TMP_SETTINGS" && -f "$TMP_SETTINGS" ]]; then
  mkdir -p "$SETTINGS_DIR"
  cp -a "$TMP_SETTINGS" "$SETTINGS_FILE"
  rm -f "$TMP_SETTINGS"
fi

cat <<EOF
Installed to: $DEST_DIR
Next:
- Open Cinnamon Settings → Applets → Add "Battery Sleep Guard" to panel.
- Configure threshold/action/interval in the applet settings.
-----
Reload Cinnamon (Alt+F2, then r).
Clear the applet cache: remove ~/.config/cinnamon/spices/battery-sleep@tikkaman6555, then reinstall.

EOF
