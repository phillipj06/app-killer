#!/bin/bash
# refresh-cloudfront-ips.sh — Fetch CloudFront IP ranges from AWS and cache locally

OUT="/usr/local/etc/cloudfront-ips.txt"

JSON=$(curl -s https://ip-ranges.amazonaws.com/ip-ranges.json 2>/dev/null)

if [[ -z "$JSON" ]]; then
    echo "Failed to fetch AWS IP ranges" >&2
    exit 1
fi

# Parse CloudFront prefixes using grep/sed (no python needed)
# Look for CLOUDFRONT blocks and extract the ip_prefix/ipv6_prefix on the line before
echo "$JSON" | tr ',' '\n' | grep -B3 '"CLOUDFRONT"' | grep -oE '"ip_prefix"[^"]*"[^"]*"' | sed 's/.*"\([0-9].*\)"/\1/' > "$OUT"
echo "$JSON" | tr ',' '\n' | grep -B3 '"CLOUDFRONT"' | grep -oE '"ipv6_prefix"[^"]*"[^"]*"' | sed 's/.*"\([0-9a-f:].*\)"/\1/' >> "$OUT"

sort -u -o "$OUT" "$OUT"

COUNT=$(wc -l < "$OUT" | tr -d ' ')
echo "Cached $COUNT CloudFront IP ranges to $OUT"
