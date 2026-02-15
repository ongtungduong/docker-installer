#!/bin/bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly DOCKER_GPG_FINGERPRINT="060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35"

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# ── OS detection (cached) ───────────────────────────────────────────
detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found. Unsupported system."
    # shellcheck source=/dev/null
    source /etc/os-release
    printf '%s' "${ID}"
}

# ── Pre-flight checks ───────────────────────────────────────────────
preflight() {
    if command -v docker &>/dev/null; then
        die "Docker is already installed ($(docker --version)). Uninstall it first if you want a fresh install."
    fi

    if [[ $EUID -ne 0 ]] && ! sudo -v 2>/dev/null; then
        die "This script requires root or sudo privileges."
    fi
}

# ── APT-based install (Ubuntu / Debian / Raspbian) ──────────────────
install_docker_apt() {
    local os="$1"

    log "Installing prerequisites…"
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl

    log "Adding Docker GPG key…"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/${os}/gpg" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    log "Adding Docker APT repository…"
    # shellcheck source=/dev/null
    local codename
    codename=$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
        "$(dpkg --print-architecture)" "${os}" "${codename}" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    log "Installing Docker Engine…"
    sudo apt-get update -y
    sudo apt-get install -y "${DOCKER_PACKAGES[@]}"
}

# ── DNF-based install (Fedora / RHEL / CentOS) ─────────────────────
install_docker_dnf() {
    local os="$1"

    log "Installing dnf-plugins-core…"
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --add-repo "https://download.docker.com/linux/${os}/docker-ce.repo"

    warn "Verify GPG fingerprint matches: ${DOCKER_GPG_FINGERPRINT}"
    read -rp "Press Enter to continue (Ctrl-C to abort)… "

    log "Installing Docker Engine…"
    sudo dnf install -y "${DOCKER_PACKAGES[@]}"
}

# ── Post-install ─────────────────────────────────────────────────────
setup_non_root_user() {
    log "Configuring Docker for non-root usage…"
    sudo groupadd -f docker                   # -f: no error if group exists
    sudo usermod -aG docker "${USER}"
}

enable_on_boot() {
    log "Enabling Docker & containerd on boot…"
    sudo systemctl enable --now docker containerd
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    preflight

    local os
    os=$(detect_os)
    log "Detected OS: ${os}"

    case "${os}" in
        ubuntu|debian|raspbian) install_docker_apt  "${os}" ;;
        fedora|rhel|centos)     install_docker_dnf  "${os}" ;;
        *) die "Unsupported operating system: ${os}" ;;
    esac

    enable_on_boot

    log "Docker installed successfully!"

    if [[ $EUID -ne 0 ]]; then
        setup_non_root_user
        warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
    fi
}

main "$@"