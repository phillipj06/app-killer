#!/bin/bash
# install.sh — Install app-killer and web-blocker on a target machine
# Run as: sudo ./install.sh <bad_username>

set -e

TARGET_USER="${1:?Usage: sudo ./install.sh <bad_username>}"
id "$TARGET_USER" >/dev/null 2>&1 || { echo "Error: user '$TARGET_USER' does not exist"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── App Killer ──────────────────────────────────────────────
echo "=== Installing App Killer ==="

cp "$SCRIPT_DIR/kill-apps.sh" /usr/local/bin/kill-apps.sh
cp "$SCRIPT_DIR/refresh-apps.sh" /usr/local/bin/refresh-apps.sh
chmod 755 /usr/local/bin/kill-apps.sh /usr/local/bin/refresh-apps.sh

echo "Seeding /tmp/apps.txt..."
/usr/local/bin/refresh-apps.sh

# Install launchd for app list refresh every 30 min
RA_PLIST="/Library/LaunchDaemons/local.refresh-apps.plist"
cp "$SCRIPT_DIR/local.refresh-apps.plist" "$RA_PLIST"
chown root:wheel "$RA_PLIST"
chmod 644 "$RA_PLIST"
launchctl bootout system/local.refresh-apps 2>/dev/null || true
launchctl bootstrap system "$RA_PLIST"

# Clean up old cron jobs if present
crontab -l 2>/dev/null | grep -v 'refresh-apps.sh' | grep -v 'refresh-cloudfront-ips.sh' | grep -v 'daily-report.sh' | crontab - 2>/dev/null

PLIST="/Library/LaunchDaemons/local.app-killer.plist"
sed "s/__TARGET_USER__/$TARGET_USER/g" "$SCRIPT_DIR/local.app-killer.plist" > "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootout system/local.app-killer 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "  App killer active — targeting user: $TARGET_USER"

# ── Web Blocker ─────────────────────────────────────────────
echo ""
echo "=== Installing Web Blocker ==="

cp "$SCRIPT_DIR/web-blocker.sh" /usr/local/bin/web-blocker.sh
cp "$SCRIPT_DIR/refresh-cloudfront-ips.sh" /usr/local/bin/refresh-cloudfront-ips.sh
chmod 755 /usr/local/bin/web-blocker.sh /usr/local/bin/refresh-cloudfront-ips.sh

mkdir -p /usr/local/etc
cp "$SCRIPT_DIR/allowed-domains.txt" /usr/local/etc/allowed-domains.txt
cp "$SCRIPT_DIR/blocked-domains.txt" /usr/local/etc/blocked-domains.txt
echo "  Installed /usr/local/etc/allowed-domains.txt"
echo "  Installed /usr/local/etc/blocked-domains.txt"

# Install mega block list (combined from 40+ sources)
if [[ -f "$SCRIPT_DIR/megalist-hosts.txt" ]]; then
    cp "$SCRIPT_DIR/megalist-hosts.txt" /usr/local/etc/megalist-hosts.txt
    echo "  Installed megalist-hosts.txt ($(wc -l < /usr/local/etc/megalist-hosts.txt | tr -d ' ') blocked domains)"
else
    echo "  WARNING: megalist-hosts.txt not found — run setup.sh first!"
fi

# Install pre-fetched CDN IP ranges and resolved IPs (from setup.sh)
MISSING=0
for ipfile in cloudfront-ips.txt fastly-ips.txt akamai-ips.txt google-ips.txt resolved-ips.txt; do
    if [[ -f "$SCRIPT_DIR/$ipfile" ]]; then
        cp "$SCRIPT_DIR/$ipfile" "/usr/local/etc/$ipfile"
        echo "  Installed $ipfile ($(wc -l < "/usr/local/etc/$ipfile" | tr -d ' ') entries)"
    else
        echo "  WARNING: $ipfile not found"
        MISSING=1
    fi
done
[[ "$MISSING" -eq 1 ]] && echo "  Run setup.sh on a machine with network access first!"

mkdir -p /etc/pf.anchors
touch /etc/pf.anchors/allowed-ips

# Clean up old anchor lines if present
sed -i '' '/web-blocker/d' /etc/pf.conf 2>/dev/null

# Enable pf
pfctl -e 2>/dev/null || true

# Clear stale caches so first cycle does full rebuild with local DNS resolution
rm -f /tmp/web-blocker-state /tmp/pf-ip-cache.txt /tmp/blocked-ip-cache.txt /tmp/hosts-block-cache.txt

# Install launchd — checks console user every 10 sec, toggles block
WB_PLIST="/Library/LaunchDaemons/local.web-blocker.plist"
sed "s/__TARGET_USER__/$TARGET_USER/g" "$SCRIPT_DIR/local.web-blocker.plist" > "$WB_PLIST"
chown root:wheel "$WB_PLIST"
chmod 644 "$WB_PLIST"

launchctl bootout system/local.web-blocker 2>/dev/null || true
launchctl bootstrap system "$WB_PLIST"

echo "  Web blocker active — targeting user: $TARGET_USER"

# ── Web Logger ──────────────────────────────────────────────
echo ""
echo "=== Installing Web Logger ==="

cp "$SCRIPT_DIR/web-logger.sh" /usr/local/bin/web-logger.sh
sed -i '' "s/__TARGET_USER__/$TARGET_USER/g" /usr/local/bin/web-logger.sh
chmod 755 /usr/local/bin/web-logger.sh

WL_PLIST="/Library/LaunchDaemons/local.web-logger.plist"
cp "$SCRIPT_DIR/local.web-logger.plist" "$WL_PLIST"
chown root:wheel "$WL_PLIST"
chmod 644 "$WL_PLIST"

launchctl bootout system/local.web-logger 2>/dev/null || true
launchctl bootstrap system "$WL_PLIST"

echo "  Web logger active — logging to /var/log/web-blocker.log"

# ── Daily Report ────────────────────────────────────────────
echo ""
echo "=== Installing Daily Report ==="

DR_PLIST="/Library/LaunchDaemons/local.daily-report.plist"
cp "$SCRIPT_DIR/local.daily-report.plist" "$DR_PLIST"
chown root:wheel "$DR_PLIST"
chmod 644 "$DR_PLIST"

launchctl bootout system/local.daily-report 2>/dev/null || true
launchctl bootstrap system "$DR_PLIST"

echo "  Daily report active — emails weekdays at 3:45 PM to \$REPORT_EMAIL"

# ── Summary ─────────────────────────────────────────────────
echo ""
echo "=== Done ==="
echo "  App Killer: kills apps for '$TARGET_USER' every 10 sec (Safari/Preview/System Settings/Mail spared)"
echo "  Web Blocker: blocks ports 80/443 for '$TARGET_USER' except domains in /usr/local/etc/allowed-domains.txt"
echo "  Web Logger: logs all blocked site attempts to /var/log/web-blocker.log"
echo ""
echo "Audit:"
echo "  sudo ~/app-killer/audit.sh today       # app kills"
echo "  sudo ~/app-killer/web-audit.sh today    # blocked sites"
echo ""
echo "To uninstall:"
echo "  sudo launchctl bootout system/local.app-killer"
echo "  sudo launchctl bootout system/local.web-blocker"
echo "  sudo launchctl bootout system/local.web-logger"
echo "  sudo rm /usr/local/bin/{kill-apps.sh,refresh-apps.sh,web-blocker.sh,web-logger.sh}"
echo "  sudo rm /Library/LaunchDaemons/local.app-killer.plist"
echo "  sudo rm /Library/LaunchDaemons/local.web-blocker.plist"
echo "  sudo rm /Library/LaunchDaemons/local.web-logger.plist"
echo "  sudo rm /etc/pf.anchors/allowed-ips"
echo "  sudo crontab -l | grep -v refresh-apps.sh | sudo crontab -"
echo "  # Run: sudo sed -i '' '/SPG-WEB-BLOCKER/d' /etc/pf.conf"
