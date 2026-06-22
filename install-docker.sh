#!/bin/bash
# Unified Docker installer for Linux.
#   Online (default):  install Docker Engine + Compose from official repos.
#   Airgap (--airgap): --prepare downloads packages on an online host;
#                      passing a package directory installs them offline.
#
# Note: errexit (set -e) is intentionally left OFF. The online flow relies on
# explicit `|| die` handling, and the airgap functions use explicit error
# checks (`|| die`, `failed=$((failed + 1))`), so neither path depends on it.

# ── Constants ────────────────────────────────────────────────────────
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"

# ── Global flags (online mode) ───────────────────────────────────────
ASSUME_YES=false
UPGRADE=false
DOCKER_VERSION=""

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# ── Shared: enable services & configure non-root access ──────────────
enable_and_group() {
    log "Enabling Docker & containerd on boot…"
    sudo systemctl enable --now docker containerd

    if [[ $EUID -ne 0 ]]; then
        log "Configuring Docker for non-root usage (adding to 'docker' group)…"
        sudo groupadd -f docker
        sudo usermod -aG docker "$USER"
        warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
    fi
}

# ── Cleanup on failure (online mode only) ────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warn "Installation failed (exit code: $exit_code). Cleaning up partial configuration…"
        sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        sudo rm -f /etc/apt/keyrings/docker.asc 2>/dev/null || true
        sudo rm -f /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
    fi
}

usage() {
    cat <<EOF
Usage:
  $0 [OPTIONS]                          Install Docker online (default).
  $0 --airgap --prepare [OPTIONS]       Download Docker packages for offline use.
  $0 --airgap <package-directory>       Install Docker offline from downloaded packages.

Online options:
  -y, --yes          Non-interactive mode (skip confirmation prompts).
  --version <ver>    Install a specific Docker version (e.g., 5:27.5.1-1).
  --upgrade          Upgrade Docker if already installed (instead of aborting).

Airgap prepare options (with --airgap --prepare):
  --os <os>          Target OS (ubuntu, debian, raspbian, fedora, centos, rhel).
  --os-version <ver> Target OS version/codename (e.g., noble for Ubuntu 24.04, 9 for RHEL 9).
  --arch <arch>      Target architecture (amd64, arm64, x86_64, aarch64). Default: host arch.
  --dry-run          Show what would be downloaded without actually downloading.

Common:
  -h, --help         Show this help message.

Examples:
  $0 --yes
  $0 --version 5:27.5.1-1~ubuntu.24.04~noble
  $0 --upgrade
  $0 --airgap --prepare --os ubuntu --os-version noble --arch amd64
  $0 --airgap ./docker-ubuntu-noble-amd64-20260320
EOF
    exit 0
}

is_interactive() {
    [[ "$ASSUME_YES" == "true" ]] && return 1
    [[ -t 0 ]] && return 0
    return 1
}

# ── Online helpers ───────────────────────────────────────────────────
preflight() {
    if command -v docker >/dev/null 2>&1; then
        if [[ "$UPGRADE" == "true" ]]; then
            warn "Docker is already installed ($(docker --version)). Upgrading…"
        else
            die "Docker is already installed ($(docker --version)). Uninstall it first or use --upgrade."
        fi
    fi
    [[ $EUID -ne 0 ]] && ! sudo -v &>/dev/null && die "This script requires root or sudo privileges."
}

detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found. Unsupported system."
    # shellcheck source=/dev/null
    source /etc/os-release
    printf '%s' "${ID:-}"
}

verify_gpg_key() {
    local keyfile="$1"
    if command -v gpg >/dev/null 2>&1; then
        log "Verifying Docker GPG key fingerprint…"
        local actual_fp
        actual_fp=$(gpg --with-fingerprint --with-colons "$keyfile" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
        local expected_fp="${GPG_FINGERPRINT// /}"
        if [[ "$actual_fp" == "$expected_fp" ]]; then
            log "GPG fingerprint verified: $GPG_FINGERPRINT"
        else
            die "GPG fingerprint mismatch! Expected: $GPG_FINGERPRINT, Got: $actual_fp"
        fi
    else
        warn "gpg not found — skipping GPG fingerprint verification."
    fi
}

# ── Build versioned package list ─────────────────────────────────────
build_package_list() {
    # shellcheck disable=SC2178  # nameref to a caller array, not a string
    local -n _pkgs=$1
    if [[ -n "$DOCKER_VERSION" ]]; then
        _pkgs=()
        for pkg in "${DOCKER_PACKAGES[@]}"; do
            _pkgs+=("${pkg}=${DOCKER_VERSION}")
        done
    else
        _pkgs=("${DOCKER_PACKAGES[@]}")
    fi
}

build_package_list_dnf() {
    # shellcheck disable=SC2178  # nameref to a caller array, not a string
    local -n _pkgs=$1
    if [[ -n "$DOCKER_VERSION" ]]; then
        _pkgs=()
        for pkg in "${DOCKER_PACKAGES[@]}"; do
            _pkgs+=("${pkg}-${DOCKER_VERSION}")
        done
    else
        _pkgs=("${DOCKER_PACKAGES[@]}")
    fi
}

# ── Online installers ────────────────────────────────────────────────
install_docker_apt() {
    local os="$1"
    log "Installing prerequisites…"
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg

    log "Adding Docker GPG key…"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/${os}/gpg" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    verify_gpg_key /etc/apt/keyrings/docker.asc

    log "Adding Docker APT repository…"
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "$os" == "raspbian" ]]; then
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
            "$(dpkg --print-architecture)" "$os" "${VERSION_CODENAME:-}" | \
            sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    else
        sudo tee /etc/apt/sources.list.d/docker.sources <<EOF >/dev/null
Types: deb
URIs: https://download.docker.com/linux/${os}
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    fi

    log "Installing Docker Engine…"
    sudo apt-get update -y
    local pkgs=()
    build_package_list pkgs
    sudo apt-get install -y "${pkgs[@]}" || die "Failed to install Docker packages."
}

install_docker_dnf() {
    local os="$1"
    log "Installing dnf-plugins-core…"
    sudo dnf install -y dnf-plugins-core

    local repo_url="https://download.docker.com/linux/${os}/docker-ce.repo"
    if [[ "$os" == "fedora" ]]; then
        sudo dnf config-manager addrepo --from-repofile "$repo_url"
    else
        sudo dnf config-manager --add-repo "$repo_url"
    fi

    if is_interactive; then
        warn "Verify GPG fingerprint matches: $GPG_FINGERPRINT"
        read -rp "Press Enter to continue (Ctrl-C to abort)… "
    else
        log "Non-interactive mode — skipping GPG prompt."
    fi

    log "Installing Docker Engine…"
    local pkgs=()
    build_package_list_dnf pkgs
    sudo dnf install -y "${pkgs[@]}" || die "Failed to install Docker packages."
}

# ── Online mode entry point ──────────────────────────────────────────
run_online() {
    trap cleanup EXIT

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) ASSUME_YES=true; shift ;;
            --version) DOCKER_VERSION="$2"; shift 2 ;;
            --upgrade) UPGRADE=true; shift ;;
            -h|--help) usage ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done

    preflight
    local os
    os=$(detect_os)
    log "Detected OS: $os"

    case "$os" in
        ubuntu|debian|raspbian) install_docker_apt "$os" ;;
        rhel|centos|fedora)     install_docker_dnf "$os" ;;
        *) die "Unsupported operating system: $os" ;;
    esac

    enable_and_group

    log "Docker installed successfully!"
}

# ── Airgap: download packages ────────────────────────────────────────
do_prepare() {
    local target_os="" target_version="" target_arch="" dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os) target_os="$2"; shift 2 ;;
            --os-version) target_version="$2"; shift 2 ;;
            --arch) target_arch="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    # Auto-detect OS and Version if missing
    if [[ -z "$target_os" || -z "$target_version" ]]; then
        if [[ -f /etc/os-release ]]; then
            log "Auto-detecting OS..."
            # shellcheck source=/dev/null
            . /etc/os-release
            target_os="${target_os:-${ID:-}}"
            if [[ -z "$target_version" ]]; then
                case "$target_os" in
                    ubuntu|debian|raspbian) target_version="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
                    fedora|centos|rhel) target_version="${VERSION_ID%%.*}" ;;
                esac
            fi
        fi
    fi

    # Auto-detect Architecture if missing
    target_arch="${target_arch:-$(uname -m)}"

    if [[ -z "$target_os" || -z "$target_version" ]]; then
        err "Could not auto-detect OS/version. Provide --os and --os-version manually."
        echo ""
        usage
    fi

    log "Target OS: $target_os | Version: $target_version | Arch: $target_arch"

    command -v curl >/dev/null || die "curl is required. Please install it first."

    # Map architecture formats
    local dpkg_arch="$target_arch" rpm_arch="$target_arch"
    case "$target_arch" in
        x86_64) dpkg_arch="amd64" ;;
        amd64)  rpm_arch="x86_64" ;;
        aarch64) dpkg_arch="arm64" ;;
        arm64)  rpm_arch="aarch64" ;;
        armv[67]*) dpkg_arch="armhf" ;;
    esac

    local base_url ext
    case "$target_os" in
        ubuntu|debian|raspbian)
            ext="deb"
            base_url="https://download.docker.com/linux/${target_os}/dists/${target_version}/pool/stable/${dpkg_arch}/"
            ;;
        fedora|centos|rhel)
            ext="rpm"
            base_url="https://download.docker.com/linux/${target_os}/${target_version}/${rpm_arch}/stable/Packages/"
            ;;
        *) die "Unsupported operating system: $target_os" ;;
    esac

    local dest_dir
    dest_dir="docker-${target_os}-${target_version}-${dpkg_arch}-$(date +%Y%m%d)"
    log "Preparing airgap files in ./${dest_dir}"
    mkdir -p "$dest_dir"

    log "Fetching index from $base_url"
    local index_html
    index_html=$(curl -fsSL "$base_url") || die "Failed to fetch index from $base_url. Check OS/Version/Arch."

    local failed=0
    for pkg in "${DOCKER_PACKAGES[@]}"; do
        log "Finding latest package for: $pkg"
        local file_pattern="href=\"${pkg}_[^\"]+\.deb\""
        [[ "$ext" == "rpm" ]] && file_pattern="href=\"${pkg}-[0-9][^\"]+\.rpm\""

        local file
        file=$(grep -oE "$file_pattern" <<< "$index_html" | cut -d'"' -f2 | sort -V | tail -n 1 || true)

        if [[ -n "$file" ]]; then
            if [[ "$dry_run" == "true" ]]; then
                log "[DRY RUN] Would download $file from $base_url"
            else
                log "Downloading $file..."
                if ! curl -fSL "${base_url}${file}" -o "${dest_dir}/${file}"; then
                    err "Download failed for $file"
                    failed=$((failed + 1))
                fi
            fi
        else
            err "Could not find any package matching $pkg at $base_url"
            failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        warn "Some packages failed to find/download. Check the errors above."
    else
        if [[ "$dry_run" == "true" ]]; then
            log "Dry run completed successfully!"
            rmdir "$dest_dir" 2>/dev/null || true
        else
            log "Generating SHA256 checksums…"
            (cd "$dest_dir" && sha256sum -- *."${ext}" > checksums.sha256)
            log "Completed! All files downloaded to ./${dest_dir}"
            log "Checksums saved to ./${dest_dir}/checksums.sha256"
        fi
    fi
}

# ── Airgap: install from local packages ──────────────────────────────
do_install() {
    local pkg_dir="$1"
    [[ -d "$pkg_dir" ]] || die "Directory not found: $pkg_dir"

    # Verify checksums if available
    if [[ -f "${pkg_dir}/checksums.sha256" ]]; then
        log "Verifying SHA256 checksums…"
        (cd "$pkg_dir" && sha256sum -c checksums.sha256) || die "Checksum verification failed! Packages may be corrupted."
        log "All checksums verified."
    else
        warn "No checksums.sha256 found — skipping integrity check."
    fi

    # Detect package type
    local deb_count rpm_count
    deb_count=$(find "$pkg_dir" -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)
    rpm_count=$(find "$pkg_dir" -maxdepth 1 -name '*.rpm' 2>/dev/null | wc -l)

    if [[ "$deb_count" -gt 0 ]]; then
        log "Found $deb_count .deb packages. Installing with dpkg…"
        sudo dpkg -i "${pkg_dir}"/*.deb || {
            warn "dpkg reported issues — attempting to fix dependencies…"
            sudo apt-get install -f -y
        }
    elif [[ "$rpm_count" -gt 0 ]]; then
        log "Found $rpm_count .rpm packages. Installing…"
        if command -v dnf >/dev/null 2>&1; then
            # dnf resolves dependencies against already-installed packages, so a
            # normal target (which already has base OS deps) installs offline;
            # bare `rpm -Uvh` would abort on any unmet dependency.
            sudo dnf install -y "${pkg_dir}"/*.rpm
        else
            sudo rpm -Uvh --force "${pkg_dir}"/*.rpm
        fi
    else
        die "No .deb or .rpm packages found in $pkg_dir"
    fi

    enable_and_group

    log "Docker installed successfully (offline)!"
}

# ── Airgap mode entry point ──────────────────────────────────────────
run_airgap() {
    [[ $# -lt 1 ]] && { err "Airgap mode requires --prepare or a package directory."; echo ""; usage; }

    case "$1" in
        -h|--help) usage ;;
        --prepare) shift; do_prepare "$@" ;;
        -*) die "Unknown airgap option: $1. Use --help for usage." ;;
        *)  do_install "$1" ;;
    esac
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    # Pre-scan for --airgap; collect the remaining args untouched so each
    # mode parses its own flags exactly as before.
    local airgap=false
    local rest=()
    for arg in "$@"; do
        if [[ "$arg" == "--airgap" ]]; then
            airgap=true
        else
            rest+=("$arg")
        fi
    done

    if [[ "$airgap" == "true" ]]; then
        run_airgap "${rest[@]}"
    else
        run_online "${rest[@]}"
    fi
}

main "$@"
