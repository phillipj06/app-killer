#!/bin/bash
# setup.sh — Run this on YOUR machine (with full network) to prepare the deploy package
# Usage: ./setup.sh
# Fetches CDN IP ranges, block lists, and resolves allowed domains.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

fetch_list() {
    local name="$1" url="$2" outfile="$3"
    echo "  Fetching $name..."
    if curl -sf "$url" | grep -v '^#' | grep -v '^$' | grep -v '^0.0.0.0' | awk '{print $1}' | sort -u >> "$outfile"; then
        return 0
    else
        echo "    WARNING: Failed to fetch $name"
        return 1
    fi
}

# ── CDN IP Ranges ──────────────────────────────────────────
echo "=== Fetching CDN IP ranges ==="

# CloudFront
echo "Fetching CloudFront IP ranges..."
curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | \
    awk '/"ip_prefix"/{gsub(/[",]/,"",$2); ip=$2} /"service": "CLOUDFRONT"/{print ip}' | \
    sort -u > "$SCRIPT_DIR/cloudfront-ips.txt"
echo "  $(wc -l < "$SCRIPT_DIR/cloudfront-ips.txt" | tr -d ' ') CloudFront ranges"

# Fastly
echo "Fetching Fastly IP ranges..."
curl -s https://api.fastly.com/public-ip-list | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort -u > "$SCRIPT_DIR/fastly-ips.txt"
echo "  $(wc -l < "$SCRIPT_DIR/fastly-ips.txt" | tr -d ' ') Fastly ranges"

# Akamai
echo "Fetching Akamai IPs..."
> "$SCRIPT_DIR/akamai-ips.txt"
for host in a.akamaiedge.net e.akamaiedge.net a.akamai.net e.akamai.net; do
    dig +short +time=5 +tries=1 "$host" A 2>/dev/null | grep -E '^[0-9]+\.' >> "$SCRIPT_DIR/akamai-ips.txt" || true
done
sort -u -o "$SCRIPT_DIR/akamai-ips.txt" "$SCRIPT_DIR/akamai-ips.txt"
echo "  $(wc -l < "$SCRIPT_DIR/akamai-ips.txt" | tr -d ' ') Akamai IPs"

# Google
echo "Fetching Google IP ranges..."
curl -s https://www.gstatic.com/ipranges/goog.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort -u > "$SCRIPT_DIR/google-ips.txt"
echo "  $(wc -l < "$SCRIPT_DIR/google-ips.txt" | tr -d ' ') Google ranges"

# ── Block Lists ────────────────────────────────────────────
echo ""
echo "=== Fetching block lists ==="

MEGALIST="$SCRIPT_DIR/megalist-hosts.txt"
> "$MEGALIST"

# StevenBlack — ads only (smaller, less overlap)
echo "Fetching StevenBlack hosts (ads only)..."
curl -sf https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts | \
    grep '^0.0.0.0' | awk '{print $2}' | grep -v '^0.0.0.0$' | sort -u >> "$MEGALIST"
echo "  StevenBlack ads loaded"

# UT1 Blacklists — only the essential categories
fetch_list "UT1 Gaming (33k+)" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/games/domains" "$MEGALIST"
fetch_list "UT1 Adult" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/adult/domains" "$MEGALIST"
fetch_list "UT1 Gambling" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/gambling/domains" "$MEGALIST"
fetch_list "UT1 Social Networks" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/social_networks/domains" "$MEGALIST"
fetch_list "UT1 Audio/Video" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/audio-video/domains" "$MEGALIST"
fetch_list "UT1 VPN" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/vpn/domains" "$MEGALIST"
fetch_list "UT1 AI" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/ai/domains" "$MEGALIST"
fetch_list "UT1 Warez/Piracy" \
    "https://raw.githubusercontent.com/olbat/ut1-blacklists/master/blacklists/warez/domains" "$MEGALIST"

# Dedupe the megalist
sort -u -o "$MEGALIST" "$MEGALIST"

# Remove any allowed domains from the megalist (safety valve)
if [[ -f "$SCRIPT_DIR/allowed-domains.txt" ]]; then
    ALLOWED_TEMP=$(mktemp)
    grep -v '^#' "$SCRIPT_DIR/allowed-domains.txt" | grep -v '^\*' | grep -v '^$' | sort -u > "$ALLOWED_TEMP"
    comm -23 "$MEGALIST" "$ALLOWED_TEMP" > "$MEGALIST.tmp"
    mv "$MEGALIST.tmp" "$MEGALIST"
    rm -f "$ALLOWED_TEMP"
fi

TOTAL=$(wc -l < "$MEGALIST" | tr -d ' ')
echo ""
echo "  === TOTAL: $TOTAL unique blocked domains ==="

# ── Resolve Allowed Domains ───────────────────────────────
echo ""
echo "=== Resolving allowed domains ==="

> "$SCRIPT_DIR/resolved-ips.txt"
while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    base="${domain#\*.}"
    dig +short +time=3 +tries=1 "$base" A 2>/dev/null | grep -E '^[0-9]+\.' >> "$SCRIPT_DIR/resolved-ips.txt" || true
done < "$SCRIPT_DIR/allowed-domains.txt"
sort -u -o "$SCRIPT_DIR/resolved-ips.txt" "$SCRIPT_DIR/resolved-ips.txt"
echo "  $(wc -l < "$SCRIPT_DIR/resolved-ips.txt" | tr -d ' ') resolved IPs from allowed-domains.txt"

# ── Summary ───────────────────────────────────────────────
echo ""
echo "=== Done ==="
echo "Files ready:"
echo "  cloudfront-ips.txt   — $(wc -l < "$SCRIPT_DIR/cloudfront-ips.txt" | tr -d ' ') CIDRs"
echo "  fastly-ips.txt       — $(wc -l < "$SCRIPT_DIR/fastly-ips.txt" | tr -d ' ') CIDRs"
echo "  akamai-ips.txt       — $(wc -l < "$SCRIPT_DIR/akamai-ips.txt" | tr -d ' ') IPs"
echo "  google-ips.txt       — $(wc -l < "$SCRIPT_DIR/google-ips.txt" | tr -d ' ') CIDRs"
echo "  resolved-ips.txt     — $(wc -l < "$SCRIPT_DIR/resolved-ips.txt" | tr -d ' ') IPs"
echo "  megalist-hosts.txt   — $TOTAL blocked domains"
echo ""
echo "Now deploy:"
echo "  scp -r $SCRIPT_DIR <user>@<target-ip>:~/"
echo "  ssh <user>@<target-ip> 'sudo ~/app-killer/install.sh <bad_username>'"
