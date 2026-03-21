# Docker Installer for Linux

A single-command bash script to install the latest Docker Engine and Docker Compose on Linux servers.

## Features

- **Online Installation (`install-docker.sh`)**: Installs Docker directly via the official APT or DNF repositories.
- **Offline/Airgap Preparation (`prepare-airgap.sh`)**: Downloads the `.deb` or `.rpm` binaries for target architectures and operating systems so they can be securely moved to airgapped environments.
- **Offline/Airgap Installation (`install-airgap.sh`)**: Installs Docker from previously downloaded packages with checksum verification.

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

### 2. Prepare Files for Airgapped Installation (Offline)

If your target server has no internet access, you can download the required Docker packages from any internet-connected machine (even a Mac) by running:

```bash
# Auto-detect the current Linux machine and download packages
./prepare-airgap.sh

# Or, explicitly define the target OS, version, and architecture (e.g., download Ubuntu 24.04 packages from a Mac)
./prepare-airgap.sh --os ubuntu --os-version noble --arch amd64
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

### 3. Install from Airgapped Packages

On the airgapped server, copy the downloaded package directory and run:

```bash
sudo bash install-airgap.sh ./docker-ubuntu-noble-amd64-20260320
```

The script will:
1. Verify SHA256 checksums (if `checksums.sha256` is present).
2. Auto-detect `.deb` or `.rpm` packages and install them.
3. Enable Docker & containerd services.

## Disclaimer

This script uses standard official Docker endpoints and procedures. However, always exercise caution when installing packages or using script execution from the web. Use it on untested operating systems at your own risk.
