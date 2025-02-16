#!/bin/bash
set -e

# Constants
LOG_FILE="/var/log/nabu-tweaks-setup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logger function
log() {
    echo "[${TIMESTAMP}] $1" | tee -a "${LOG_FILE}"
}

# Error handler
handle_error() {
    log "Error occurred at line $1"
    exit 1
}

# Set error handler
trap 'handle_error "$LINENO"' ERR

log "Starting Xiaomi Pad 5 post-installation setup..."

# Create log file with appropriate permissions
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log "Error: Required command '$1' not found"
        return 1
    fi
}

# Perform system checks
log "Performing system checks..."
check_command systemctl || exit 1

# Generate a fixed MAC address for WLAN based on machine-info
if [ -f "/etc/machine-id" ]; then
    interface=wlan0
    mac="$((cat /etc/machine-id; echo ${interface}; ) | sha256sum -)"
    echo "[Match]" > /etc/systemd/network/10-$interface.network
    echo "Name=$interface" >> /etc/systemd/network/10-$interface.network
    echo "" >> /etc/systemd/network/10-$interface.network
    echo "[Link]" >> /etc/systemd/network/10-$interface.network
    echo "MACAddress=42:${mac:0:2}:${mac:4:2}:${mac:8:2}:${mac:12:2}:${mac:16:2}" >> /etc/systemd/network/10-$interface.network
    # Restart systemd-networkd to apply changes
    systemctl enable --now systemd-networkd
else
    log "Warning: /etc/machine-id not found, skipping WLAN MAC address configuration"
fi

# GNOME: Show only mounted drives in Dash to Dock
if command -v "gsettings" >/dev/null 2>&1; then
    gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts-only-mounted true || exit 1
fi

log "Post-installation setup completed successfully"
exit 0