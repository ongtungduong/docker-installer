# Docker Installer for Linux

A single-command bash script to install the latest Docker Engine and Docker Compose on Linux servers, with support for both online and airgap (offline) deployments.

## Quick Start

**Online (requires internet)**:
```bash
curl -fsSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh | bash
```

**Airgap (offline)**:
1. On internet-connected machine: `bash install-docker-airgap.sh --prepare`
2. Transfer directory to offline server
3. Run: `bash install-docker-airgap.sh ./docker-*`

## Features

- **Online Installation (`install-docker.sh`)**: Installs Docker directly via the official APT or DNF repositories.
- **Airgap/Offline (`install-docker-airgap.sh`)**: Downloads packages for offline use (`--prepare`) or installs from previously downloaded packages.
- **GPG Verification**: Validates Docker's official GPG fingerprint on apt-based systems.
- **SHA256 Checksums**: Integrity checking for offline packages.
- **Automated Testing**: CI matrix validates on 13 Linux distributions.

## Prerequisites

- Root or sudo privileges (for installation)
- Bash 3.0+ (standard on all supported distros)
- No existing Docker installation (uninstall any conflicting packages first, or use `--upgrade`)

## Usage

### 1. Online Installation

To install Docker Engine directly on your Linux machine:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh)
```

#### Flags

| Flag | Description | Example |
| ---- | ----------- | ------- |
| `-y, --yes` | Non-interactive mode — skip all confirmation prompts. | `--yes` |
| `--version <ver>` | Install a specific Docker version. | `--version 5:27.5.1-1~ubuntu.24.04~noble` |
| `--upgrade` | Upgrade Docker if already installed (instead of aborting). | `--upgrade` |
| `-h, --help` | Show help message. | `--help` |

#### Examples

```bash
# Non-interactive install (useful for scripts/CI)
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh) --yes

# Install a specific Docker version
bash install-docker.sh --version 5:27.5.1-1~ubuntu.24.04~noble

# Upgrade existing Docker installation
bash install-docker.sh --upgrade --yes
```

#### Supported Distributions

| OS                  | Versions                                  | Architecture | Package Manager |
| ------------------- | ----------------------------------------- | ------------ | --------------- |
| **Ubuntu**          | 22.04 LTS, 24.04 LTS, 25.10               | amd64, arm64 | apt             |
| **Debian**          | 11, 12, 13                               | amd64, arm64, armhf | apt         |
| **Raspberry Pi OS** | 11, 12                                    | armhf        | apt             |
| **RHEL**            | 8, 9                                      | x86_64, aarch64 | dnf            |
| **CentOS Stream**   | 9, 10                                     | x86_64, aarch64 | dnf            |
| **Fedora**          | 41, 42, 43                                | x86_64, aarch64 | dnf            |

**Total CI coverage**: 13 distributions × 2 modes = 26 automated tests before each release.

### 2. Airgapped Installation (Offline)

#### Step 1: Prepare Packages

On an internet-connected machine, download Docker packages:

```bash
# Auto-detect current OS and download packages
bash install-docker-airgap.sh --prepare

# Or specify target OS, version, and architecture explicitly
bash install-docker-airgap.sh --prepare --os ubuntu --os-version noble --arch amd64

# Preview what would be downloaded (dry-run)
bash install-docker-airgap.sh --prepare --os fedora --os-version 42 --arch x86_64 --dry-run
```

**Output**: A directory like `docker-ubuntu-noble-amd64-20260322/` containing:
- 5 Docker packages (docker-ce, docker-ce-cli, containerd.io, buildx-plugin, compose-plugin)
- `checksums.sha256` file for integrity verification

#### Step 2: Transfer to Offline Server

Copy the prepared directory to the target server (USB drive, network transfer, etc.):

```bash
scp -r docker-ubuntu-noble-amd64-20260322/ user@offline-server:/tmp/
```

#### Step 3: Install on Offline Server

On the airgapped server:

```bash
bash install-docker-airgap.sh /tmp/docker-ubuntu-noble-amd64-20260322
```

The script will:
1. Verify SHA256 checksums against `checksums.sha256` (prevents corrupted/tampered packages).
2. Auto-detect `.deb` or `.rpm` packages and install them.
3. Enable Docker & containerd services to start on boot.
4. Configure docker group for non-root access.

#### Prepare Mode Flags

| Flag | Description | Example |
| ---- | ----------- | ------- |
| `--prepare` | Download mode. | `--prepare` |
| `--os <os>` | Target OS: ubuntu, debian, raspbian, rhel, centos, fedora | `--os ubuntu` |
| `--os-version <ver>` | OS version/codename: noble (24.04), 9 (RHEL 9), 42 (Fedora 42) | `--os-version noble` |
| `--arch <arch>` | Architecture: amd64, arm64, x86_64, aarch64, armhf | `--arch amd64` |
| `--dry-run` | Show what would download without actually downloading. | `--dry-run` |
| `-h, --help` | Show help. | `--help` |

#### Supported Architectures

| OS                  | Architectures                   |
| ------------------- | ------------------------------- |
| **Ubuntu**          | amd64 (x86_64), arm64 (aarch64) |
| **Debian**          | amd64, arm64, armhf             |
| **Raspberry Pi OS** | armhf (32-bit ARM)              |
| **RHEL**            | x86_64, aarch64                 |
| **CentOS Stream**   | x86_64, aarch64                 |
| **Fedora**          | x86_64, aarch64                 |

## Verification

After installation, verify Docker is working:

```bash
docker --version
docker run hello-world
docker compose version
```

If using non-root mode, you may need to log out and back in to apply docker group permissions.

## Documentation

For more information:
- **Project Overview & Requirements**: See `docs/project-overview-pdr.md`
- **System Architecture & Technical Deep Dive**: See `docs/system-architecture.md`
- **Code Standards & Contributing**: See `docs/code-standards.md`
- **Deployment & CI Testing**: See `docs/deployment-guide.md`
- **Project Roadmap**: See `docs/project-roadmap.md`

## Troubleshooting

| Issue | Solution |
| ----- | -------- |
| **"Docker is already installed"** | Use `--upgrade` flag to update existing installation, or uninstall first: `apt remove docker-ce` or `dnf remove docker-ce` |
| **Permission denied on docker commands** | User not in docker group; log out and back in, or `newgrp docker` |
| **"gpg not found" warning (apt)** | GPG verification skipped but repo trusted; safe to continue |
| **Checksum mismatch (airgap)** | Package corrupted during transfer; re-download via `--prepare` |
| **systemctl not available (containers)** | Expected in CI/Docker containers; services won't auto-start but installation succeeds |

## Disclaimer

This script uses official Docker endpoints and procedures. Always exercise caution when installing packages or executing scripts from the web. Use on untested operating systems at your own risk.

## License

See LICENSE file in repository.
