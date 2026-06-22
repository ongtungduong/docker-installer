# Docker Installer — Project Overview & PDR

## Project Purpose

Provide fast, reliable shell-script tooling to install Docker Engine and dependencies on Linux servers in two deployment scenarios:
- **Online environments**: Direct installation via official Docker repositories
- **Airgap/offline environments**: Package preparation on internet-connected machines, then offline installation on isolated systems

## Goals

1. **Simplify Docker setup** — Single command to install, no manual repository configuration or GPG key steps
2. **Support standard Linux distributions** — Cover 13+ distros across two package managers (apt, dnf)
3. **Secure by default** — GPG fingerprint verification, SHA256 checksum validation in offline mode
4. **Self-service deployment** — No custom packaging, artifact hosting, or infrastructure beyond GitHub
5. **Automate testing** — CI matrix validates both scripts on all supported distros before merge

## Non-Goals

- Kubernetes cluster provisioning or orchestration
- Docker daemon configuration tuning (users adjust `/etc/docker/daemon.json` if needed)
- Network access for airgap-prepared systems during installation (assumption: transferring packages is user's responsibility)
- Support for ancient distro versions (dropped Ubuntu <22.04, RHEL <8, etc.)

## Target Users

- **DevOps/SRE teams** automating server provisioning in cloud environments
- **Infrastructure engineers** setting up isolated/airgap networks in regulated environments
- **Developers** rapidly spinning up Docker-enabled VMs for testing
- **CI/CD platforms** bootstrapping Docker before running containerized workloads

## Success Criteria

| Criterion | Measure |
|-----------|---------|
| Installation speed | <90 seconds on modern hardware |
| Script size | <450 LOC for unified script (keep it readable) |
| GPG/checksum verification | 100% success on valid packages, 100% failure on corrupted/tampered |
| Distro support | All 13 tested distros pass CI matrix before merge |
| Error recovery | Cleanup trap removes partial config on failure; no orphaned repos |
| User experience | One-liner curl for online, 2-command workflow for airgap |

## Architecture Overview

### Single-Script, Multi-Mode Model

**`install-docker.sh`** (428 LOC)
- Unified installer supporting both online and offline deployment
- **Online mode** (default): Uses official Docker repositories, detects OS (`/etc/os-release`), selects apt or dnf, adds Docker GPG key, configures repository, installs packages, manages systemd services and user group permissions. Supports `--yes`, `--version`, `--upgrade` flags.
- **Airgap mode** (`--airgap` flag): Dual-mode operational pattern:
  - **Prepare** (`--airgap --prepare`): Auto-detects or accepts OS/version/arch, downloads packages, generates SHA256 checksums
  - **Install** (`--airgap <dir>`): Verifies checksums, detects `.deb` or `.rpm`, installs via `dpkg` or `rpm`
  - Dry-run support (`--airgap --prepare --dry-run`) for non-destructive planning

### Package List

Both scripts install:
- `docker-ce` — Docker Engine
- `docker-ce-cli` — Docker CLI
- `containerd.io` — Container runtime
- `docker-buildx-plugin` — BuildKit plugin
- `docker-compose-plugin` — Docker Compose v2

### Security Model

| Component | Mechanism |
|-----------|-----------|
| **apt** | GPG key verification using Docker's official fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` |
| **dnf** | Manual prompt (interactive) or silent pass in non-interactive mode; no key file verification currently |
| **Airgap** | SHA256 checksums pre-computed on prepare, validated before install |

## Supported Platforms

### APT (Debian-based)

| Distribution | Versions | Arch |
|---|---|---|
| Ubuntu | 22.04 LTS, 24.04 LTS, 25.10 | amd64, arm64 |
| Debian | 11 (Bullseye), 12 (Bookworm), 13 (Trixie) | amd64, armhf, arm64 |
| Raspberry Pi OS | 11, 12 | armhf |

### DNF (Red Hat-based)

| Distribution | Versions | Arch |
|---|---|---|
| RHEL | 8, 9 | x86_64, aarch64 |
| CentOS Stream | 9, 10 | x86_64, aarch64 |
| Fedora | 41, 42, 43 | x86_64, aarch64 |

**Total: 13 distros × 2 modes = 26 CI test jobs**

## Failure Modes & Recovery

| Mode | Cause | Recovery |
|---|---|---|
| **GPG verification fails** | Fingerprint mismatch (apt only) | Script dies; cleanup trap removes `/etc/apt/sources.list.d/docker.*` and `/etc/apt/keyrings/docker.asc` |
| **Package download fails** | Network issue or distro/arch mismatch | In prepare mode, script continues; user sees error count. Install still possible from partial dir. |
| **Checksum mismatch** | Corrupted/tampered package | Install mode dies; checksums.sha256 prevents accidental installation |
| **dpkg/rpm fails** | Dependency or pre-existing package conflict | apt-get install -f -y (dpkg path) attempts automatic fix; user must resolve rpm issues manually |
| **systemctl enable fails** | systemd not available in container | Soft warning; installation continues (services may not auto-start) |

## Release Process

1. Edit script(s) locally
2. Run through full CI matrix on PR
3. All 26 jobs pass → merge to main
4. GitHub Actions publishes release manifest
5. Users curl scripts directly from `main` branch (no release artifacts needed)

## Future Roadmap

### Potential Enhancements

- **zypper support** — SUSE Linux Enterprise, openSUSE (low priority, small user base)
- **Arch support** — Pacman package manager
- **ARM detection** — Better automatic architecture mapping for edge devices
- **Docker version pinning in airgap** — Allow `--prepare --version X.Y.Z` to lock specific releases
- **Systemd socket activation** — Configure Docker to start on-demand
- **Audit logging** — Log installation decisions and commands to syslog

### Known Limitations

- Airgap prepare requires internet access; no mirror support
- DNF GPG verification is manual/deferred (no fingerprint check in code)
- Scripts do not configure Docker daemon settings (users must customize `/etc/docker/daemon.json`)
- No automatic Docker storage driver selection for exotic setups (LVM, ZFS, etc.)
