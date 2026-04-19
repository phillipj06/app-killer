#!/bin/bash
# audit.sh — Summarize app kills from the log
# Usage: ./audit.sh [today|week|all]  (default: today)

KILL_LOG="/var/log/app-killer.log"

if [[ ! -f "$KILL_LOG" ]]; then
    echo "No log file found at $KILL_LOG"
    exit 1
fi

PERIOD="${1:-today}"

case "$PERIOD" in
    today)
        DATE_FILTER=$(date '+%Y-%m-%d')
        LABEL="Today ($DATE_FILTER)"
        ;;
    week)
        DATE_FILTER=$(date -v-7d '+%Y-%m-%d')
        LABEL="Last 7 days (since $DATE_FILTER)"
        ;;
    all)
        DATE_FILTER=""
        LABEL="All time"
        ;;
    *)
        DATE_FILTER="$PERIOD"
        LABEL="Date: $PERIOD"
        ;;
esac

if [[ -n "$DATE_FILTER" ]]; then
    DATA=$(awk -v d="$DATE_FILTER" '$1 >= d' "$KILL_LOG")
else
    DATA=$(cat "$KILL_LOG")
fi

TOTAL=$(echo "$DATA" | grep -c "KILLED" 2>/dev/null || echo 0)

echo "=== App Kill Audit: $LABEL ==="
echo "Total kills: $TOTAL"
echo ""

echo "--- Kills by app ---"
echo "$DATA" | awk '{print $4}' | sort | uniq -c | sort -rn
echo ""

echo "--- Kills by 15-min window ---"
echo "$DATA" | awk '{
    split($2, t, ":")
    h = t[1]
    m = int(t[2] / 15) * 15
    printf "%s %s:%02d %s\n", $1, h, m, $4
}' | sort | uniq -c | sort -k2,3 -k1rn | \
    awk '{printf "%4d  %s %s  %s\n", $1, $2, $3, $4}'
