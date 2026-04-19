#!/bin/bash
# daily-report.sh — Email daily summary of app kills and browsing activity
# Run via cron. Only sends if there was activity.

REPORT_TO="${REPORT_EMAIL:?Set REPORT_EMAIL in the launchd plist or environment}"
APP_LOG="/var/log/app-killer.log"
WEB_LOG="/var/log/web-blocker.log"
TODAY=$(date '+%Y-%m-%d')
HOSTNAME=$(hostname)

NOISE='(gstatic\.com|googleapis\.com|googleusercontent\.com|cloudfront\.net|akamaiedge\.net|cloudflare\.net|edgekey\.net|akadns\.net|apple\.com|icloud\.com|aaplimg\.com|apple-dns\.net|fastly\.net|imgix\.net|doubleclick\.net|google-analytics\.com|googletagmanager\.com|cloudflareinsights\.com|amazonaws\.com|awsglobalaccelerator\.com|googlehosted\.com|l\.google\.com|withgoogle\.com|insops\.net|bugsnag\.com|pendo\.io)'

# Collect app kill data
APP_DATA=""
if [[ -f "$APP_LOG" ]]; then
    APP_DATA=$(awk -v d="$TODAY" '$1 == d' "$APP_LOG")
fi

# Collect web log data
WEB_DATA=""
if [[ -f "$WEB_LOG" ]]; then
    WEB_DATA=$(awk -v d="$TODAY" '$1 == d' "$WEB_LOG")
fi

APP_COUNT=0
if [[ -n "$APP_DATA" ]]; then
    APP_COUNT=$(echo "$APP_DATA" | grep -c "KILLED" || true)
fi

WEB_COUNT=0
if [[ -n "$WEB_DATA" ]]; then
    WEB_COUNT=$(echo "$WEB_DATA" | grep -c . || true)
fi

# Skip if no activity at all
[[ "$APP_COUNT" -eq 0 ]] && [[ "$WEB_COUNT" -eq 0 ]] && exit 0

# Build report
REPORT="App-Killer Daily Report — $TODAY on $HOSTNAME

"

if [[ "$APP_COUNT" -gt 0 ]]; then
    REPORT+="=== APPS KILLED ($APP_COUNT total) ===

"
    REPORT+="By app:
$(echo "$APP_DATA" | awk '{print $4}' | sort | uniq -c | sort -rn)

"
    REPORT+="By 15-min window:
$(echo "$APP_DATA" | awk '{
    split($2, t, ":")
    h = t[1]; m = int(t[2] / 15) * 15
    printf "%s %s:%02d %s\n", $1, h, m, $4
}' | sort | uniq -c | sort -k2,3 -k1rn | awk '{printf "%4d  %s %s  %s\n", $1, $2, $3, $4}')

"
fi

if [[ "$WEB_COUNT" -gt 0 ]]; then
    SITES=$(echo "$WEB_DATA" | awk '{print $NF}' | \
        sed 's/^www\.//; s/^m\.//' | \
        awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}' | \
        grep -vE "^$NOISE$")

    SITE_COUNT=$(echo "$SITES" | grep -c . || true)

    REPORT+="=== SITES VISITED ($WEB_COUNT DNS queries, $SITE_COUNT to real sites) ===

"
    REPORT+="Top 20 sites:
$(echo "$SITES" | sort | uniq -c | sort -rn | head -20)

"
    REPORT+="Activity by 15-min window:
$(echo "$WEB_DATA" | awk '{
    split($2, t, ":")
    h = t[1]; m = int(t[2] / 15) * 15
    printf "%s %s:%02d\n", $1, h, m
}' | sort | uniq -c | awk '{printf "%4d queries  %s %s\n", $1, $2, $3}')

"
    REPORT+="Top sites by 15-min window:
$(echo "$WEB_DATA" | awk '{
    split($2, t, ":")
    h = t[1]; m = int(t[2] / 15) * 15
    printf "%s %s:%02d %s\n", $1, h, m, $NF
}' | awk '{d=$3; sub(/^www\./,"",d); sub(/^m\./,"",d); n=split(d,a,"."); if(n>=2) d=a[n-1]"."a[n]; print $1, $2, d}' | \
    grep -vE "$NOISE" | \
    sort | uniq -c | sort -k2,3 -k1rn | \
    awk '{
        key=$2" "$3
        if (key != prev) { count=0; prev=key; if (NR>1) printf "\n" }
        if (count < 5) { printf "%4d  %s %s  %s\n", $1, $2, $3, $4 }
        count++
    }')
"
fi

echo "$REPORT" | mail -s "App-Killer Report: $TODAY" "$REPORT_TO"
