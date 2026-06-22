# Codebase Summary

## File Manifest

### Root Script

| File | LOC | Purpose |
|------|-----|---------|
| `install-docker.sh` | 428 | Unified installer: online mode (default) + airgap mode (`--airgap` flag) with prepare/install subcommands |

### CI & Documentation

| File | Purpose |
|---|---|
| `.github/workflows/test-install.yml` | Automated test matrix: 6 apt distros, 7 dnf distros |
| `README.md` | User-facing quick start guide |
| `docs/project-overview-pdr.md` | Requirements, architecture, roadmap |
| `docs/codebase-summary.md` | This file |
| `docs/code-standards.md` | Bash conventions and contribution guidelines |
| `docs/system-architecture.md` | Technical deep dive: OS detection, package flows |

---

## install-docker.sh — Online Installer

### Constants

```bash
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
```

Global flags: `ASSUME_YES`, `UPGRADE`, `DOCKER_VERSION`

### Functions

| Function | Lines | Role |
|----------|-------|------|
| `log()`, `warn()`, `err()`, `die()` | 14–17 | Color-coded logging to stdout/stderr |
| `cleanup()` | 20–28 | EXIT trap: removes partial apt/dnf config on failure |
| `usage()` | 31–49 | Help message with examples |
| `is_interactive()` | 51–55 | Checks if TTY available or `--yes` flag set |
| `preflight()` | 58–67 | Verifies not root, Docker not already installed (unless `--upgrade`) |
| `detect_os()` | 69–74 | Sources `/etc/os-release`, returns ID (ubuntu, debian, etc.) |
| `verify_gpg_key()` | 76–91 | Validates GPG fingerprint using `gpg` CLI; warns if gpg unavailable |
| `build_package_list()` | 94–104 | Constructs apt version string: `pkg=VERSION` |
| `build_package_list_dnf()` | 106–116 | Constructs dnf version string: `pkg-VERSION` |
| `install_docker_apt()` | 119–154 | apt-get flow: adds key, configures DEB822 or legacy APT source, installs |
| `install_docker_dnf()` | 156–179 | dnf flow: adds repo, manual GPG prompt (interactive), installs |
| `main()` | 182–215 | Parses args, calls preflight/detect_os, routes to apt/dnf installer, enables services, configures docker group |

### Entry Point

- `main "$@"` at line 217

### Key Flows

**Online Install (APT)**
1. `preflight()` → check no Docker, verify sudo/root
2. `detect_os()` → read ID from /etc/os-release
3. `install_docker_apt()`
   - Install prerequisites (ca-certificates, curl, gnupg)
   - Download Docker GPG key to `/etc/apt/keyrings/docker.asc`
   - `verify_gpg_key()` → validate fingerprint
   - Configure `/etc/apt/sources.list.d/docker.sources` or `.list` (Raspbian compat)
   - `apt-get install` with optional `--version`
4. `systemctl enable --now docker containerd`
5. Add current user to docker group (non-root)

**Online Install (DNF)**
1. Same preflight & detect_os
2. `install_docker_dnf()`
   - Install dnf-plugins-core
   - Add Docker repo via `dnf config-manager`
   - Manual GPG fingerprint prompt (if interactive)
   - `dnf install` with optional `--version`
3. Enable services, configure docker group

### Exit Codes

- `0` — Success
- `1` — Any error (die), or cleanup trap on non-zero exit
- $? captured in cleanup trap to differentiate clean vs. failed exit

---

## install-docker.sh — Airgap Mode Functions

### Airgap-Specific Functions

| Function | Role |
|----------|------|
| `run_online()` | Routes online installation (default behavior) |
| `run_airgap()` | Detects airgap subcommand and routes to prepare or install |
| `do_prepare()` | Download packages from Docker repos, generate checksums |
| `do_install()` | Verify checksums, auto-detect deb/rpm, install packages |

### do_prepare() Workflow (Airgap Mode)

**Input**: `--airgap --prepare [--os <os>] [--os-version <v>] [--arch <a>] [--dry-run]`

1. **Auto-detect** (if missing):
   - Read `/etc/os-release` for ID, UBUNTU_CODENAME, VERSION_CODENAME, or VERSION_ID
   - Fallback to `uname -m` for architecture
2. **Validate**: Ensure OS and version provided or auto-detected
3. **Architecture mapping**:
   - `x86_64` ↔ `amd64` (dpkg) vs `x86_64` (rpm)
   - `aarch64` ↔ `arm64` (dpkg) vs `aarch64` (rpm)
   - `armv[67]*` → `armhf` (dpkg, Raspberry Pi)
4. **Construct base URL**:
   - apt: `https://download.docker.com/linux/{OS}/dists/{VERSION}/pool/stable/{ARCH}/`
   - dnf: `https://download.docker.com/linux/{OS}/{VERSION}/{ARCH}/stable/Packages/`
5. **Create output directory**: `docker-{OS}-{VERSION}-{ARCH}-{YYYYMMDD}`
6. **Fetch index HTML**, parse package links using `grep -oE` regex
7. **Download each package** or log [DRY RUN] if `--dry-run`
8. **Generate SHA256 checksums**: `sha256sum -- *.deb` or `*.rpm` → `checksums.sha256`

### do_install() Workflow (Airgap Mode)

**Input**: `install-docker.sh --airgap <package-dir>`

1. **Verify checksums** (if `checksums.sha256` exists):
   - `cd $PKG_DIR && sha256sum -c checksums.sha256`
   - Die if any mismatch
2. **Detect package type**:
   - Count `*.deb` and `*.rpm` in directory
   - If deb count > 0: use dpkg
   - Else if rpm count > 0: use rpm
   - Else die (no packages found)
3. **Install packages**:
   - **dpkg path**: `sudo dpkg -i *.deb`; on error, `sudo apt-get install -f -y` (auto-fix deps)
   - **rpm path**: `sudo dnf install -y *.rpm` when dnf is present (resolves deps against installed packages); falls back to `sudo rpm -Uvh --force *.rpm` otherwise
4. **Enable services**: `sudo systemctl enable --now docker containerd`
5. **Configure docker group** (non-root)

### Entry Point & Routing

- `main "$@"` pre-scans for `--airgap` flag early
- If `--airgap` found: routes to `run_airgap()` which dispatches to `do_prepare()` or `do_install()`
- If no `--airgap`: routes to `run_online()` for standard installation

### Key Design Decisions

- **No embedded checksums**: Generated fresh on prepare to avoid stale digest issues
- **Force flag for rpm**: `--force` allows reinstalling/upgrading without explicit uninstall
- **dpkg auto-fix**: APT's `-f` flag resolves missing dependencies post-install
- **Exit on first checksum fail**: Security-first: corrupted == untrusted
- **set -euo pipefail disabled**: Online path relies on explicit `||` handlers; airgap path uses explicit error checks

---

## CI Test Matrix

### test-install.yml Configuration

**APT matrix** (6 jobs): Ubuntu 22.04/24.04/26.04, Debian 11/12/13

**DNF matrix** (7 jobs): RHEL 8/9/10, CentOS Stream 9/10, Fedora 43/44

**Total: 13 distros, 26 jobs** (apt install + dry-run prepare per distro)

### Test Steps

1. Install curl, sudo (base image may lack them)
2. Download script from current commit SHA
3. Mock systemctl (return 0) so services "enable" in container
4. Run `install-docker.sh --yes`
5. Verify `docker --version` and `docker compose version`
6. Run `install-docker.sh --airgap --prepare --dry-run` for architecture verification

### Why Mock systemctl?

Container images lack systemd; mocking systemctl prevents service enable failures while still validating package installation logic.

---

## Data Flow Diagram

```
Online (default):
  [User curl] → install-docker.sh --yes
                    ↓
           detect_os → {apt, dnf}
                    ↓
           fetch Docker key/repo
                    ↓
           verify GPG (apt) or manual prompt (dnf)
                    ↓
           apt-get/dnf install
                    ↓
           systemctl enable

Airgap Prepare:
  [User on internet machine] → install-docker.sh --airgap --prepare
                                    ↓
                          auto-detect or explicit OS/arch
                                    ↓
                          fetch Docker CDN index
                                    ↓
                          grep & download *.deb or *.rpm
                                    ↓
                          sha256sum → checksums.sha256
                                    ↓
                          [Transfer dir to offline machine]

Airgap Install:
  [User on offline machine] → install-docker.sh --airgap ./docker-*-*-*
                                    ↓
                          verify checksums.sha256
                                    ↓
                          auto-detect deb/rpm
                                    ↓
                          dpkg/rpm install
                                    ↓
                          systemctl enable
```

---

## Code Style Notes

- **Readonly variables**: Uppercase, declared at top
- **Local scope**: Functions use `local -n` for nameref (build_package_list)
- **Traps**: EXIT cleanup prevents orphaned config
- **Error handling**: `set -euo pipefail` in airgap; online script omits (more lenient on network)
- **Comments**: Inline `# ──` dividers for sections, minimal redundancy
- **Color logging**: Red [ERROR], Yellow [WARN], Green [INFO]

---

## Testing Checklist

- [ ] All 13 distros pass online install (`install-docker.sh --yes`)
- [ ] All 13 distros pass airgap dry-run prepare (`install-docker.sh --airgap --prepare --dry-run`)
- [ ] All 13 distros pass airgap real prepare + install (new smoke test)
- [ ] GPG fingerprint verified (apt only, requires gpg CLI)
- [ ] Checksum verification catches corrupted packages
- [ ] Cleanup trap removes partial config on failure
- [ ] Non-root user added to docker group
- [ ] systemctl enable works (or gracefully degrades in containers)
- [ ] `--upgrade` flag allows re-running on existing Docker
- [ ] `--version` pins specific Docker release
- [ ] `--airgap --prepare --dry-run` lists files without downloading
