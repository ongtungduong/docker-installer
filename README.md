# Docker Installer for Linux

A single-command bash script to install the latest Docker Engine and Docker Compose on Linux servers.

## Features

- **Online Installation (`install-docker.sh`)**: Installs Docker directly via the official APT or DNF repositories.
- **Airgap/Offline (`install-docker-airgap.sh`)**: Downloads packages for offline use (`--prepare`) or installs from previously downloaded packages.

## Prerequisites

- Root or sudo privileges (for installation)
- No existing Docker installation (uninstall any conflicting packages first, or use `--upgrade`)

## Usage

### 1. Online Installation

To install Docker Engine directly on your Linux machine:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh)
```

#### Options

| Flag | Description |
| ---- | ----------- |
| `-y, --yes` | Non-interactive mode — skip all confirmation prompts. |
| `--version <ver>` | Install a specific Docker version (e.g., `5:27.5.1-1~ubuntu.24.04~noble`). |
| `--upgrade` | Upgrade Docker if already installed (instead of aborting). |
| `-h, --help` | Show help message. |

```bash
# Non-interactive install (useful for scripts/CI)
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh) --yes

# Install a specific version
bash install-docker.sh --version 5:27.5.1-1~ubuntu.24.04~noble

# Upgrade existing Docker installation
bash install-docker.sh --upgrade
```

- Supported Linux Distributions:

| OS                  | Supported Versions                        | Package Manager |
| ------------------- | ----------------------------------------- | --------------- |
| **Ubuntu**          | 25.10, 24.04 (LTS), 22.04 (LTS)           | apt             |
| **Debian**          | 13 (Trixie), 12 (Bookworm), 11 (Bullseye) | apt             |
| **Raspberry Pi OS** | 12 (stable), 11 (oldstable)               | apt             |
| **RHEL**            | 8, 9, 10                                  | dnf             |
| **CentOS Stream**   | 9, 10                                     | dnf             |
| **Fedora**          | 43, 42, 41                                | dnf             |

### 2. Airgapped Installation (Offline)

#### Step 1: Prepare packages (on an internet-connected machine)

```bash
# Auto-detect the current Linux machine and download packages
./install-docker-airgap.sh --prepare

# Or, explicitly define the target OS, version, and architecture (e.g., download Ubuntu 24.04 packages from a Mac)
./install-docker-airgap.sh --prepare --os ubuntu --os-version noble --arch amd64
```

The script generates a `checksums.sha256` file alongside the downloaded packages for integrity verification.

- Supported Linux Distributions:

| OS                  | Architecture          |
| ------------------- | --------------------- |
| **Ubuntu**          | 64-bit (amd64, arm64) |
| **Debian**          | amd64, armhf, arm64   |
| **Raspberry Pi OS** | 32-bit (armhf)        |
| **RHEL**            | x86_64, aarch64       |
| **CentOS Stream**   | x86_64, aarch64       |
| **Fedora**          | x86_64, aarch64       |

#### Step 2: Install on the airgapped server

Copy the downloaded package directory to the target server, then run:

```bash
sudo bash install-docker-airgap.sh ./docker-ubuntu-noble-amd64-20260320
```

The script will:
1. Verify SHA256 checksums (if `checksums.sha256` is present).
2. Auto-detect `.deb` or `.rpm` packages and install them.
3. Enable Docker & containerd services.

## Disclaimer

This script uses standard official Docker endpoints and procedures. However, always exercise caution when installing packages or using script execution from the web. Use it on untested operating systems at your own risk.
