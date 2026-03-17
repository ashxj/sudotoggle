# 🔐 sudotoggle

**Manage sudo NOPASSWD mode with ease — enable, disable, and set automatic expiry timers.**

---

## 📖 Table of Contents

- [About](#about)
- [Features](#features)
- [How It Works](#how-it-works)
- [Installation](#installation)
- [Usage](#usage)
- [Command Reference](#command-reference)
- [Configuration](#configuration)
- [Examples](#examples)
- [Files & Structure](#files--structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## 📌 About

`sudotoggle` is a lightweight Bash utility that simplifies managing passwordless `sudo` access on Linux systems. It creates and manages temporary or permanent NOPASSWD rules in `/etc/sudoers.d/`, complete with optional auto-expiry and real-time debug output.

Perfect for development sessions, automation scripts, or any workflow where frequent sudo access is needed without compromising long-term security.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🚀 **Quick Toggle** | Enable or disable passwordless sudo with a single command |
| ⏱️ **Timed Sessions** | Set automatic expiry (in seconds or at a specific time) |
| 🔍 **Debug Mode** | Real-time status output before every sudo command |
| 🛡️ **Safe Rollback** | Validates sudoers syntax before applying changes |
| 📊 **Status Overview** | View current state, expiry time, and remaining duration |
| 🐚 **Shell Integration** | Automatic hook installation for Bash and Zsh |

---

## ⚙️ How It Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        sudotoggle.sh                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Commands   │  │    Config    │  │      Shell Hook      │  │
│  │  -on / -off  │◄─┤  ~/.config/  │◄─┤  preexec / DEBUG     │  │
│  │  -debug      │  │  sudotoggle/ │  │  trap (Bash/Zsh)     │  │
│  │  -status     │  │   config     │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│         │                   │                      │            │
│         ▼                   ▼                      ▼            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              /etc/sudoers.d/nopasswd_<user>              │   │
│  │                   (NOPASSWD rule file)                   │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Flow Diagram

```
User runs: sudotoggle -on
        │
        ▼
┌───────────────────┐
│  Authenticate     │ ──► sudo -v (password prompt)
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Create Rule      │ ──► /etc/sudoers.d/nopasswd_<user>
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Validate Syntax  │ ──► visudo -cf
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Save Expiry      │ ──► ~/.config/sudotoggle/config
└───────────────────┘
        │
        ▼
   ✅ Enabled!
```

---

## 📦 Installation

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/sudotoggle.git
cd sudotoggle

# Make the script executable
chmod +x sudotoggle.sh

# (Optional) Move to a directory in your PATH
sudo mv sudotoggle.sh /usr/local/bin/sudotoggle
```

### Verify Installation

```bash
sudotoggle -status
```

---

## 🎯 Usage

### Basic Syntax

```bash
sudotoggle <command> [options]
```

### Command Reference

| Command | Arguments | Description |
|---------|-----------|-------------|
| `-on` | *(none)* | Enable NOPASSWD indefinitely |
| `-on` | `-time <seconds>` | Enable for specified duration |
| `-on` | `-timef <HH:MM>` | Enable until specific time |
| `-off` | *(none)* | Disable NOPASSWD immediately |
| `-debug` | `on` / `off` | Toggle debug output mode |
| `-status` | *(none)* | Display current configuration state |
| `-help` | *(none)* | Show help message |

### Arguments Detail

| Argument | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `-time` | Integer (seconds) | Yes (with `-time`) | — | Duration in seconds (e.g., `3600` for 1 hour) |
| `-timef` | String (HH:MM) | Yes (with `-timef`) | — | Target time in 24-hour format (e.g., `18:30`) |

---

## 🛠️ Configuration

Configuration is stored in `~/.config/sudotoggle/config`:

```ini
DEBUG=on
EXPIRY=1742334600
```

### Configuration Options

| Key | Values | Description |
|-----|--------|-------------|
| `DEBUG` | `on` / `off` | Enables debug output before sudo commands |
| `EXPIRY` | Unix timestamp / `unlimited` | Automatic disable time |

---

## 📚 Examples

### Enable Passwordless Sudo

```bash
# Enable indefinitely
sudotoggle -on

# Enable for 1 hour (3600 seconds)
sudotoggle -on -time 3600

# Enable until 6:30 PM today
sudotoggle -on -timef 18:30
```

### Disable Passwordless Sudo

```bash
sudotoggle -off
```

### Debug Mode

```bash
# Enable debug output
sudotoggle -debug on

# Sample output before sudo commands:
# [sudotoggle] 🔓 NOPASSWD ACTIVE — until 2025-03-17 18:30:00 (1234s remaining)
```

### Check Status

```bash
sudotoggle -status
```

**Sample Output:**
```
─────────────────────────────────────
  NOPASSWD:  ✅ ENABLED
  Expiry:    2025-03-17 18:30:00  (1234s remaining)
  Debug:     on
  User:      quintarionity
  File:      /etc/sudoers.d/nopasswd_quintarionity
─────────────────────────────────────
```

---

## 📁 Files & Structure

| Path | Purpose |
|------|---------|
| `/etc/sudoers.d/nopasswd_<user>` | Sudoers rule granting NOPASSWD access |
| `~/.config/sudotoggle/config` | User configuration (debug, expiry) |
| `~/.config/sudotoggle/hook.sh` | Shell hook for debug output and auto-expiry |

---

## 🔧 Troubleshooting

### Issue: "Passwordless sudo is already enabled"

**Solution:** Run `sudotoggle -status` to check current state. Use `-off` first if you want to reset.

### Issue: Hook not working in terminal

**Solution:** Source your shell config:
```bash
source ~/.bashrc   # for Bash
source ~/.zshrc    # for Zsh
```

### Issue: Other terminals still have sudo cached

**Solution:** Run `sudo -k` in those terminals to clear the credential cache.

### Issue: Timer expired but NOPASSWD still active

**Solution:** The auto-disable triggers on the **next sudo command**. Run any sudo command to trigger the cleanup.

---

## 📄 License

This project is provided as-is for educational and productivity purposes.

---

<div align="center">

**Made with ❤️ for the Linux community**

[⬆ Back to Top](#-sudotoggle)

</div>
