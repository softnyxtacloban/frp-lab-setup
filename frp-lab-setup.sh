#!/bin/bash
###############################################################################
# FRP Bypass Lab Setup Script
# Target: Ubuntu Server 20.04 / 22.04 (traditional sysadmin practices)
# Functions:
# - System update
# - Install iptables, dnsmasq, openssl
# - Configure DNS spoofing (dnsmasq)
# - Configure iptables NAT for HTTP/HTTPS redirection to Burp
# - Generate custom CA certificate
# - (Optionally) Install CA on connected Android via ADB
# - Persistence of settings across reboots
# - SSL pinning bypass strategies summary
###############################################################################

set -e
set -u

# === Logging Setup ===
LOGFILE="/var/log/frp_setup.log"
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
chmod 644 "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# === Root Privilege Check ===
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Exiting."
    exit 1
fi

echo "==== Starting FRP Bypass Lab Setup at $(date) ===="

# === Error trap ===
trap 'echo "[$(date)] ERROR at line $LINENO: \"$BASH_COMMAND\" failed."' ERR

# === OS Check ===
source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    echo "Error: This script is intended for Ubuntu only."
    exit 1
fi
if [[ "$VERSION_ID" != "20.04" && "$VERSION_ID" != "22.04" ]]; then
    echo "Warning: Script tested only on Ubuntu 20.04 and 22.04. Proceed with caution."
fi

# === System Update & Package Installation ===
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y
echo "Installing required packages: iptables, dnsmasq, openssl..."
apt-get install -y iptables dnsmasq openssl adb

# === Detect Default Network Interface and IP ===
echo "Detecting network interface and IP..."
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')
DEFAULT_IP=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
if [[ -z "$DEFAULT_IP" ]]; then
    DEFAULT_IP=$(hostname -I | awk '{print $1}')
fi
echo "Detected Interface: $INTERFACE"
echo "Detected IP: $DEFAULT_IP"

# === DNS Spoofing Setup ===
echo "Configuring dnsmasq for DNS spoofing..."
read -p "Enter IP for DNS spoofing (default: $DEFAULT_IP): " SPOOF_IP
SPOOF_IP=${SPOOF_IP:-$DEFAULT_IP}
DNSMASQ_CONF="/etc/dnsmasq.conf"
cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.bak.$(date +%Y%m%d%H%M%S)"
echo -e "\n# FRP Bypass DNS Spoofing\naddress=/#/$SPOOF_IP" >>"$DNSMASQ_CONF"

systemctl restart dnsmasq
echo "dnsmasq restarted with DNS spoofing pointing to $SPOOF_IP."

# === iptables NAT Redirection Setup ===
echo "Setting up iptables NAT rules to redirect HTTP and HTTPS to port 8080..."
iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8080

# === Persist iptables Rules ===
echo "Persisting iptables rules via /etc/rc.local..."
RC_LOCAL="/etc/rc.local"
if [[ ! -f "$RC_LOCAL" ]]; then
    echo -e "#!/bin/sh -e\n\nexit 0" >"$RC_LOCAL"
    chmod +x "$RC_LOCAL"
fi
cp "$RC_LOCAL" "${RC_LOCAL}.bak.$(date +%Y%m%d%H%M%S)"

sed -i "/^exit 0/i iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080" "$RC_LOCAL"
sed -i "/^exit 0/i iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8080" "$RC_LOCAL"

# Enable rc-local service if needed
systemctl enable rc-local || echo "Warning: systemctl enable rc-local failed. Enable manually if needed."

# === Custom CA Certificate Generation ===
echo "Generating custom CA certificate for SSL interception..."
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -keyout customCA.key -out customCA.crt \
    -subj "/C=US/ST=CA/L=SanFrancisco/O=MyOrg/OU=ProxyCert/CN=MyCA"
echo "Custom CA certificate (customCA.crt) and key (customCA.key) generated."

# === Push CA to Android Device (Optional) ===
if command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
    echo "ADB device detected. Pushing CA certificate..."
    adb push customCA.crt /sdcard/Download/
    echo "Certificate pushed to /sdcard/Download on Android device."
    echo "Install manually via: Settings → Security → Install from storage."
else
    echo "No Android device connected. You can manually copy customCA.crt later."
fi

# === SSL Pinning Bypass Summary ===
echo ""
echo "=== SSL Pinning Bypass Techniques Summary ==="
echo "1) Dynamic Instrumentation using Frida:"
echo "   frida-trace -U -i \"*SSL*\" -f com.example.app"
echo ""
echo "2) Objection (Frida toolkit):"
echo "   objection --gadget com.example.app explore"
echo "   In the Objection shell: android sslpinning disable"
echo ""
echo "3) APK Reverse Engineering:"
echo "   apktool d app.apk"
echo "   # Edit to bypass SSL checks, rebuild:"
echo "   apktool b app/ -o app-patched.apk"
echo "   apksigner sign --ks mykeystore.jks app-patched.apk"
echo ""

echo "==== FRP Bypass Lab Setup Complete! ===="
echo "Check full logs at $LOGFILE"
exit 0
