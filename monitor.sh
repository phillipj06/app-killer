#!/bin/bash
# monitor.sh — Log all DNS lookups happening on this machine
# Run as: sudo ./monitor.sh [duration_seconds]
# Defaults to 120 seconds. Browse around during monitoring, then review results.

DURATION="${1:-120}"
LOGFILE="/tmp/dns-monitor.txt"

echo "Monitoring all DNS lookups for ${DURATION}s..."
echo "Browse around on the machine now. Press Ctrl+C to stop early."
echo ""

# tcpdump on all interfaces, capture UDP port 53 queries
# Parse the query name from standard DNS query format
sudo tcpdump -i en0 -n -l 'udp port 53' 2>/dev/null &
TCPDUMP_PID=$!

# Also try all interfaces in case en0 isn't the active one
sudo tcpdump -i any -n -l 'udp port 53' 2>/dev/null > /tmp/dns-raw.txt &
TCPDUMP2_PID=$!

sleep "$DURATION"

kill "$TCPDUMP_PID" "$TCPDUMP2_PID" 2>/dev/null
wait "$TCPDUMP_PID" "$TCPDUMP2_PID" 2>/dev/null

# Extract queried hostnames from tcpdump output
grep -oE ' A\? [^ ]+| AAAA\? [^ ]+' /tmp/dns-raw.txt | \
    awk '{print $2}' | \
    sed 's/\.$//' | \
    sort -u > "$LOGFILE"

COUNT=$(wc -l < "$LOGFILE" | tr -d ' ')
echo ""
echo "=== Captured $COUNT unique hostnames ==="
echo "Saved to: $LOGFILE"
echo ""

# Categorize
echo "--- Likely important (non-CDN/tracking) ---"
grep -vE '(metric|telemetry|analytics|tracking|beacon|pixel|crash|doubleclick|googlesyndication|safebrowsing|gvt[0-9]|update|ocsp|xp\.apple|push\.apple|configuration\.apple|lcdn-|cdn\.|cloudfront|akamai|fastly|edgekey|edgesuite|akadns|cloudflare|\.arpa$|\.local$|_tcp\.|_udp\.)' "$LOGFILE" | sort

echo ""
echo "--- Filtered out (CDN/tracking/infra) ---"
grep -E '(metric|telemetry|analytics|tracking|beacon|pixel|crash|doubleclick|googlesyndication|safebrowsing|gvt[0-9]|update|ocsp|xp\.apple|push\.apple|configuration\.apple|lcdn-|cdn\.|cloudfront|akamai|fastly|edgekey|edgesuite|akadns|cloudflare|\.arpa$|\.local$|_tcp\.|_udp\.)' "$LOGFILE" | sort

echo ""
echo "Full raw log: /tmp/dns-raw.txt"
