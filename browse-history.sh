#!/bin/bash
# browse-history.sh — Dump Safari browsing history for a user
# Usage: sudo ./browse-history.sh [username] [today|week|all]

TARGET_USER="${1:?Usage: sudo ./browse-history.sh <username>}"
PERIOD="${2:-today}"
DB="/Users/$TARGET_USER/Library/Safari/History.db"

if [[ ! -f "$DB" ]]; then
    echo "No Safari history found for $TARGET_USER"
    exit 1
fi

case "$PERIOD" in
    today)
        # Safari stores time as seconds since 2001-01-01
        SINCE=$(python3 -c "import datetime; print((datetime.datetime.now().replace(hour=0,minute=0,second=0) - datetime.datetime(2001,1,1)).total_seconds())" 2>/dev/null)
        if [[ -z "$SINCE" ]]; then
            SINCE=$(date -j -f "%Y-%m-%d" "$(date +%Y-%m-%d)" "+%s")
            SINCE=$((SINCE - 978307200))
        fi
        LABEL="Today"
        ;;
    week)
        SINCE=$(python3 -c "import datetime; print((datetime.datetime.now() - datetime.timedelta(days=7) - datetime.datetime(2001,1,1)).total_seconds())" 2>/dev/null)
        if [[ -z "$SINCE" ]]; then
            SINCE=$(date -v-7d "+%s")
            SINCE=$((SINCE - 978307200))
        fi
        LABEL="Last 7 days"
        ;;
    all)
        SINCE=0
        LABEL="All time"
        ;;
esac

echo "=== Safari History: $TARGET_USER — $LABEL ==="
echo ""

# Copy DB to tmp to avoid locking issues
cp "$DB" /tmp/history_copy.db 2>/dev/null

echo "--- Pages visited (most recent first) ---"
sqlite3 /tmp/history_copy.db "
SELECT
    datetime(v.visit_time + 978307200, 'unixepoch', 'localtime') as visited,
    i.url
FROM history_visits v
JOIN history_items i ON v.history_item = i.id
WHERE v.visit_time > $SINCE
ORDER BY v.visit_time DESC;
" 2>/dev/null

echo ""
echo "--- Top sites by visit count ---"
sqlite3 /tmp/history_copy.db "
SELECT
    COUNT(*) as visits,
    REPLACE(REPLACE(SUBSTR(i.url, INSTR(i.url, '://') + 3), 'www.', ''), SUBSTR(REPLACE(SUBSTR(i.url, INSTR(i.url, '://') + 3), 'www.', ''), INSTR(REPLACE(SUBSTR(i.url, INSTR(i.url, '://') + 3), 'www.', ''), '/')), '') as domain
FROM history_visits v
JOIN history_items i ON v.history_item = i.id
WHERE v.visit_time > $SINCE
GROUP BY domain
ORDER BY visits DESC
LIMIT 30;
" 2>/dev/null

rm -f /tmp/history_copy.db
