#!/bin/bash
# web-logger.sh — Log ALL DNS queries when bad_user is at the console
# Runs as root, kid can't access or modify /var/log/
# Filtering happens in the audit script, not here — never miss a query

BAD_USER="__TARGET_USER__"
WEB_LOG="/var/log/web-blocker.log"
MAX_LOG_SIZE=$((100 * 1024 * 1024))  # 100MB

# Rotate log if over max size
if [[ -f "$WEB_LOG" ]]; then
    LOG_SIZE=$(stat -f%z "$WEB_LOG" 2>/dev/null || echo 0)
    if [[ "$LOG_SIZE" -gt "$MAX_LOG_SIZE" ]]; then
        mv "$WEB_LOG.2" "$WEB_LOG.3" 2>/dev/null
        mv "$WEB_LOG.1" "$WEB_LOG.2" 2>/dev/null
        mv "$WEB_LOG" "$WEB_LOG.1"
    fi
fi

# Log every DNS query when bad_user is at console
tcpdump -i any -n -l 'udp port 53' 2>/dev/null | \
    grep --line-buffered -oE 'A\? [^ ]+' | \
    sed -u 's/^A? //; s/\.$//' | \
    awk -v logfile="$WEB_LOG" -v baduser="$BAD_USER" '
/\.local$/ || /\.arpa$/ || /^_/ { next }
{
    # Check console user every 30 seconds
    now = systime()
    if (now - last_check > 30) {
        cmd = "/usr/bin/stat -f %Su /dev/console"
        cmd | getline console_user
        close(cmd)
        last_check = now
    }
    if (console_user != baduser) next

    ts = strftime("%Y-%m-%d %H:%M:%S")
    print ts " " $0 >> logfile
    fflush(logfile)
}'
