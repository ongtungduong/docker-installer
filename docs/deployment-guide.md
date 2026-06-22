# Deployment & CI Testing Guide

## Local Testing

### Prerequisites

- Bash 3.0+ (Ubuntu 22.04+ has 5.1+)
- sudo or root access
- curl installed

### Syntax Validation

Before committing, validate bash syntax:

```bash
bash -n install-docker.sh
bash -n install-docker-airgap.sh
```

No output = syntax OK. Any errors will be printed.

### Manual Testing

#### Online Installer

**In a VM or container with internet access**:

```bash
# Test help
bash install-docker.sh --help

# Test non-interactive installation
bash install-docker.sh --yes

# Test with specific version (requires valid version string)
bash install-docker.sh --version 5:27.5.1-1~ubuntu.24.04~noble

# Test upgrade flag (after initial install)
bash install-docker.sh --upgrade

# Verify installation
docker --version
docker compose version
```

**Expected output**:
```
[INFO] Detecting OS…
[INFO] Installing prerequisites…
[INFO] Adding Docker GPG key…
[INFO] Verifying Docker GPG key fingerprint…
[INFO] Adding Docker APT repository…
[INFO] Installing Docker Engine…
[INFO] Enabling Docker & containerd on boot…
[INFO] Configuring Docker for non-root usage (adding to 'docker' group)…
[INFO] Docker installed successfully!
```

**Cleanup after test** (if you want to re-run):
```bash
# Ubuntu/Debian
sudo rm -rf /etc/apt/sources.list.d/docker.* /etc/apt/keyrings/docker.asc
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# RHEL/Fedora
sudo rm -f /etc/yum.repos.d/docker-ce.repo
sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

#### Airgap Installer

**Prepare mode (on machine with internet access)**:

```bash
# Auto-detect current OS
bash install-docker-airgap.sh --prepare

# Explicit OS/version/arch
bash install-docker-airgap.sh --prepare --os ubuntu --os-version noble --arch amd64

# Dry-run (show what would download, don't actually download)
bash install-docker-airgap.sh --prepare --os fedora --os-version 42 --arch x86_64 --dry-run

# Prepare for Raspberry Pi (armhf)
bash install-docker-airgap.sh --prepare --os raspbian --os-version bookworm --arch armhf
```

**Expected output**:
```
[INFO] Target OS: ubuntu | Version: noble | Arch: amd64
[INFO] Preparing airgap files in ./docker-ubuntu-noble-amd64-20260322
[INFO] Fetching index from https://download.docker.com/linux/ubuntu/dists/noble/pool/stable/amd64/
[INFO] Finding latest package for: docker-ce
[INFO] Downloading docker-ce_27.5.1_3~0~ubuntu-noble_amd64.deb…
...
[INFO] Generating SHA256 checksums…
[INFO] Completed! All files downloaded to ./docker-ubuntu-noble-amd64-20260322
[INFO] Checksums saved to ./docker-ubuntu-noble-amd64-20260322/checksums.sha256
```

**Install mode (on airgap/offline machine)**:

```bash
# Copy the prepared directory to the target server:
# scp -r docker-ubuntu-noble-amd64-20260322 user@airgap-host:/tmp/

# On the airgap host, install:
sudo bash install-docker-airgap.sh /tmp/docker-ubuntu-noble-amd64-20260322
```

**Expected output**:
```
[INFO] Verifying SHA256 checksums…
[INFO] All checksums verified.
[INFO] Found 5 .deb packages. Installing with dpkg…
[INFO] Enabling Docker & containerd on boot…
[INFO] Configuring Docker for non-root usage (adding to 'docker' group)…
[INFO] Docker installed successfully (offline)!
```

---

## CI Testing

### Workflow File

**Location**: `.github/workflows/test-install.yml`

**Triggers**:
- Push to main
- Pull request to main
- Manual dispatch (GitHub UI > "Run workflow")

### Matrix

The workflow tests both scripts across 13 Linux distributions in two stages:

#### Stage 1: APT Distros (6 jobs)

| Distro | Version | Image | Package Manager |
|--------|---------|-------|---|
| Ubuntu | 22.04 (Jammy) | ubuntu:22.04 | apt |
| Ubuntu | 24.04 (Noble) | ubuntu:24.04 | apt |
| Ubuntu | 25.10 (Plucky) | ubuntu:25.10 | apt |
| Debian | 11 (Bullseye) | debian:11 | apt |
| Debian | 12 (Bookworm) | debian:12 | apt |
| Debian | 13 (Trixie) | debian:13 | apt |

#### Stage 2: DNF Distros (7 jobs)

| Distro | Version | Image | Package Manager |
|--------|---------|-------|---|
| RHEL | 8 | registry.access.redhat.com/ubi8/ubi | dnf |
| RHEL | 9 | registry.access.redhat.com/ubi9/ubi | dnf |
| CentOS Stream | 9 | quay.io/centos/centos:stream9 | dnf |
| CentOS Stream | 10 | quay.io/centos/centos:stream10 | dnf |
| Fedora | 41 | fedora:41 | dnf |
| Fedora | 42 | fedora:42 | dnf |
| Fedora | 43 | fedora:43 | dnf |

### What Each Job Does

**For every container in the matrix**:

1. **Install prerequisites**:
   ```bash
   apt-get update -y && apt-get install -y curl sudo   # APT
   dnf install -y --allowerasing curl sudo             # DNF
   ```

2. **Download both scripts**:
   ```bash
   curl -sSL https://raw.githubusercontent.com/[owner]/docker-installer/[commit]/install-docker.sh \
     -o /tmp/install-docker.sh
   curl -sSL https://raw.githubusercontent.com/[owner]/docker-installer/[commit]/install-docker-airgap.sh \
     -o /tmp/install-docker-airgap.sh
   ```

3. **Mock systemctl** (containers don't have systemd):
   ```bash
   printf '#!/bin/bash\nexit 0\n' > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl
   ```
   This stub allows `systemctl enable --now` to succeed without a real systemd daemon.

4. **Run online installer**:
   ```bash
   bash /tmp/install-docker.sh --yes
   ```

5. **Verify Docker installed**:
   ```bash
   docker --version
   docker compose version
   ```

6. **Test airgap prepare (dry-run)**:
   ```bash
   bash /tmp/install-docker-airgap.sh --prepare \
     --os [matrix.os] \
     --os-version [matrix.version] \
     --arch [amd64 for APT, x86_64 for DNF] \
     --dry-run
   ```

### CI Environment Variables

| Variable | Value | Used For |
|----------|-------|----------|
| `SCRIPT_URL` | `https://raw.githubusercontent.com/${{github.repository}}/${{github.sha}}/install-docker.sh` | Download latest script from current branch/commit |
| `AIRGAP_SCRIPT_URL` | Similar for airgap script | Download latest airgap script |

This ensures every CI run tests the *current* code changes, not main branch code.

### Fail-Fast Setting

```yaml
strategy:
  fail-fast: false
```

This means:
- If Ubuntu 22.04 job fails, other jobs still run
- Allows you to see all failing distros at once
- Useful for identifying distro-specific issues

### Local CI Simulation

To test locally before pushing:

#### Option 1: Run in Docker

```bash
# Test on Ubuntu 24.04
docker run -it -v $PWD:/work ubuntu:24.04 bash
cd /work
apt-get update && apt-get install -y curl sudo
bash install-docker.sh --help   # Syntax check without install

# Test on Fedora 42
docker run -it -v $PWD:/work fedora:42 bash
cd /work
dnf install -y curl sudo
bash install-docker.sh --help
```

#### Option 2: Act (GitHub Actions locally)

Install [act](https://github.com/nektos/act):

```bash
act push --job apt-distros
act push --job dnf-distros
```

This runs the actual workflow steps in Docker containers locally.

#### Option 3: Manual Script Testing

For quick validation without full CI:

```bash
# Syntax check
bash -n install-docker.sh
bash -n install-docker-airgap.sh

# Dry-run prepare
bash install-docker-airgap.sh --prepare --dry-run

# Run on current OS (requires sudo)
# bash install-docker.sh --yes
```

---

## CI Troubleshooting

### Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| **APT: "Could not find any package matching docker-ce"** | Distro/version/arch mismatch in prepare | Verify `--os`, `--os-version`, `--arch` match Docker CDN structure |
| **DNF: "No matching packages found"** | Distro/version/arch mismatch | Verify RPM URL exists; check Fedora version support |
| **GPG verification fails** | Fingerprint mismatch or gpg not installed | Update `GPG_FINGERPRINT` constant; install gpg in CI job |
| **systemctl: command not found** | Container lacks systemd | CI job mocks systemctl; ensure mock is in place |
| **docker --version fails** | Package not installed (dpkg/rpm error) | Check dpkg/rpm output; verify package manager step |
| **Permission denied on dpkg/rpm** | Not running with sudo | Verify CI job runs as root or uses sudo |

### Debugging CI Failures

1. **Check GitHub Actions logs**: https://github.com/[owner]/docker-installer/actions
2. **Click failed job** → scroll to failing step
3. **Look for error lines** in `Run Docker` or `Install Docker` steps
4. **Re-run job** (button in GitHub UI) after pushing a fix

### Testing a Fix Before Full CI

```bash
# Edit script locally
# Test syntax
bash -n install-docker.sh

# Test in container matching failing distro
docker run -it -v $PWD:/work [failed-image] bash
cd /work
bash install-docker.sh --help

# If OK, commit and push
git add .
git commit -m "fix: [issue]"
git push origin [branch]

# Full CI runs automatically; watch at GitHub Actions tab
```

---

## Deployment Process

### Release Flow

1. **Create PR** with changes to `install-docker.sh` or `install-docker-airgap.sh`
2. **CI validates** all 13 distros (push to PR triggers workflow)
3. **Code review** + approval
4. **Merge to main** (fast-forward or squash merge)
5. **Users download** directly from main branch:
   ```bash
   curl -sSL https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh | bash
   ```

No release artifacts, no tagged versions — scripts are served fresh from main.

### Versioning Strategy

Since scripts are not versioned, communicate breaking changes via:
- Update the README with migration notes
- Add comments in scripts explaining deprecated flags
- Consider backward-compatible flag parsing

### Rollback

If a commit breaks things:

1. **Identify the bad commit** (GitHub Actions log shows which commit failed)
2. **Revert on main**: `git revert [bad-commit]`
3. **CI validates revert** (all 13 distros)
4. **Users automatically get fixed version** on next curl

---

## Performance Notes

### Install Speed

Typical install time (network-dependent):
- **Online mode**: 60–90 seconds (apt/dnf + package download)
- **Airgap prepare**: 120–180 seconds (download 5 packages from CDN)
- **Airgap install**: 30–60 seconds (dpkg/rpm local install, no network)

### Network Usage

- **Online install**: ~300–400 MB (full Docker packages + dependencies)
- **Airgap prepare**: Same ~300–400 MB, but happens once on central machine
- **Airgap install**: 0 MB network (all local)

---

## Maintenance

### Regular Tasks

| Task | Frequency | Owner |
|------|-----------|-------|
| Test on new distro versions | Each Ubuntu/Fedora release (~6 months) | Maintainer |
| Verify Docker GPG fingerprint unchanged | Annually | Maintainer |
| Check for deprecated package manager flags (apt, dnf) | Annually | Maintainer |
| Review GitHub Actions deprecation warnings | On CI failure | Maintainer |

### Adding New Distro Support

1. **Identify package manager** (apt, dnf, zypper, pacman, etc.)
2. **Add branch to `detect_os()` and install functions**
3. **Add CI job** (new matrix entry in `.github/workflows/test-install.yml`)
4. **Test locally** in container for that distro
5. **Merge when all CI jobs pass**

Example (hypothetical zypper/SUSE):

```bash
# In install-docker.sh
case "$os" in
    ubuntu|debian|raspbian) install_docker_apt "$os" ;;
    rhel|centos|fedora)     install_docker_dnf "$os" ;;
    suse|opensuse)          install_docker_zypper "$os" ;;  # New
    *) die "Unsupported OS: $os" ;;
esac

# In install-docker-airgap.sh prepare mode
case "$target_os" in
    ubuntu|debian|raspbian)
        ext="deb"
        base_url="https://download.docker.com/linux/${target_os}/dists/…"
        ;;
    fedora|centos|rhel)
        ext="rpm"
        base_url="https://download.docker.com/linux/${target_os}/…"
        ;;
    suse|opensuse)            # New
        ext="rpm"
        base_url="https://download.docker.com/linux/…"  # Verify CDN structure
        ;;
esac

# In CI workflow (.github/workflows/test-install.yml)
strategy:
  matrix:
    include:
      # ... existing ...
      - { name: "openSUSE Leap 15.6", image: "opensuse/leap:15.6", os: suse, version: "15.6" }
```
