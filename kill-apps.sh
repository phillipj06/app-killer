#!/bin/bash
# kill-apps.sh — If the target user is at the console, kill their unauthorized apps

BAD_USER="${1:?Usage: kill-apps.sh <target_username>}"
APP_LIST="/tmp/apps.txt"
KILL_LOG="/var/log/app-killer.log"
MAX_LOG_SIZE=$((100 * 1024 * 1024))  # 100MB

# Who currently owns the GUI console?
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)

# Only act if the bad user is at the console
[[ "$CONSOLE_USER" != "$BAD_USER" ]] && exit 0

[[ -f "$APP_LIST" ]] || /usr/local/bin/refresh-apps.sh

CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null) || exit 0

# Get list of actually running processes for this user (one pgrep call instead of hundreds)
RUNNING=$(pgrep -U "$CONSOLE_UID" -l 2>/dev/null | awk '{print $2}')
[[ -z "$RUNNING" ]] && exit 0

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
KILLED=""

while IFS= read -r app; do
    [[ -z "$app" || "$app" == "Finder" || "$app" == "Safari" || "$app" == "Preview" || "$app" == "System Settings" || "$app" == "Mail" ]] && continue
    # Only pkill if the app is actually running
    if echo "$RUNNING" | grep -qxF "$app"; then
        pkill -x -U "$CONSOLE_UID" "$app" 2>/dev/null
        KILLED="$KILLED$TIMESTAMP KILLED $app\n"
    fi
done < "$APP_LIST"

# Batch write log entries
if [[ -n "$KILLED" ]]; then
    # Rotate log if needed
    if [[ -f "$KILL_LOG" ]]; then
        LOG_SIZE=$(stat -f%z "$KILL_LOG" 2>/dev/null || echo 0)
        if [[ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]]; then
            mv "$KILL_LOG.2" "$KILL_LOG.3" 2>/dev/null
            mv "$KILL_LOG.1" "$KILL_LOG.2" 2>/dev/null
            mv "$KILL_LOG" "$KILL_LOG.1"
        fi
    fi
    printf "$KILLED" >> "$KILL_LOG"
fi
