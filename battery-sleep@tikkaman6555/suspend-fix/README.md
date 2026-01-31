# suspend-fix/

This folder contains suspend/resume helper scripts (systemd system-sleep hooks) for machines that resume to a black screen.

## One-shot (recommended)

Default (install smart resume):

```bash
sudo ./apply.sh
```

Include `s2idle` forcing (optional):

```bash
sudo ./apply.sh --s2idle
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
