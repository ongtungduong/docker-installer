# Docker Installer for Linux

A single-command bash script to install the latest Docker Engine and Docker Compose on Linux servers.

## Features

- **Online Installation (`install-docker.sh`)**: Installs Docker directly via the official APT or DNF repositories.
- **Offline/Airgap Preparation (`prepare-airgap.sh`)**: Downloads the `.deb` or `.rpm` binaries for target architectures and operating systems so they can be securely moved to airgapped environments. 

## Prerequisites

- Root or sudo privileges (for installation)
- No existing Docker installation (uninstall any conflicting packages first)

## Usage

### 1. Online Installation

To install Docker Engine directly on your Linux machine:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh)
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

- Supported Linux Distributions:

```markdown
| OS                  | Architecture          |
| ------------------- | --------------------- |
| **Ubuntu**          | 64-bit (amd64, arm64) |
| **Debian**          | amd64, armhf, arm64   |
| **Raspberry Pi OS** | 32-bit (armhf)        |
| **RHEL**            | x86_64, aarch64       |
| **CentOS Stream**   | x86_64, aarch64       |
| **Fedora**          | x86_64, aarch64       |
```

## Disclaimer

This script uses standard official Docker endpoints and procedures. However, always exercise caution when installing packages or using script execution from the web. Use it on untested operating systems at your own risk.
