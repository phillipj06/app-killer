#!/bin/bash
# web-blocker.sh — Block web traffic only when bad_user is at the console
# Uses pf for general blocking + /etc/hosts to blackhole domains by name
# OPTIMIZED: Only rewrites files when console user changes

BAD_USER="${1:?Usage: web-blocker.sh <bad_username>}"
ALLOWED_DOMAINS="/usr/local/etc/allowed-domains.txt"
BLOCKED_DOMAINS="/usr/local/etc/blocked-domains.txt"
PF_TABLE="/etc/pf.anchors/allowed-ips"
PF_CONF="/etc/pf.conf"
HOSTS="/etc/hosts"
MARKER_START="# >>> SPG-WEB-BLOCKER-START"
MARKER_END="# >>> SPG-WEB-BLOCKER-END"
STATE_FILE="/tmp/web-blocker-state"

CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)

# Read previous state
PREV_STATE=""
[[ -f "$STATE_FILE" ]] && PREV_STATE=$(cat "$STATE_FILE")

# Determine desired state
if [[ "$CONSOLE_USER" == "$BAD_USER" ]]; then
    DESIRED_STATE="blocked"
else
    DESIRED_STATE="open"
fi

# Check if PF IP cache needs refresh (every 30 min, re-resolve allowed domains)
PF_IP_CACHE="/tmp/pf-ip-cache.txt"
PF_CACHE_STALE=false
if [[ "$DESIRED_STATE" == "blocked" && -f "$PF_IP_CACHE" ]] && [[ -n "$(find "$PF_IP_CACHE" -mmin +30 2>/dev/null)" ]]; then
    PF_CACHE_STALE=true
    rm -f "$PF_IP_CACHE"
fi

# Skip if state hasn't changed AND PF cache is fresh
if [[ "$PREV_STATE" == "$DESIRED_STATE" ]] && ! $PF_CACHE_STALE; then
    exit 0
fi

# Update state file only on actual state change
if [[ "$PREV_STATE" != "$DESIRED_STATE" ]]; then
    echo "$DESIRED_STATE" > "$STATE_FILE"
fi

# Remove existing block rules from both files
sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$PF_CONF" 2>/dev/null
sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS" 2>/dev/null

if [[ "$DESIRED_STATE" == "open" ]]; then
    # Not the bad user — reload clean config and flush DNS
    pfctl -f "$PF_CONF" 2>/dev/null
    dscacheutil -flushcache 2>/dev/null
    killall -HUP mDNSResponder 2>/dev/null
    exit 0
fi

# ── Bad user is active — apply blocks ──

# === /etc/hosts: blackhole blocked domains by name ===
STEVENBLACK="/usr/local/etc/megalist-hosts.txt"
HOSTS_CACHE="/tmp/hosts-block-cache.txt"

# Build hosts cache if it doesn't exist or source files changed
REBUILD_CACHE=false
if [[ ! -f "$HOSTS_CACHE" ]]; then
    REBUILD_CACHE=true
elif [[ "$BLOCKED_DOMAINS" -nt "$HOSTS_CACHE" || "$STEVENBLACK" -nt "$HOSTS_CACHE" ]]; then
    REBUILD_CACHE=true
fi

if $REBUILD_CACHE; then
    > "$HOSTS_CACHE"

    # Manual block list (IPv4 and IPv6)
    if [[ -f "$BLOCKED_DOMAINS" ]]; then
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            base="${domain#\*.}"
            echo "127.0.0.1 $base" >> "$HOSTS_CACHE"
            echo "127.0.0.1 www.$base" >> "$HOSTS_CACHE"
            echo "::1 $base" >> "$HOSTS_CACHE"
            echo "::1 www.$base" >> "$HOSTS_CACHE"
        done < "$BLOCKED_DOMAINS"
    fi

    # Megalist (IPv4 and IPv6)
    if [[ -f "$STEVENBLACK" ]]; then
        sed 's/^/127.0.0.1 /' "$STEVENBLACK" >> "$HOSTS_CACHE"
        sed 's/^/::1 /' "$STEVENBLACK" >> "$HOSTS_CACHE"
    fi
fi

# Append cached hosts block
echo "$MARKER_START" >> "$HOSTS"
cat "$HOSTS_CACHE" >> "$HOSTS"
echo "$MARKER_END" >> "$HOSTS"
dscacheutil -flushcache 2>/dev/null
killall -HUP mDNSResponder 2>/dev/null

# === pf: block all web except allowed domains ===

# PF_IP_CACHE defined earlier (age check); rebuild if missing
if [[ ! -f "$PF_IP_CACHE" ]]; then
    > "$PF_IP_CACHE"

    # Add pre-fetched CDN IP ranges and resolved IPs (from setup.sh)
    for ipfile in /usr/local/etc/cloudfront-ips.txt /usr/local/etc/fastly-ips.txt /usr/local/etc/akamai-ips.txt /usr/local/etc/google-ips.txt /usr/local/etc/resolved-ips.txt; do
        [[ -f "$ipfile" ]] && cat "$ipfile" >> "$PF_IP_CACHE"
    done

    # Resolve allowed domains locally (target machine's DNS perspective)
    # Catches IPs that differ from what setup.sh resolved on the source machine
    if [[ -f "$ALLOWED_DOMAINS" ]]; then
        grep -v '^#' "$ALLOWED_DOMAINS" | grep -v '^$' | sed 's/^\*\.//' | sort -u | \
            xargs -P 10 -I{} sh -c 'dig +short +time=2 +tries=1 "$1" A 2>/dev/null | grep -E "^[0-9]+\."' _ {} >> "$PF_IP_CACHE" 2>/dev/null
    fi

    sort -u -o "$PF_IP_CACHE" "$PF_IP_CACHE"
fi

# Build blocked IPs from cache (no dig needed — setup.sh pre-resolved everything)
BLOCKED_IP_CACHE="/tmp/blocked-ip-cache.txt"
if [[ ! -f "$BLOCKED_IP_CACHE" ]]; then
    > "$BLOCKED_IP_CACHE"
    if [[ -f "$BLOCKED_DOMAINS" ]]; then
        while IFS= read -r domain; do
            [[ -z "$domain" || "$domain" == \#* ]] && continue
            base="${domain#\*.}"
            dig +short +time=2 +tries=1 "$base" A 2>/dev/null | grep -E '^[0-9]+\.' >> "$BLOCKED_IP_CACHE"
        done < "$BLOCKED_DOMAINS"
    fi
    sort -u -o "$BLOCKED_IP_CACHE" "$BLOCKED_IP_CACHE"
fi

IP_LIST=$(awk '{printf "%s, ", $0}' "$PF_IP_CACHE" | sed 's/, $//')
BLOCKED_IP_LIST=$(awk '{printf "%s, ", $0}' "$BLOCKED_IP_CACHE" | sed 's/, $//')

# Append block rules to pf.conf
cat >> "$PF_CONF" <<EOF
$MARKER_START
table <allowed_ips> { $IP_LIST }
table <blocked_ips> { $BLOCKED_IP_LIST }
block return out quick proto tcp from any to <blocked_ips> port { 80, 443 }
block return out quick inet6 proto tcp to any port { 80, 443 }
pass out quick on lo0 all
pass out quick proto { tcp, udp } to any port 53
pass out quick proto tcp to 10.0.0.0/8 port { 80, 443 }
pass out quick proto tcp to 172.16.0.0/12 port { 80, 443 }
pass out quick proto tcp to 192.168.0.0/16 port { 80, 443 }
pass out quick proto tcp to <allowed_ips> port { 80, 443 }
block return out proto tcp to any port { 80, 443 }
$MARKER_END
EOF

# Enable and reload
pfctl -e 2>/dev/null || true
pfctl -f "$PF_CONF" 2>/dev/null

# Kill existing connections only on state change (not every cycle)
pfctl -k 0/0 2>/dev/null
