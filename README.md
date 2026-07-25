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

## 📋 Requirements
- **OS**: Ubuntu or Debian
- **User**: Regular user with `sudo` privileges (e.g. `mdrcloud`)

---

## 📜 License
[MIT License](LICENSE)

