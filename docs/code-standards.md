# Code Standards & Contribution Guide

## Bash Conventions

All scripts follow a consistent Bash style optimized for readability, portability, and safety.

### Strict Mode & Error Handling

**install-docker.sh**:
```bash
# set -euo pipefail    # Disabled: allows non-interactive recovery flows
```
- **Why commented out**: Online path relies on explicit `||` handlers; airgap path uses explicit error checks for separation
- **Trade-off**: Requires explicit error handling in critical paths
- **Benefit**: Clean mode separation and custom recovery flows

**Recommendation for new code**: Use explicit error handling with `||` and `if` checks unless `set -euo pipefail` is globally appropriate.

### Variable Management

**Readonly constants** — prevent accidental mutation:
```bash
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
```

**Global flags** — cluster top-level, clearly named:
```bash
ASSUME_YES=false
UPGRADE=false
DOCKER_VERSION=""
```

**Local variables** — always use `local` in functions:
```bash
install_docker_apt() {
    local os="$1"
    local pkgs=()
    # ...
}
```

**Nameref for pass-by-reference** — avoid subshells:
```bash
build_package_list() {
    local -n _pkgs=$1                    # _pkgs is a nameref to caller's array
    if [[ -n "$DOCKER_VERSION" ]]; then
        _pkgs=("${pkg}=${DOCKER_VERSION}")
    fi
}

# Call:
pkgs=()
build_package_list pkgs                 # pkgs updated in place, not subshell
```

**Command substitution** — prefer `$()` over backticks:
```bash
os=$(detect_os)
actual_fp=$(gpg --with-fingerprint ... | awk -F: '/^fpr:/{print $10; exit}')
```

### Quoting & Expansion

**Quote all variables** — prevent word splitting:
```bash
die "$@"                                 # Preserves argument list
sudo install -m 0755 -d "$1"            # Path with spaces
```

**Quote arrays in loops** — preserve elements:
```bash
for pkg in "${DOCKER_PACKAGES[@]}"; do  # Not $DOCKER_PACKAGES
    _pkgs+=("${pkg}=${DOCKER_VERSION}")
done
```

**Prefer string literals over variable expansion** when static:
```bash
printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"    # Color codes as literals
```

### Conditionals

**Use `[[...]]` for portability** over `[...]`:
```bash
[[ -f /etc/os-release ]] || die "File not found"
[[ "$actual_fp" == "$expected_fp" ]] || die "Mismatch"
[[ $# -lt 1 ]] && die "No args"
```

**Return codes matter** — explicit or via exit status:
```bash
is_interactive() {
    [[ "$ASSUME_YES" == "true" ]] && return 1  # -y means non-interactive
    [[ -t 0 ]] && return 0                      # TTY attached
    return 1
}

# Usage:
if is_interactive; then
    read -rp "Confirm? " ans
fi
```

### Functions

**Function naming** — snake_case, prefixed by action:
```bash
detect_os()
install_docker_apt()
verify_gpg_key()
build_package_list()
do_prepare()
do_install()
```

**Function documentation** — comments above definition:
```bash
# ── Helpers ──────────────────────────────────────────────────────────
# Install Docker using apt (Debian-based distros)
install_docker_apt() {
    local os="$1"
    ...
}
```

**Early return pattern** — exit on validation failures:
```bash
preflight() {
    if command -v docker >/dev/null 2>&1; then
        if [[ "$UPGRADE" == "true" ]]; then
            warn "Docker is already installed. Upgrading…"
        else
            die "Docker is already installed. Uninstall first or use --upgrade."
        fi
    fi
    [[ $EUID -ne 0 ]] && ! sudo -v &>/dev/null && die "Need root or sudo"
}
```

### Logging

**Color-coded output** — consistent across both scripts:
```bash
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }
```

**Stderr routing** — warnings/errors go to stderr:
```bash
warn "This is a warning" >&2
die "This is fatal"     # >&2 redundant in die()
```

**Progress messages** — use `log()`:
```bash
log "Detecting OS…"
log "Installing prerequisites…"
log "Downloading $file…"
```

### Trap & Cleanup

**Exit trap for cleanup** — runs on exit regardless of success/failure:
```bash
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warn "Installation failed (exit code: $exit_code). Cleaning up…"
        # Remove partial configuration
        sudo rm -f /etc/apt/sources.list.d/docker.* 2>/dev/null || true
    fi
}
trap cleanup EXIT
```

**Why `2>/dev/null || true`** — suppress errors on systems where files don't exist, allow trap to continue.

### Portability

**Avoid bashisms in POSIX-critical sections**:
```bash
# Good: POSIX-compatible
source /etc/os-release            # More portable than .

# Acceptable (bash-only):
local -n nameref                  # Bash 4.3+
[[ ... ]]                         # Bash 3.0+
```

**Shebang**: Always `#!/bin/bash` (requires Bash 3.0+, not POSIX sh).

**Test on at least** the oldest supported distro (Ubuntu 22.04 → Bash 5.1).

---

## Code Organization

### File Structure

```
install-docker.sh
  1. Shebang + set options
  2. ── Constants
  3. ── Global flags
  4. ── Logging helpers
  5. ── Cleanup trap
  6. ── usage() function
  7. ── Utility functions (is_interactive, preflight, detect_os, etc.)
  8. ── OS-specific installers (install_docker_apt, install_docker_dnf)
  9. ── main() entry point
 10. main "$@"   # Script invocation
```

### Section Markers

Use ASCII dividers for readability:
```bash
# ── Constants ────────────────────────────────────────────────────────
# ── Logging helpers ──────────────────────────────────────────────────
# ── Prepare: download packages ──────────────────────────────────────
# ── Main ─────────────────────────────────────────────────────────────
```

Helps navigate 200-line scripts without scrolling infinitely.

---

## Testing & Validation

### Local Testing

**Before submitting PR**:

1. **Syntax check**:
   ```bash
   bash -n install-docker.sh
   ```

2. **Manual test on supported OS**:
   ```bash
   # Online
   bash install-docker.sh --help
   bash install-docker.sh --version 5:27.5.1-1
   
   # Airgap prepare (dry-run)
   bash install-docker.sh --airgap --prepare --dry-run
   
   # Airgap install (with prepared directory)
   bash install-docker.sh --airgap ./docker-ubuntu-noble-amd64-*
   ```

3. **ShellCheck (optional but recommended)**:
   ```bash
   shellcheck install-docker.sh
   ```

### CI Testing

CI runs all 13 distros via `.github/workflows/test-install.yml`. Before pushing:

- Ensure no breaking changes to flag parsing
- No new OS detection logic without testing logic for fallback
- Checksum generation/verification must be idempotent

---

## Contribution Guidelines

### Submitting Changes

1. **Fork the repository** and create a feature branch
2. **Edit script** following conventions above
3. **Syntax check** locally: `bash -n install-docker.sh`
4. **Commit with conventional message**:
   ```
   feat(install): add --config flag for daemon.json
   fix(airgap): handle symlinks in package dir
   docs: clarify airgap workflow for arm64
   ```
5. **Push and open PR** — CI matrix will validate all 13 distros + airgap smoke tests
6. **Wait for all jobs to pass** before merge

### Code Review Focus

Reviewers check for:

| Aspect | Criteria |
|--------|----------|
| **Safety** | Error paths reach cleanup trap; die() vs warn() used correctly |
| **Portability** | Changes tested on ≥2 distros (apt + dnf); OS detection is robust |
| **Size** | Scripts stay <250 LOC; no feature bloat |
| **Compatibility** | Flags are additive (backward compatible); no OS support removal |
| **Clarity** | Variable names clear; comments explain *why*, not *what* |

### Avoiding Common Pitfalls

| Mistake | How to Catch |
|---------|---|
| **Unquoted variables** | `shellcheck -x` |
| **Subshells in loops** | Trace variable mutations; use nameref |
| **Missing `local`** | `shellcheck` warns (via grep for globals) |
| **Hardcoded paths** | Search for `/etc/apt`, `/etc/yum` — should be `sudo` prefixed |
| **No cleanup on failure** | Review trap and exit codes in online path |
| **Different arch logic for deb vs rpm** | Compare `dpkg_arch` vs `rpm_arch` handling in `do_prepare()` |
| **Airgap/online logic bleed** | Ensure `run_online()` and `run_airgap()` don't share state |

---

## Future Refactoring Considerations

### Potential Improvements (defer unless needed)

1. **Extract OS detection to a function map**:
   ```bash
   declare -A OS_INSTALLERS=(
       [ubuntu]="install_docker_apt"
       [rhel]="install_docker_dnf"
   )
   ```
   Trade-off: adds indirection, doesn't reduce LOC significantly.

2. **Unify package list builders** (apt vs dnf differ only in separator):
   ```bash
   build_package_list() {
       local sep="$1" fmt="$2"   # "=" vs "-" for apt vs dnf
   }
   ```
   Trade-off: harder to follow; current dual functions are clearer.

3. **Airgap mode auto-detection** (can we infer OS from package dir name?):
   ```bash
   docker-ubuntu-noble-amd64-20260320  # Parse and auto-detect
   ```
   Trade-off: fragile parsing, but could improve UX.

Only refactor when adding new behavior, not for abstract "cleanliness."

---

## Documentation in Code

### Comments Style

**Explain intent, not obvious behavior**:
```bash
# Good
# Debian/Ubuntu use space-separated format; RHEL/Fedora use dash
if [[ -n "$DOCKER_VERSION" ]]; then
    # Build version-pinned package list
```

**Bad**
```bash
# Loop through packages and add version
for pkg in "${DOCKER_PACKAGES[@]}"; do
```

### Function Headers

Document public/shared functions:
```bash
# ── Helpers ──────────────────────────────────────────────────────────
# detect_os: Print ID field from /etc/os-release
# Outputs: "ubuntu", "rhel", etc., or dies if /etc/os-release missing
detect_os() {
    ...
}
```

## Summary

**Core principles**:
- **Clarity over brevity** — readable bash beats golfed bash
- **Fail-safe defaults** — cleanup trap, readonly constants, local variables
- **Explicit error handling** — die() for fatal, warn() for recoverable
- **Tested paths** — all 13 distros, 2 modes, covered in CI
- **No surprises** — consistent formatting, predictable flow

Contributions that respect these principles will integrate smoothly.
