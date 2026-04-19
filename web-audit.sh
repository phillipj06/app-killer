#!/bin/bash
# web-audit.sh — Tamper-proof browsing history audit
# Usage: ./web-audit.sh [today|week|all]  (default: today)

WEB_LOG="/var/log/web-blocker.log"

if [[ ! -f "$WEB_LOG" ]]; then
    echo "No log file found at $WEB_LOG"
    exit 1
fi

PERIOD="${1:-today}"
RAW="${2:-}"

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
        LABEL="Since $PERIOD"
        ;;
esac

if [[ -n "$DATE_FILTER" ]]; then
    DATA=$(awk -v d="$DATE_FILTER" '$1 >= d' "$WEB_LOG")
else
    DATA=$(cat "$WEB_LOG")
fi

TOTAL=$(echo "$DATA" | wc -l | tr -d ' ')

NOISE='(gstatic\.com|googleapis\.com|googleusercontent\.com|cloudfront\.net|akamaiedge\.net|cloudflare\.net|edgekey\.net|akadns\.net|apple\.com|icloud\.com|aaplimg\.com|apple-dns\.net|fastly\.net|imgix\.net|doubleclick\.net|google-analytics\.com|googletagmanager\.com|cloudflareinsights\.com|amazonaws\.com|awsglobalaccelerator\.com|googlehosted\.com|BLOCKED|l\.google\.com|withgoogle\.com|insops\.net|bugsnag\.com|pendo\.io)'

echo "=== Browsing Audit: $LABEL ==="
echo "Total DNS queries: $TOTAL"
echo ""

# Extract base domains, filter infra noise
SITES=$(echo "$DATA" | awk '{print $NF}' | \
    sed 's/^www\.//; s/^m\.//' | \
    awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}' | \
    grep -vE "^$NOISE$")

echo "--- Top 30 sites visited ---"
echo "$SITES" | sort | uniq -c | sort -rn | head -30
echo ""

echo "--- Activity by 15-min window ---"
echo "$DATA" | awk '{
    split($2, t, ":")
    h = t[1]
    m = int(t[2] / 15) * 15
    printf "%s %s:%02d\n", $1, h, m
}' | sort | uniq -c | awk '{printf "%4d queries  %s %s\n", $1, $2, $3}'
echo ""

echo "--- Sites by 15-min window (top 5 per window) ---"
echo "$DATA" | awk '{
    split($2, t, ":")
    h = t[1]
    m = int(t[2] / 15) * 15
    printf "%s %s:%02d %s\n", $1, h, m, $NF
}' | \
    awk '{d=$3; sub(/^www\./,"",d); sub(/^m\./,"",d); n=split(d,a,"."); if(n>=2) d=a[n-1]"."a[n]; print $1, $2, d}' | \
    grep -vE "$NOISE" | \
    sort | uniq -c | sort -k2,3 -k1rn | \
    awk '{
        key=$2" "$3
        if (key != prev) { count=0; prev=key; if (NR>1) print "" }
        if (count < 5) { printf "%4d  %s %s  %s\n", $1, $2, $3, $4 }
        count++
    }'
