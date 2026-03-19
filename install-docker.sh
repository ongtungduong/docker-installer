#!/bin/bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
readonly GPG_FINGERPRINT="060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35"

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# ── Helpers ──────────────────────────────────────────────────────────
preflight() {
    command -v docker >/dev/null 2>&1 && die "Docker is already installed ($(docker --version)). Uninstall it first."
    [[ $EUID -ne 0 ]] && ! sudo -v &>/dev/null && die "This script requires root or sudo privileges."
}

detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found. Unsupported system."
    # shellcheck source=/dev/null
    source /etc/os-release
    printf '%s' "${ID:-}"
}

# ── Installers ───────────────────────────────────────────────────────
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
    sudo apt-get install -y "${DOCKER_PACKAGES[@]}"
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

    warn "Verify GPG fingerprint matches: $GPG_FINGERPRINT"
    read -rp "Press Enter to continue (Ctrl-C to abort)… "

    log "Installing Docker Engine…"
    sudo dnf install -y "${DOCKER_PACKAGES[@]}"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
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

