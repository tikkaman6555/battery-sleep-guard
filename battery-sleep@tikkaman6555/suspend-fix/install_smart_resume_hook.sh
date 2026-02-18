#!/bin/bash

# Installs a systemd system-sleep hook that fixes Intel/Cinnamon black screen on resume
# without restarting your display manager.
#
# Installs to: /usr/lib/systemd/system-sleep/fix-smart-resume (or /lib/...) depending on distro.
# Logs:
# - journalctl -b -t fix-smart-resume
# - /run/fix-smart-resume.log
# - /var/log/fix-smart-resume.log

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

SYSTEM_SLEEP_DIR="/lib/systemd/system-sleep"
if [ -d "/usr/lib/systemd/system-sleep" ]; then
  SYSTEM_SLEEP_DIR="/usr/lib/systemd/system-sleep"
fi

HOOK_PATH="$SYSTEM_SLEEP_DIR/fix-smart-resume"

echo "Installing smart resume hook to $HOOK_PATH..."

cat << 'EOF' > "$HOOK_PATH"
#!/bin/bash

# $1 = pre (suspend) or post (resume)
# $2 = suspend/hibernate/etc

VT_FILE="/run/fix-smart-resume.active_vt"
RUN_LOG_FILE="/run/fix-smart-resume.log"
PERSIST_LOG_FILE="/var/log/fix-smart-resume.log"

log() {
    local line
    line="$(date -Is 2>/dev/null || date) $*"
    printf '%s\n' "$line" >> "$RUN_LOG_FILE" 2>/dev/null || true
    printf '%s\n' "$line" >> "$PERSIST_LOG_FILE" 2>/dev/null || true
    if command -v systemd-cat >/dev/null 2>&1; then
        printf '%s\n' "$line" | systemd-cat -t fix-smart-resume || true
    fi
}

get_active_vt() {
    if [ -r /sys/class/tty/tty0/active ]; then
        local active
        active=$(cat /sys/class/tty/tty0/active 2>/dev/null || true)
        if echo "$active" | grep -Eq '^tty[0-9]+$'; then
            echo "${active#tty}"
            return 0
        fi
    fi

    if [ -x /usr/bin/fgconsole ]; then
        /usr/bin/fgconsole 2>/dev/null && return 0
    fi
    if [ -x /bin/fgconsole ]; then
        /bin/fgconsole 2>/dev/null && return 0
    fi

    return 1
}

run_chvt() {
    if [ -x /usr/bin/chvt ]; then
        /usr/bin/chvt "$@"
        return $?
    fi
    if [ -x /bin/chvt ]; then
        /bin/chvt "$@"
        return $?
    fi
    return 127
}

get_active_session_info() {
    # Echoes: "session_id user_name display type locked_hint"
    local sid
    sid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$4=="seat0" && $6=="active" {print $1; exit}')
    if [ -z "$sid" ]; then
        sid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '$6=="active" {print $1; exit}')
    fi
    [ -n "$sid" ] || return 1

    local name display type
    name=$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)
    display=$(loginctl show-session "$sid" -p Display --value 2>/dev/null || true)
    type=$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)

    local locked
    locked=$(loginctl show-session "$sid" -p LockedHint --value 2>/dev/null || true)
    [ -n "$locked" ] || locked="unknown"

    [ -n "$name" ] || return 1
    [ -n "$display" ] || display=":0"
    [ -n "$type" ] || type="unknown"

    echo "$sid $name $display $type $locked"
}

try_wake_x11() {
    local user="$1"
    local display="$2"
    local locked_hint="${3:-unknown}"

    local home_dir=""
    home_dir=$(getent passwd "$user" 2>/dev/null | cut -d: -f6)
    if [ -z "$home_dir" ]; then
        home_dir="/home/$user"
    fi

    local xauth_user="$home_dir/.Xauthority"
    if [ ! -r "$xauth_user" ]; then
        xauth_user=""
    fi

    local lightdm_xauth="/var/run/lightdm/root/$display"
    if [ ! -r "$lightdm_xauth" ]; then
        lightdm_xauth="/run/lightdm/root/$display"
    fi
    if [ ! -r "$lightdm_xauth" ]; then
        lightdm_xauth=""
    fi

    local xauth_root=""
    if [ -n "$lightdm_xauth" ]; then
        xauth_root="$lightdm_xauth"
    fi

    if command -v xset >/dev/null 2>&1; then
        if [ -n "$xauth_root" ]; then
            DISPLAY="$display" XAUTHORITY="$xauth_root" xset dpms force on >/dev/null 2>&1 || true
            DISPLAY="$display" XAUTHORITY="$xauth_root" xset s reset >/dev/null 2>&1 || true
            log "post: xset dpms on (root display=$display xauth=$xauth_root)"
        elif [ -n "$xauth_user" ]; then
            runuser -l "$user" -c "DISPLAY='$display' XAUTHORITY='$xauth_user' xset dpms force on; xset s reset" >/dev/null 2>&1 || true
            log "post: xset dpms on (user=$user display=$display xauth=$xauth_user)"
        else
            log "post: xset present but no readable XAUTHORITY; skipping"
        fi
    fi

    if [ "$locked_hint" = "yes" ]; then
        log "post: session locked (LockedHint=yes); skipping xrandr poke"
        return 0
    fi

    if command -v xrandr >/dev/null 2>&1; then
        if [ -n "$xauth_root" ]; then
            DISPLAY="$display" XAUTHORITY="$xauth_root" xrandr --auto >/dev/null 2>&1 || true
            log "post: xrandr --auto (root display=$display xauth=$xauth_root)"
        elif [ -n "$xauth_user" ]; then
            runuser -l "$user" -c "DISPLAY='$display' XAUTHORITY='$xauth_user' xrandr --auto" >/dev/null 2>&1 || true
            log "post: xrandr --auto (user=$user display=$display xauth=$xauth_user)"
        fi
    fi

    # Cinnamon-specific: try the cinnamon-screensaver CLI to nudge the screen/saver (no-op if not present)
    if command -v cinnamon-screensaver-command >/dev/null 2>&1; then
        if [ -n "$xauth_root" ]; then
            DISPLAY="$display" XAUTHORITY="$xauth_root" cinnamon-screensaver-command --poke >/dev/null 2>&1 || true
            log "post: cinnamon-screensaver-command --poke (root display=$display)"
        elif [ -n "$xauth_user" ]; then
            runuser -l "$user" -c "DISPLAY='$display' XAUTHORITY='$xauth_user' cinnamon-screensaver-command --poke" >/dev/null 2>&1 || true
            log "post: cinnamon-screensaver-command --poke (user=$user display=$display)"
        fi
    fi
}

try_wake_wayland() {
    # Best-effort Wayland handling: try DBus screen-saver activity and compositor helpers (GNOME, sway).
    local user="$1"
    local display="$2"
    local locked_hint="${3:-unknown}"

    if [ "$locked_hint" = "yes" ]; then
        log "post: wayland session locked (LockedHint=yes); skipping Wayland poke"
        return 0
    fi

    # Try to simulate user activity on the session DBus (GNOME/Mutter/others expose org.freedesktop.ScreenSaver)
    if command -v gdbus >/dev/null 2>&1; then
        runuser -l "$user" -c "gdbus call --session --dest org.freedesktop.ScreenSaver --object-path /org/freedesktop/ScreenSaver --method org.freedesktop.ScreenSaver.SimulateUserActivity" >/dev/null 2>&1 || true
        log "post: wayland gdbus SimulateUserActivity (user=$user)"
    fi

    # Compositor-specific: sway (wlroots) - request outputs / DPMS on
    if command -v swaymsg >/dev/null 2>&1; then
        runuser -l "$user" -c "swaymsg 'output * dpms on' >/dev/null 2>&1 || true" || true
        log "post: swaymsg dpms on (user=$user)"
    fi

    # Hyprland: try hyprctl dispatch dpms on (best-effort)
    if command -v hyprctl >/dev/null 2>&1; then
        runuser -l "$user" -c "hyprctl dispatch dpms on >/dev/null 2>&1 || true" || true
        log "post: hyprctl dpms on (user=$user)"
    fi

    # Fallback: try to ping the compositor (gnome-shell) via DBus Eval to force re-exec (very safe: do not restart)
    if command -v gdbus >/dev/null 2>&1; then
        # Try to call org.gnome.Shell.Eval to perform a no-op evaluate; ignore failures
        runuser -l "$user" -c "gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell --method org.gnome.Shell.Eval \"global.log('resume-poke')\"" >/dev/null 2>&1 || true
        log "post: wayland gnome-shell Eval poke (user=$user)"
    fi
}

case "${1:-}" in
    pre)
        log "pre: invoked (mode=$2)"
        vt=$(get_active_vt || true)
        if echo "$vt" | grep -Eq '^[0-9]+$'; then
            echo "$vt" > "$VT_FILE"
            log "pre: saved active VT=$vt"
        else
            echo "7" > "$VT_FILE"
            log "pre: failed to detect active VT; defaulting to 7"
        fi
        ;;

    post)
        log "post: starting resume actions (mode=$2)"

        session_info=$(get_active_session_info 2>/dev/null || true)
        if [ -n "$session_info" ]; then
            log "post: active session: $session_info"
        else
            log "post: could not determine active session via loginctl"
        fi

        if [ -f "$VT_FILE" ]; then
            SAVED_VT=$(cat "$VT_FILE")
        else
            SAVED_VT=7
        fi

        if ! echo "$SAVED_VT" | grep -Eq '^[0-9]+$'; then
            log "post: VT file contained non-numeric '$SAVED_VT'; defaulting to 7"
            SAVED_VT=7
        fi

        if [ ! -e "/dev/tty${SAVED_VT}" ]; then
            current_vt=$(get_active_vt || true)
            if echo "$current_vt" | grep -Eq '^[0-9]+$'; then
                log "post: /dev/tty${SAVED_VT} missing; using current active VT=$current_vt"
                SAVED_VT="$current_vt"
            fi
        fi

        sess_locked="unknown"
        if [ -n "$session_info" ]; then
            sess_locked=$(echo "$session_info" | awk '{print $5}')
        fi

        if [ "$sess_locked" = "yes" ]; then
            log "post: session locked (LockedHint=yes); skipping VT switch"
        else
            for attempt in 1 2 3 4 5; do
                run_chvt 1
                rc1=$?
                sleep 0.6
                run_chvt "$SAVED_VT"
                rc2=$?
                log "post: chvt attempt=$attempt rc1=$rc1 rc2=$rc2 saved_vt=$SAVED_VT"
                if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
                    break
                fi
                sleep 0.6
            done
        fi

        if [ -n "$session_info" ]; then
            sess_user=$(echo "$session_info" | awk '{print $2}')
            sess_display=$(echo "$session_info" | awk '{print $3}')
            sess_type=$(echo "$session_info" | awk '{print $4}')
            sess_locked=$(echo "$session_info" | awk '{print $5}')

            if [ "$sess_type" = "x11" ] && echo "$sess_display" | grep -Eq '^:'; then
                sleep 0.5
                try_wake_x11 "$sess_user" "$sess_display" "$sess_locked"
            elif [ "$sess_type" = "wayland" ]; then
                sleep 0.5
                try_wake_wayland "$sess_user" "$sess_display" "$sess_locked"
            fi
        fi

        backlight_paths=()
        if [ -d /sys/class/backlight/intel_backlight ]; then
            backlight_paths+=(/sys/class/backlight/intel_backlight)
        else
            for bl in /sys/class/backlight/*; do
                [ -d "$bl" ] && backlight_paths+=("$bl")
            done
        fi

        for bl in "${backlight_paths[@]}"; do
            [ -r "$bl/brightness" ] || continue
            [ -r "$bl/max_brightness" ] || continue

            current=$(cat "$bl/brightness" 2>/dev/null || echo "")
            max=$(cat "$bl/max_brightness" 2>/dev/null || echo "")
            echo "$current" | grep -Eq '^[0-9]+$' || continue
            echo "$max" | grep -Eq '^[0-9]+$' || continue

            low_threshold=$((max / 20))
            [ "$low_threshold" -lt 1 ] && low_threshold=1
            if [ "$current" -lt "$low_threshold" ]; then
                target=$((max / 2))
                echo "$target" > "$bl/brightness" 2>/dev/null || true
                log "post: backlight bumped on $(basename "$bl") current=$current max=$max target=$target"
            fi
        done

        rm -f "$VT_FILE"
        log "post: finished"
        ;;

    *)
        ;;
esac
EOF

chmod +x "$HOOK_PATH"

echo "Installed. Test suspend/resume."