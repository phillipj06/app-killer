#!/bin/bash
# emergency-access.sh — Temporarily disable all blocking for 15 minutes
# Double-click from Desktop. Requires admin password.
# Logs ALL browsing activity during the window.

DURATION=900  # 15 minutes in seconds
WEB_LOG="/var/log/web-blocker.log"
EMERGENCY_LOG="/var/log/emergency-access.log"
STATE_FILE="/tmp/web-blocker-state"

# Must run as root
if [[ $EUID -ne 0 ]]; then
    osascript -e 'do shell script "/usr/local/bin/emergency-access.sh" with administrator privileges'
    exit 0
fi

# Log who triggered it and when
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)
echo "$(date '+%Y-%m-%d %H:%M:%S') EMERGENCY ACCESS GRANTED for $CONSOLE_USER (${DURATION}s)" >> "$EMERGENCY_LOG"

# Show notification
osascript -e "display notification \"All sites unlocked for 15 minutes. Everything is being logged.\" with title \"Emergency Access\"" 2>/dev/null

# Disable web blocker
sed -i '' '/SPG-WEB-BLOCKER-START/,/SPG-WEB-BLOCKER-END/d' /etc/pf.conf 2>/dev/null
sed -i '' '/SPG-WEB-BLOCKER-START/,/SPG-WEB-BLOCKER-END/d' /etc/hosts 2>/dev/null
pfctl -f /etc/pf.conf 2>/dev/null
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

# Prevent web-blocker.sh from re-enabling during the window
echo "emergency" > "$STATE_FILE"

# Start detailed DNS logging for the emergency window
DETAIL_LOG="/var/log/emergency-dns-$(date '+%Y%m%d-%H%M%S').log"
tcpdump -i any -n -l 'udp port 53' 2>/dev/null | \
    grep --line-buffered -oE 'A\? [^ ]+' | \
    sed -u 's/^A? //; s/\.$//' | \
    awk -v logfile="$DETAIL_LOG" '
/\.local$/ || /\.arpa$/ || /^_/ { next }
{
    ts = strftime("%Y-%m-%d %H:%M:%S")
    print ts " " $0 >> logfile
    fflush(logfile)
}' &
TCPDUMP_PID=$!

# Countdown
sleep "$DURATION"

# Kill the logger
kill "$TCPDUMP_PID" 2>/dev/null
wait "$TCPDUMP_PID" 2>/dev/null

# Log end
echo "$(date '+%Y-%m-%d %H:%M:%S') EMERGENCY ACCESS EXPIRED for $CONSOLE_USER" >> "$EMERGENCY_LOG"
SITES_VISITED=$(wc -l < "$DETAIL_LOG" 2>/dev/null | tr -d ' ')
echo "$(date '+%Y-%m-%d %H:%M:%S') $SITES_VISITED DNS queries logged to $DETAIL_LOG" >> "$EMERGENCY_LOG"

# Re-enable blocking by clearing state (next web-blocker.sh cycle picks it up)
rm -f "$STATE_FILE"

# Force immediate re-block
/usr/local/bin/web-blocker.sh "$(grep -A1 'ProgramArguments' /Library/LaunchDaemons/local.web-blocker.plist | tail -1 | sed 's/.*<string>//;s/<.*//')" 2>/dev/null

osascript -e "display notification \"Emergency access expired. Blocking restored.\" with title \"Emergency Access\"" 2>/dev/null
