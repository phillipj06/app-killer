#!/bin/bash
# resolve-domains.sh — Parallel DNS resolution for all allowed domains
# Run this on YOUR machine (with full network access)
# Usage: bash resolve-domains.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWED="$SCRIPT_DIR/allowed-domains.txt"
OUTFILE="$SCRIPT_DIR/resolved-ips.txt"
TMPDIR=$(mktemp -d)
MAX_JOBS=50

echo "=== Resolving allowed domains (parallel, up to $MAX_JOBS at a time) ==="

# Extract unique base domains
grep -v '^#' "$ALLOWED" | grep -v '^$' | sed 's/^\*\.//' | sort -u > "$TMPDIR/domains.txt"
TOTAL=$(wc -l < "$TMPDIR/domains.txt" | tr -d ' ')
echo "  $TOTAL unique domains to resolve"

# Resolve in parallel
COUNT=0
while IFS= read -r domain; do
    (
        dig +short +time=2 +tries=1 "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' > "$TMPDIR/$(echo "$domain" | tr '/' '_').ips" || true
    ) &
    COUNT=$((COUNT + 1))
    # Throttle to MAX_JOBS concurrent
    if (( COUNT % MAX_JOBS == 0 )); then
        wait
        echo "  resolved $COUNT / $TOTAL ..."
    fi
done < "$TMPDIR/domains.txt"
wait
echo "  resolved $COUNT / $TOTAL ... done"

# Collect failures (empty .ips files = no resolution)
FAILED=0
FAILED_LIST=""
for f in "$TMPDIR"/*.ips; do
    if [[ ! -s "$f" ]]; then
        domain=$(basename "$f" .ips | tr '_' '/')
        FAILED_LIST+="  $domain\n"
        FAILED=$((FAILED + 1))
    fi
done

# Merge all results
cat "$TMPDIR"/*.ips 2>/dev/null | sort -u > "$OUTFILE"
rm -rf "$TMPDIR"

RESOLVED=$(wc -l < "$OUTFILE" | tr -d ' ')
SUCCEEDED=$((TOTAL - FAILED))
echo ""
echo "=== Results ==="
echo "  $SUCCEEDED / $TOTAL domains resolved -> $RESOLVED unique IPs"
if (( FAILED > 0 )); then
    echo ""
    echo "  WARNING: $FAILED domains failed to resolve:"
    echo -e "$FAILED_LIST"
    echo "  These are likely CNAMEs, wildcards, or stale entries — review if any are critical."
fi
