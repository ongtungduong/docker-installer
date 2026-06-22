# System Architecture

## High-Level Design

The Docker Installer uses a **single-script, multi-mode architecture** to handle online and offline deployment scenarios with shared logging, error handling, and setup routines while maintaining strict separation between modes.

```
┌─────────────────────────────────────────────────────────────────┐
│                     User Workflow                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Online (default):         Offline (--airgap):                │
│  ┌──────────────────┐      ┌──────────────────┐               │
│  │ install-docker.sh│      │ install-docker.sh│ --airgap      │
│  │                  │      │                  │ --prepare     │
│  │ [no flag]        │      │                  │ ──────────>   │
│  └──────────────────┘      └──────────────────┘ [Download]    │
│    ↓                          ↓ [Copy dir]                     │
│  [apt/dnf repo]          install-docker.sh --airgap <dir>     │
│  [Install + enable]         [Verify + install]                │
└─────────────────────────────────────────────────────────────────┘
```

## install-docker.sh — Online Installer

### Flow

```
main()
  ├─ Parse flags (--yes, --version, --upgrade)
  ├─ preflight()
  │   ├─ Check if Docker already installed
  │   ├─ Verify sudo/root privileges
  │   └─ Die if conflicts and not --upgrade
  │
  ├─ detect_os()
  │   └─ Source /etc/os-release, return $ID
  │
  └─ OS branching:
      ├─ [ubuntu|debian|raspbian] → install_docker_apt()
      │   ├─ apt-get update && install ca-certificates, curl, gnupg
      │   ├─ Download GPG key from Docker CDN
      │   ├─ verify_gpg_key() — fingerprint check (apt only)
      │   ├─ Add repo (DEB822 format for Ubuntu/Debian, legacy for Raspbian)
      │   ├─ build_package_list() — handle --version spacing
      │   └─ apt-get install docker packages
      │
      └─ [rhel|centos|fedora] → install_docker_dnf()
          ├─ dnf install dnf-plugins-core
          ├─ dnf config-manager add/addrepo (Fedora vs RHEL differ)
          ├─ Manual GPG prompt (interactive only)
          ├─ build_package_list_dnf() — handle --version dash format
          └─ dnf install docker packages

  [All paths converge]
  ├─ systemctl enable --now docker containerd
  ├─ Add current user to docker group (non-root mode)
  └─ Print success message
```

### Key Design Decisions

**Nameref for package list** — Uses bash `local -n` to pass arrays by reference:
```bash
build_package_list pkgs    # pkgs is a nameref to the caller's variable
```
Avoids subshells, preserves array state.

**Cleanup trap** — Runs on exit code ≠ 0:
```bash
trap cleanup EXIT
cleanup() {
    if [[ $exit_code -ne 0 ]]; then
        # Remove partial config files
        rm -f /etc/apt/sources.list.d/docker.* /etc/apt/keyrings/docker.asc
    fi
}
```
Ensures failed installs don't leave broken repositories.

**Two package list builders** — `build_package_list()` vs `build_package_list_dnf()`:
- APT format: `docker-ce=5:27.5.1-1~ubuntu.24.04~noble`
- DNF format: `docker-ce-5.27.5.1-1`

**GPG verification (apt-only)** — Uses `gpg --with-fingerprint --with-colons`:
```bash
actual_fp=$(gpg --with-fingerprint ... | awk -F: '/^fpr:/{print $10; exit}')
[[ "$actual_fp" == "$expected_fp" ]] || die "Fingerprint mismatch"
```
DNF path defers verification to user manual prompt.

---

## install-docker.sh Airgap Mode — Offline Installer

### Airgap Mode Routing

```
main(args)
  ├─ Pre-scan for --airgap flag
  │   ├─ If --airgap present → run_airgap()
  │   │   ├─ Check for --prepare → do_prepare(opts)
  │   │   ├─ Check for -h/--help → usage
  │   │   └─ $path (directory) → do_install($path)
  │   └─ Else → run_online() [default]
```

### Prepare Mode (do_prepare)

**Purpose**: Download packages to a timestamped directory on an internet-connected machine.

**CLI**: `install-docker.sh --airgap --prepare [--os <os>] [--os-version <v>] [--arch <a>] [--dry-run]`

```
do_prepare(--os, --os-version, --arch, --dry-run)
  │
  ├─ Parse options
  │
  ├─ Auto-detect (if OS/version not provided)
  │   ├─ Source /etc/os-release
  │   └─ Map OS/version using smart defaults
  │
  ├─ Architecture normalization
  │   ├─ x86_64 ↔ amd64 (dpkg format)
  │   ├─ aarch64 ↔ arm64 (dpkg format)
  │   └─ armv[67]* → armhf (dpkg format)
  │   └─ rpm_arch = amd64/aarch64, dpkg_arch = amd64/arm64/armhf
  │
  ├─ Build base_url (varies by OS)
  │   ├─ APT: https://download.docker.com/linux/{os}/dists/{version}/pool/stable/{dpkg_arch}/
  │   └─ DNF: https://download.docker.com/linux/{os}/{version}/{rpm_arch}/stable/Packages/
  │
  ├─ Create dest_dir = docker-{os}-{version}-{arch}-{YYYYMMDD}
  │
  ├─ Fetch index HTML from base_url
  │
  ├─ For each package in DOCKER_PACKAGES array:
  │   ├─ Grep index for latest matching file (sorted by version)
  │   ├─ If --dry-run: print what would download
  │   └─ Else: curl package and save to dest_dir
  │
  └─ Generate checksums
      ├─ cd dest_dir && sha256sum *.{deb|rpm} > checksums.sha256
      └─ Print completion summary
```

**Example outputs**:
- APT: `docker-ubuntu-noble-amd64-20260320/` with `*.deb` files
- DNF: `docker-fedora-44-x86_64-20260320/` with `*.rpm` files

### Install Mode (do_install)

**Purpose**: Install Docker from pre-downloaded packages (offline).

**CLI**: `install-docker.sh --airgap <package-dir>`

```
do_install($pkg_dir)
  │
  ├─ Verify directory exists
  │
  ├─ Checksum validation (if checksums.sha256 present)
  │   ├─ cd pkg_dir && sha256sum -c checksums.sha256
  │   └─ Die if any mismatch (prevents corrupted/tampered installs)
  │
  ├─ Detect package type
  │   ├─ Count .deb files
  │   └─ Count .rpm files
  │
  ├─ Install (pick one)
  │   │
  │   ├─ .deb path:
  │   │   ├─ sudo dpkg -i $pkg_dir/*.deb
  │   │   └─ Fallback: sudo apt-get install -f -y (fix broken deps)
  │   │
  │   └─ .rpm path:
  │       ├─ dnf present: sudo dnf install -y $pkg_dir/*.rpm (resolves deps)
  │       └─ Fallback:    sudo rpm -Uvh --force $pkg_dir/*.rpm
  │
  ├─ systemctl enable --now docker containerd
  │
  ├─ Add current user to docker group (non-root)
  │
  └─ Print success message
```

### Key Design Decisions

**Timestamped directories** — Allows parallel prepare runs on same machine:
```bash
dest_dir="docker-${target_os}-${target_version}-${dpkg_arch}-$(date +%Y%m%d)"
```

**Version sort for latest package** — Finds newest minor/patch release:
```bash
sort -V | tail -n 1
```
Ensures `docker-ce_27.5.1_amd64.deb` is picked over `27.4.0`, etc.

**Dual architecture mapping** — Normalizes distro-specific arch strings:
```
x86_64 ↔ amd64       (for dpkg)
aarch64 ↔ arm64      (for dpkg)
armv6/armv7 → armhf  (for dpkg)
```
Allows users on macOS to prepare packages for ARM servers.

**SHA256 checksum workflow**:
1. Prepare computes: `sha256sum *.deb > checksums.sha256`
2. Install verifies: `sha256sum -c checksums.sha256` (must pass 100%)
3. Dies on mismatch (corruption, tampering, incomplete download all caught)

---

## Shared Utilities

### Logging

```bash
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }
```

- **Colored output**: green=info, yellow=warn, red=error
- **stderr routing**: warn/err → stderr; log → stdout
- **Exit convention**: die() → exit 1

### Constants

```bash
readonly DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

readonly GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
```

---

## Data Flow: Install Path (Apt Example)

```
User: bash install-docker.sh --yes

[1] Parse: ASSUME_YES=true
    [2] Preflight: sudo check, Docker conflict check
        [3] Detect: read /etc/os-release → "ubuntu"
            [4] Branch: install_docker_apt("ubuntu")
                [5] apt-get update && install curl, ca-certificates, gnupg
                    [6] Download GPG key → /etc/apt/keyrings/docker.asc
                        [7] verify_gpg_key() → fingerprint check
                            [8] Add DEB822 repo → /etc/apt/sources.list.d/docker.sources
                                [9] build_package_list() → ["docker-ce", "docker-ce-cli", "containerd.io", ...]
                                    [10] apt-get install -y $packages
                                        [11] systemctl enable --now docker containerd
                                            [12] groupadd -f docker && usermod -aG docker $USER
                                                [13] Print success + logout reminder

Exit: 0 (cleanup trap skips on success)
```

---

## CI Test Matrix

**File**: `.github/workflows/test-install.yml`

| Stage | Count | Coverage |
|-------|-------|----------|
| **apt-distros** (online install) | 6 | Ubuntu 22.04, 24.04, 26.04 · Debian 11, 12, 13 |
| **dnf-distros** (online install) | 7 | RHEL 8, 9, 10 · CentOS Stream 9, 10 · Fedora 43, 44 |
| **airgap-distros** (real prepare + offline install) | 13 | every supported distro |
| **Total** | 26 | 13 online + 13 airgap job runs |

**Online jobs** (`apt-distros` + `dnf-distros`, 13 distros):
1. Install curl + sudo
2. Download script from current commit
3. (RHEL 10 only) enable CentOS Stream 10 base repos so UBI can resolve Docker's runtime deps
4. Mock systemctl (containers don't have it)
5. Run `install-docker.sh --yes` (online mode)
6. Verify `docker --version` and `docker compose version`

**Airgap jobs** (`airgap-distros`, all 13 distros, real end-to-end in a fresh container):
1. Install curl + sudo
2. Download script from current commit
3. (RHEL 10 only) enable CentOS Stream 10 base repos
4. Run full prepare: `install-docker.sh --airgap --prepare --os … --os-version … --arch …`
5. Run full offline install: `install-docker.sh --airgap ./docker-*-*-*`
6. Verify `docker --version` and `docker compose version`

**Fail-fast**: false (all jobs run even if one fails, to expose all distro issues)
