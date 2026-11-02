# Docker Installer for Linux

A single bash script (`install-docker.sh`) to install the latest Docker Engine and Docker Compose on Linux servers, with support for both online and airgap (offline) deployments via the `--airgap` flag.

## Quick Start

**Online (requires internet)**:
```bash
curl -fsSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh | bash
```

**Airgap (offline)**:
1. On internet-connected machine: `bash install-docker.sh --airgap --prepare`
2. Transfer directory to offline server
3. Run: `bash install-docker.sh --airgap ./docker-*`

## Features

- **Online Installation (default)**: Installs Docker directly via the official APT or DNF repositories.
- **Airgap/Offline (`--airgap`)**: Downloads packages for offline use (`--airgap --prepare`) or installs from previously downloaded packages (`--airgap <dir>`).
- **GPG Verification**: Validates Docker's official GPG fingerprint (apt and dnf) and aborts on mismatch.
- **SHA256 Checksums**: Integrity checking for offline packages (required unless `--allow-unverified`).
- **Automated Testing**: CI matrix validates on 14 Linux distributions (plus arm64 airgap installs on Ubuntu 24.04 and Fedora 44).

## Prerequisites

- Root or sudo privileges (for installation)
- Bash 4.3+ (standard on all supported distros)
- No existing Docker installation and no conflicting packages (`docker.io`, `docker-compose`, `docker-compose-v2`, `docker-doc`, `podman-docker`, `containerd`, `runc`, `podman`, …). The installer lists them with the removal command and aborts; it never removes them itself. Use `--upgrade` for an existing Docker CE install.

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
| `--version <ver>` | Pin `docker-ce` and `docker-ce-cli` to this package version (other packages follow the repo). apt: `5:29.8.2-1~ubuntu.24.04~noble`; dnf: `3:29.8.2-1.el9`. | `--version 5:29.8.2-1~ubuntu.24.04~noble` |
| `--upgrade` | Upgrade Docker if already installed (instead of aborting). | `--upgrade` |
| `-h, --help` | Show help message. | `--help` |

#### Examples

```bash
# Non-interactive install (useful for scripts/CI)
bash <(curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh) --yes

# Install a specific Docker version
bash install-docker.sh --version 5:29.8.2-1~ubuntu.24.04~noble

# Upgrade existing Docker installation
bash install-docker.sh --upgrade --yes
```

#### Supported Distributions

| OS                  | Versions                                  | Architecture | Package Manager |
| ------------------- | ----------------------------------------- | ------------ | --------------- |
| **Ubuntu**          | 22.04 LTS, 24.04 LTS, 26.04 LTS, 26.10    | amd64, arm64 | apt             |
| **Debian**          | 12, 13                                   | amd64, arm64, armhf | apt         |
| **Raspberry Pi OS** | 11, 12 (32-bit armhf is deprecated by Docker; Engine v28 is the last supported major) | armhf | apt |
| **RHEL**            | 8, 9, 10                                  | x86_64, aarch64 | dnf            |
| **CentOS Stream**   | 9, 10                                     | x86_64, aarch64 | dnf            |
| **Fedora**          | 43, 44, 45                                  | x86_64, aarch64 | dnf            |

Docker also publishes s390x (Ubuntu, RHEL) and ppc64le (Ubuntu, Debian, Fedora, CentOS) packages; `--prepare` passes these architectures through, but this repo's CI covers amd64 and arm64 only.

**Total CI coverage**: one job per distribution (14 + 2 arm64), each running a real end-to-end airgap install followed by an online install = 16 install jobs, plus a ShellCheck lint job.

### 2. Airgapped Installation (Offline)

#### Option A: Download a prebuilt bundle (easiest)

Each [release](https://github.com/ongtungduong/docker-installer/releases) ships a
self-contained `.tar.gz` per distro and architecture (amd64 + arm64), bundling the
Docker packages, `checksums.sha256` (plus `docker.gpg` for RPM bundles), and `install-docker.sh`:

```bash
# On the offline server (example: Ubuntu 24.04 amd64)
tar -xzf docker-ubuntu-noble-amd64.tar.gz
cd docker-ubuntu-noble-amd64
sudo ./install-docker.sh --airgap "$(pwd)"
```

Verify a download against the release's `SHA256SUMS.txt` before transferring (see Security Notes).

#### Option B: Prepare packages yourself

#### Step 1: Prepare Packages

On an internet-connected machine, download Docker packages:

```bash
# Auto-detect current OS and download packages
bash install-docker.sh --airgap --prepare

# Or specify target OS, version, and architecture explicitly
bash install-docker.sh --airgap --prepare --os ubuntu --os-version noble --arch amd64

# Preview what would be downloaded (dry-run)
bash install-docker.sh --airgap --prepare --os fedora --os-version 44 --arch x86_64 --dry-run
```

**Output**: A directory like `docker-ubuntu-noble-amd64-20260322/` containing:
- 5 Docker packages (docker-ce, docker-ce-cli, containerd.io, buildx-plugin, compose-plugin)
- `checksums.sha256` file for integrity verification
- `docker.gpg` (RPM only): Docker's RPM repo key, fingerprint-verified at prepare time

#### Step 2: Transfer to Offline Server

Copy the prepared directory to the target server (USB drive, network transfer, etc.):

```bash
scp -r docker-ubuntu-noble-amd64-20260322/ user@offline-server:/tmp/
```

#### Step 3: Install on Offline Server

On the airgapped server:

```bash
bash install-docker.sh --airgap /tmp/docker-ubuntu-noble-amd64-20260322
```

The script will:
1. Verify SHA256 checksums against `checksums.sha256`. The install aborts if the file is missing unless `--allow-unverified` is passed. RPM bundles also import the bundled `docker.gpg`.
2. Auto-detect `.deb` or `.rpm` packages and install them.
3. Enable Docker & containerd services to start on boot.
4. Configure docker group for non-root access.

#### Airgap Mode Flags

Pass `--airgap` first, then either `--prepare` (with the flags below) to download, or a package directory to install offline.

| Flag | Description | Example |
| ---- | ----------- | ------- |
| `--airgap` | Activate airgap mode (prepend to all airgap commands). | `--airgap` |
| `--prepare` | Download mode (used with `--airgap`). | `--airgap --prepare` |
| `--os <os>` | Target OS: ubuntu, debian, raspbian, rhel, centos, fedora | `--os ubuntu` |
| `--os-version <ver>` | OS version/codename: noble (24.04), resolute (26.04), stonking (26.10), 10 (RHEL 10), 45 (Fedora 45) | `--os-version noble` |
| `--arch <arch>` | Architecture: amd64, arm64, x86_64, aarch64, armhf, ppc64le/ppc64el, s390x | `--arch amd64` |
| `--allow-unverified` | Install even if `checksums.sha256` is missing (no integrity check; use only for packages you obtained and verified yourself). | `--airgap <dir> --allow-unverified` |
| `--dry-run` | Show what would download without actually downloading. | `--dry-run` |
| `-h, --help` | Show help. | `--help` |

#### Supported Architectures

| OS                  | Architectures                   |
| ------------------- | ------------------------------- |
| **Ubuntu**          | amd64 (x86_64), arm64 (aarch64), ppc64le, s390x |
| **Debian**          | amd64, arm64, armhf, ppc64le    |
| **Raspberry Pi OS** | armhf (32-bit ARM)              |
| **RHEL**            | x86_64, aarch64, s390x          |
| **CentOS Stream**   | x86_64, aarch64, ppc64le        |
| **Fedora**          | x86_64, aarch64, ppc64le        |

## Verification

After installation, verify Docker is working:

```bash
docker --version
docker run hello-world
docker compose version
```

If using non-root mode, you may need to log out and back in to apply docker group permissions.

## Security Notes

- **docker group is root-equivalent**: any member can mount the host filesystem into a container. The installer adds your user to the group and prints a warning; add only trusted users.
- **Firewall bypass**: ports published by containers bypass `ufw`/`firewalld` rules. Docker supports only `iptables-nft` and `iptables-legacy` (rules created with native nft are unsupported). Restrict published ports via the `DOCKER-USER` chain.
- **Airgap authenticity**: DEB bundles carry checksums only (integrity, not authenticity); RPM bundles additionally carry the repo key and are signature-checked on install. Verify the downloaded bundle against the release `SHA256SUMS.txt`, and keep `--allow-unverified` for packages you vetted yourself.
- **Pin the installer when using `curl | bash`**: replace `main` in the URL with a release tag or commit SHA so the script cannot change under you.

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
| **"gpg" missing** | The installer installs `gnupg` (apt) / `gnupg2` (dnf) itself to verify Docker's repo key; if that fails, install gpg manually and re-run |
| **"Conflicting packages found"** | Remove the listed packages (the message prints the command), then re-run; the installer never removes them automatically |
| **"checksums.sha256 not found" (airgap)** | Re-run `--airgap --prepare` or use a release bundle; pass `--allow-unverified` only for packages you verified yourself |
| **Checksum mismatch (airgap)** | Package corrupted during transfer; re-download via `--airgap --prepare` |
| **systemctl not available (containers)** | Expected in CI/Docker containers; services won't auto-start but installation succeeds |

## Disclaimer

This script uses official Docker endpoints and procedures. Always exercise caution when installing packages or executing scripts from the web. Use on untested operating systems at your own risk.

## License

See LICENSE file in repository.
