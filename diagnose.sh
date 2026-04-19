#!/bin/bash
# diagnose.sh — Temporarily disable web blocker, capture DNS, then re-enable
# Run as: sudo ./diagnose.sh [duration_seconds]
# Browse the broken site during the capture window

DURATION="${1:-30}"

echo "=== Disabling web blocker ==="
sed -i '' '/SPG-WEB-BLOCKER-START/,/SPG-WEB-BLOCKER-END/d' /etc/pf.conf 2>/dev/null
sed -i '' '/SPG-WEB-BLOCKER-START/,/SPG-WEB-BLOCKER-END/d' /etc/hosts 2>/dev/null
pfctl -f /etc/pf.conf 2>/dev/null

# Flush DNS cache so ALL lookups appear in tcpdump (not just uncached ones)
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

echo "=== Capturing DNS for ${DURATION}s — browse the broken site NOW ==="
tcpdump -i any -n -l 'udp port 53' > /tmp/canvas-dns.txt 2>/dev/null &
TCPDUMP_PID=$!

sleep "$DURATION"

kill "$TCPDUMP_PID" 2>/dev/null
wait "$TCPDUMP_PID" 2>/dev/null

echo ""
echo "=== Re-enabling web blocker ==="
# Clear state file so web-blocker.sh re-applies rules from scratch
rm -f /tmp/web-blocker-state /tmp/pf-ip-cache.txt /tmp/blocked-ip-cache.txt
# The next 10-second cycle of web-blocker.sh will re-apply the rules automatically
# Force it now:
/usr/local/bin/web-blocker.sh "$(cat /Library/LaunchDaemons/local.web-blocker.plist | grep -A1 '__TARGET_USER__\|<string>' | grep -v ProgramArguments | tail -1 | sed 's/.*<string>//;s/<.*//')" 2>/dev/null

echo ""
echo "=== Domains captured ==="
grep -oE 'A\? [^ ]+' /tmp/canvas-dns.txt | awk '{print $2}' | sed 's/\.$//' | sort -u | tee /tmp/dns-domains.txt

echo ""
COUNT=$(wc -l < /tmp/dns-domains.txt | tr -d ' ')
echo "=== $COUNT unique domains saved to /tmp/dns-domains.txt ==="
