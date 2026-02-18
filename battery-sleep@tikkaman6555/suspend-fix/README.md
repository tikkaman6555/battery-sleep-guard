# suspend-fix/

This folder contains suspend/resume helper scripts (systemd system-sleep hooks) for machines that resume to a black screen.

## One-shot (recommended)

Default (install smart resume + force s2idle):

```bash
sudo ./apply.sh
```

Skip `s2idle` if you don't want it:

```bash
sudo ./apply.sh --no-s2idle
```

Skip smart-resume (only force `s2idle`):

```bash
sudo ./apply.sh --no-smart-resume --s2idle
```

## Manual steps (equivalent)

Install the resume fix hook (Cinnamon/Xorg + LightDM-friendly):

```bash
sudo ./install_smart_resume_hook.sh
```

If `deep` suspend is unreliable, force `s2idle` (optional):

```bash
sudo ./install_force_s2idle_hook.sh
```

## Logs

- Smart resume hook: `journalctl -b -t fix-smart-resume`
- Force s2idle hook: `journalctl -b -t hibear-force-s2idle`

## Collect debug info

```bash
./analyze_suspend.sh
```

## Notes

- If you see “double login”, it’s almost always because something restarts `display-manager` after resume.
  The `cleanup.sh` script disables/masks `resume-fix-display.service` if present.

- The `fix-smart-resume` hook now includes best-effort Wayland handling (GNOME/sway/hyprland). It attempts a session DBus "poke" and compositor-specific DPMS/refresh commands without restarting the display manager.

- Added a Cinnamon-specific screensaver "poke" (uses `cinnamon-screensaver-command --poke` if available) to improve resume reliability on Linux Mint / Cinnamon (X11).
