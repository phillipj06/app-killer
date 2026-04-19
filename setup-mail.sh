#!/bin/bash
# setup-mail.sh — Configure postfix to relay through Gmail
# Run as: sudo ./setup-mail.sh
# Will prompt for Gmail address and app password

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0"
    exit 1
fi

echo "=== Gmail SMTP Setup ==="
echo "You need a Gmail app password. Generate one at:"
echo "  Google Account → Security → 2-Step Verification → App passwords"
echo ""

read -p "Gmail address: " GMAIL_USER
read -s -p "App password: " GMAIL_PASS
echo ""

# Configure postfix
MAIN_CF="/etc/postfix/main.cf"

# Remove any existing relay config
sed -i '' '/relayhost/d' "$MAIN_CF" 2>/dev/null
sed -i '' '/smtp_sasl/d' "$MAIN_CF" 2>/dev/null
sed -i '' '/smtp_use_tls/d' "$MAIN_CF" 2>/dev/null

# Add Gmail relay config
cat >> "$MAIN_CF" <<'EOF'
relayhost = [smtp.gmail.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_use_tls = yes
EOF

# Create password file (root-only)
echo "[smtp.gmail.com]:587 $GMAIL_USER:$GMAIL_PASS" > /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# Reload postfix
postfix reload 2>/dev/null || postfix start 2>/dev/null

echo ""
echo "=== Testing ==="
read -p "Send test email to: " TEST_DEST
echo "Test from app-killer on $(hostname)" | mail -s "App-Killer Mail Test" "$TEST_DEST"
echo "Check $TEST_DEST for the test email."
