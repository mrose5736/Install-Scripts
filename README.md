# 🚀 Infrastructure Install Scripts

Automated installation and setup scripts for infrastructure VMs (Debian/Ubuntu).

---

## 📦 Available Scripts

### 1. Docker Base Script (`install-docker.sh`)
Installs Docker Engine, Docker CLI, Docker Compose plugin, configures non-root user access, and sets up log rotation (`10m` max size, `3` max files) to prevent disk space exhaustion.

#### ⚡ One-Line Remote Execution
```bash
curl -fsSL https://raw.githubusercontent.com/mrose5736/Install-Scripts/main/scripts/install-docker.sh | bash
```

#### 🛠 Manual Execution
```bash
curl -fsSL -O https://raw.githubusercontent.com/mrose5736/Install-Scripts/main/scripts/install-docker.sh
chmod +x install-docker.sh
./install-docker.sh
```

---

### 2. Arcane (Docker Management UI)
Installs Docker, Docker Compose, auto-generates security keys (`ENCRYPTION_KEY` & `JWT_SECRET`), and deploys **Arcane** on port **3552**.

#### ⚡ One-Line Remote Execution (Recommended)
Run directly on your VM:
```bash
curl -fsSL https://raw.githubusercontent.com/mrose5736/Install-Scripts/main/scripts/install-arcane.sh | bash
```

#### 🛠 Manual Execution
```bash
curl -fsSL -O https://raw.githubusercontent.com/mrose5736/Install-Scripts/main/scripts/install-arcane.sh
chmod +x install-arcane.sh
./install-arcane.sh
```

---

### 3. Windows Server 2022 / 2025 Post-Install (`setup-windows-server.ps1`)
Post-installation baseline setup script for Windows Server 2022 and 2025 Datacenter.
- Checks and sets Timezone to Europe/London (`GMT Standard Time`).
- Configures English (UK) / `en-GB` language, system locale, and keyboard layout.
- Removes Windows Defender features (`Windows-Defender`).
- Checks and installs Google Chrome, Visual Studio Code (system-wide), and Voidtools Everything.
- Baseline Server Tweaks: Disables IE ESC, enables RDP with NLA, unhides file extensions & hidden files, sets High Performance power plan, and syncs NTP against the UK pool.

#### ⚡ One-Line Remote Execution (Elevated PowerShell)
```powershell
irm https://raw.githubusercontent.com/mrose5736/Install-Scripts/main/scripts/setup-windows-server.ps1 | iex
```

#### 🛠 Manual Execution
```powershell
# Run with all defaults (will prompt if Defender removal requires restart)
.\setup-windows-server.ps1

# Optional flags:
.\setup-windows-server.ps1 -AutoRestart
.\setup-windows-server.ps1 -SkipDefenderRemoval
.\setup-windows-server.ps1 -SkipSoftwareInstall
.\setup-windows-server.ps1 -SkipServerTweaks
```

---

## 📋 Requirements
- **Linux Scripts**: Ubuntu or Debian with `sudo` privileges.
- **Windows Script**: Windows Server 2022 or 2025 Datacenter run from an elevated Administrator PowerShell prompt.

---

## 📜 License
[MIT License](LICENSE)

