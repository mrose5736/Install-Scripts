# 🚀 Infrastructure Install Scripts

Automated installation and setup scripts for infrastructure VMs (Debian/Ubuntu).

---

## 📦 Available Scripts

### 1. Arcane (Docker Management UI)
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

## 📋 Requirements
- **OS**: Ubuntu or Debian
- **User**: Regular user with `sudo` privileges (e.g. `mdrcloud`)
- **Port**: `3552` open on firewall/network

---

## 📜 License
[MIT License](LICENSE)
