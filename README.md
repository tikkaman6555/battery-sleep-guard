# Battery Sleep Guard (Cinnamon Applet)

Monitors battery level and triggers suspend/hibernate/alert at a configured threshold.

## Features
- Threshold-based action (Suspend / Hibernate / Alert only)
- Optional popup alert with countdown
- Cooldown to avoid repeated triggers
- Right-click menu with quick controls and cooldown indicator
- Built-in “Fix deep sleep” button in applet settings

## Install
From the applet folder:
- `./install.sh`

If changes don’t appear:
- Reload Cinnamon (Alt+F2 → r)
- The installer also clears the applet cache while preserving settings

## Uninstall
- `./install.sh -u`

## Configuration
Open Cinnamon Settings → Applets → Battery Sleep Guard.

### Options (all settings)
- **Threshold percentage**: Battery % at or below which the action triggers.
- **Action when threshold reached**: Suspend / Hibernate / Alert only.
- **Check interval (seconds)**: How often to poll battery state.
- **Cooldown after action (minutes)**: Minimum time before another trigger after one fires.
- **Show notification before action**: Passive toast right before action.
- **Show popup alert before action**: Blocking dialog with countdown and buttons.
- **Popup countdown seconds**: Length of the popup countdown.
- **Only act while discharging**: Ignore threshold while charging/full.
- **Fix deep sleep** (button): Applies the deep sleep fix via admin prompt; reboot required.

### Notification vs Popup Alert
- **Notification**: passive toast before action
- **Popup alert**: blocking dialog with countdown and buttons to cancel or trigger immediately

### Alert-only mode
If Action is **Alert only**, the popup is informational and no suspend/hibernate occurs.

## Troubleshooting
If the applet doesn’t show:
- Ensure it’s enabled in Cinnamon Settings → Applets
- Check `.xsession-errors` for applet errors

## Deep sleep fix
Use the **Fix deep sleep** button in the applet settings (requires admin password). Reboot afterward.
