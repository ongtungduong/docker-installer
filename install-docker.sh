#!/bin/bash
# set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly GPG_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"

# ── Global flags ─────────────────────────────────────────────────────
ASSUME_YES=false
UPGRADE=false
DOCKER_VERSION=""

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# ── Cleanup on failure ──────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warn "Installation failed (exit code: $exit_code). Cleaning up partial configuration…"
        sudo rm -f /etc/apt/sources.list.d/docker.sources /etc/apt/sources.list.d/docker.list 2>/dev/null || true
        sudo rm -f /etc/apt/keyrings/docker.asc 2>/dev/null || true
        sudo rm -f /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install Docker Engine and Docker Compose on Linux.

Options:
  -y, --yes          Non-interactive mode (skip confirmation prompts).
  --version <ver>    Install a specific Docker version (e.g., 5:27.5.1-1).
  --upgrade          Upgrade Docker if already installed (instead of aborting).
  -h, --help         Show this help message.

Example:
  $0 --yes
  $0 --version 5:27.5.1-1~ubuntu.24.04~noble
  $0 --upgrade
EOF
    exit 0
}

is_interactive() {
    [[ "$ASSUME_YES" == "true" ]] && return 1
    [[ -t 0 ]] && return 0
    return 1
}

# ── Helpers ──────────────────────────────────────────────────────────
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

# ── Installers ───────────────────────────────────────────────────────
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
    sudo apt-get install -y "${pkgs[@]}"
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
    sudo dnf install -y "${pkgs[@]}"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
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

    log "Enabling Docker & containerd on boot…"
    sudo systemctl enable --now docker containerd

    if [[ $EUID -ne 0 ]]; then
        log "Configuring Docker for non-root usage (adding to 'docker' group)…"
        sudo groupadd -f docker
        sudo usermod -aG docker "$USER"
        warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
    fi

    log "Docker installed successfully!"
}

main "$@"
