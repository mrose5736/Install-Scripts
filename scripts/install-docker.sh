#!/usr/bin/env bash
# ==============================================================================
# Script: install-docker.sh
# Description: Automated installer for Docker Engine, Docker CLI & Docker Compose
# Supported OS: Ubuntu / Debian
# Features:
#   - Automated OS detection & repository setup
#   - User added to docker group (no sudo required after relogin)
#   - Optimal daemon configuration (log rotation, overlay2, live restore)
# ==============================================================================

set -euo pipefail

# Require non-root user with sudo permissions
if [ "$EUID" -eq 0 ]; then
    echo "[!] Error: Please run this script as your regular user (e.g., 'mdrcloud')."
    echo "    Do not run directly with sudo. The script invokes sudo when required."
    exit 1
fi

CURRENT_USER=$(whoami)
echo "=========================================================="
echo " Starting Docker Base Installation for User: ${CURRENT_USER}"
echo "=========================================================="

# 1. Update system packages & install dependencies
echo "[*] Installing prerequisite system packages..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release openssl iptables

# 2. Detect OS distro (Ubuntu or Debian)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "[!] Error: Unable to detect OS distribution via /etc/os-release."
    exit 1
fi

if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
    echo "[!] Warning: Detected OS '${DISTRO}'. Official repository setup targets Ubuntu or Debian."
fi

# 3. Setup Official Docker Repository GPG key and repo
echo "[*] Setting up official Docker GPG key & repository for ${DISTRO}..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

DISTRO_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} ${DISTRO_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker Engine, CLI, Containerd, and Compose plugin
echo "[*] Installing Docker Engine, CLI, and Docker Compose plugin..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Configure daemon settings (Log rotation & live-restore)
echo "[*] Configuring Docker daemon (/etc/docker/daemon.json)..."
sudo mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    cat << EOF | sudo tee /etc/docker/daemon.json > /dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
    echo "[*] Restarting Docker service to apply configuration..."
    sudo systemctl restart docker
fi

# 6. Enable Docker service on boot
echo "[*] Enabling Docker systemd service..."
sudo systemctl enable docker

# 7. Add current user to Docker group
echo "[*] Adding user '${CURRENT_USER}' to the docker group..."
sudo usermod -aG docker "${CURRENT_USER}"

echo ""
echo "=========================================================="
echo " [✓] Docker Base installation completed successfully!"
echo " Docker Version: $(docker --version 2>/dev/null || sudo docker --version)"
echo " Compose Version: $(docker compose version 2>/dev/null || sudo docker compose version)"
echo ""
echo " Note: Remember to log out and back in (or run 'newgrp docker')"
echo " for non-root docker permissions to take effect."
echo "=========================================================="
