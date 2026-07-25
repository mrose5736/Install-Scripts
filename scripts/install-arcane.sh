#!/usr/bin/env bash
# ==============================================================================
# Script: install-arcane.sh
# Description: Automatic installer for Docker & Arcane Management UI (Port 3552)
# Supported OS: Ubuntu / Debian
# Target User: mdrcloud (or any user with sudo privileges)
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
echo " Starting Arcane Installation for User: ${CURRENT_USER}"
echo "=========================================================="

# 1. Update system packages and install prerequisites
echo "[*] Installing system dependencies..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release openssl

# 2. Setup Official Docker Repository
echo "[*] Setting up Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

DISTRO_CODENAME=$(lsb_release -cs)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${DISTRO_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3. Install Docker Engine & Docker Compose Plugin
echo "[*] Installing Docker Engine & Docker Compose..."
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 4. Add current user to Docker group
echo "[*] Adding user '${CURRENT_USER}' to the docker group..."
sudo usermod -aG docker "${CURRENT_USER}"

# 5. Create installation and project directories
ARCANE_DIR="${HOME}/arcane"
PROJECTS_DIR="${HOME}/arcane/projects"
echo "[*] Creating deployment directories at ${ARCANE_DIR}..."
mkdir -p "${ARCANE_DIR}" "${PROJECTS_DIR}"
cd "${ARCANE_DIR}"

# 6. Generate 32-byte secret encryption keys required by Arcane
echo "[*] Auto-generating Arcane security keys (ENCRYPTION_KEY & JWT_SECRET)..."
ENC_KEY=$(openssl rand -hex 32)
JWT_SEC=$(openssl rand -hex 32)

# 7. Write docker-compose.yml configuration
echo "[*] Creating docker-compose.yml..."
cat << EOF > docker-compose.yml
version: '3.8'

services:
  arcane:
    image: ghcr.io/getarcaneapp/manager:latest
    container_name: arcane
    restart: unless-stopped
    ports:
      - "3552:3552"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - arcane-data:/app/data
      - ${PROJECTS_DIR}:/projects
    environment:
      - ENCRYPTION_KEY=${ENC_KEY}
      - JWT_SECRET=${JWT_SEC}
      - PROJECTS_DIRECTORY=/projects
      - APP_URL=http://localhost:3552
      - PUID=1000
      - PGID=1000

volumes:
  arcane-data:
EOF

# 8. Start Arcane container stack
echo "[*] Pulling images and launching Arcane..."
sudo docker compose down --remove-orphans 2>/dev/null || true
sudo docker compose up -d

echo ""
echo "=========================================================="
echo " [✓] Arcane installation finished successfully!"
echo " Web UI: http://<YOUR_VM_IP>:3552"
echo ""
echo " Note: Remember to log out and log back in for 'docker'"
echo " commands to work without 'sudo'."
echo "=========================================================="
