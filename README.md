# hibrear

A small Linux Mint / Cinnamon helper repo.

This repo contains:

- Cinnamon applet: `battery-sleep@tikkaman6555/` (Battery Sleep Guard)
- Suspend/resume fix scripts: `battery-sleep@tikkaman6555/suspend-fix/`

## Battery Sleep Guard (Cinnamon applet)

The applet monitors your battery percentage and can:
- Suspend
- Hibernate
- Alert only (optional popup/notification)

### Install

```bash
cd battery-sleep@tikkaman6555
./install.sh
```

Then:
- Cinnamon Settings → Applets → add **Battery Sleep Guard** to the panel.

Uninstall:

```bash
cd battery-sleep@tikkaman6555
./install.sh -u
```

### Panel UI (clicks + menu)

#### Click behavior

- Left click: toggle the applet menu
- Double left click: open the applet settings
- Middle click: toggle the applet menu
- Right click: refresh menu labels then toggle the menu

#### Applet label format

The label is:

`<percent>%<status> <mode>`

Where:
- `<status>` is `↓` (Discharging), `↑` (Charging), `✓` (Full)
- `<mode>` is `S` (Suspend), `H` (Hibernate), or `A` (Alert)
- If popup alerts are enabled for Suspend/Hibernate, the mode shows `+P` (example: `S+P`)

#### Menu controls

- **Threshold slider**: quick-set the threshold (1–50%). Changing the threshold resets the cooldown and suppresses one check cycle to avoid an immediate trigger from the edit itself.
- **Action**: quick-set Suspend / Hibernate / Alert only.
- **Status**: shows current percent + UPower status string.
- **Cooldown**: shows how long until the applet can trigger again.

### Settings UI (all controls)

Open: Cinnamon Settings → Applets → Battery Sleep Guard.

- **Threshold percentage**: battery % at or below which the action triggers.
- **Action when threshold reached**:
	- Suspend: runs `systemctl suspend`
	- Hibernate: runs `systemctl hibernate`
	- Alert only: never suspends/hibernates; can show a popup alert (see below)
- **Check interval (seconds)**: how often the applet polls `/sys/class/power_supply/BAT*/`.
- **Cooldown after action (minutes)**: minimum time between triggers.
- **Show notification before action**: shows a Cinnamon notification right before suspend/hibernate.
- **Show popup alert before action**:
	- If enabled (and action is Suspend/Hibernate), shows a blocking countdown dialog with Cancel / “Suspend now” (or “Hibernate now”).
	- If action is Alert only, the popup shows a countdown and a Dismiss button.
- **Popup countdown seconds**: length of the popup countdown.
- **Only act while discharging**: when enabled, the threshold is ignored unless the status is exactly `Discharging`.
- **Force sleep/hibernate at critical threshold when action is Alert only**: safety net; if Action is Alert only, the applet can still suspend/hibernate at the critical threshold.
- **Critical threshold percentage**: battery % at or below which the critical action triggers (only used when Action is Alert only).
- **Critical action**: Suspend or Hibernate for the critical threshold (only used when Action is Alert only).
- **Install suspend/resume fix** (button): prompts for admin privileges and runs `battery-sleep@tikkaman6555/suspend-fix/apply.sh`.

## Suspend/resume fix scripts

Path: `battery-sleep@tikkaman6555/suspend-fix/`

These scripts install systemd **system-sleep** hooks to improve resume reliability on some systems (e.g. black screen after resume).

### Recommended (one-shot)

From inside `battery-sleep@tikkaman6555/suspend-fix/`:

```bash
sudo ./apply.sh
```

Optional: also force `s2idle`:

```bash
sudo ./apply.sh --s2idle
```

### What gets installed

The scripts install systemd **system-sleep** hooks under one of:
- `/usr/lib/systemd/system-sleep/`
- `/lib/systemd/system-sleep/`

(Exact location depends on the distro; the scripts choose the appropriate one.)

### Logs

- Smart resume: `journalctl -b -t fix-smart-resume`
- Force s2idle: `journalctl -b -t hibear-force-s2idle`

### Rollback

List installed hooks:

```bash
ls -la /usr/lib/systemd/system-sleep /lib/systemd/system-sleep 2>/dev/null
```

Then remove the hook files you installed (the scripts print their target path). If you want a safety check before deleting anything, re-run the installers to see the destination path, then `sudo rm -f <that-path>`.

## Security note

The applet runs the fix via `pkexec` (admin prompt). Only use this repo from a trusted checkout and review scripts before running them as root.
