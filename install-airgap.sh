#!/bin/bash
set -euo pipefail

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 <package-directory>

Install Docker Engine from locally downloaded packages (airgap/offline).
The package directory should be created by prepare-airgap.sh.

Options:
  -h, --help    Show this help message.

Example:
  $0 ./docker-ubuntu-noble-amd64-20260320
EOF
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    [[ $# -lt 1 ]] && { err "Missing package directory argument."; echo ""; usage; }
    [[ "$1" == "-h" || "$1" == "--help" ]] && usage

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
        log "Found $rpm_count .rpm packages. Installing with rpm…"
        sudo rpm -Uvh --force "${pkg_dir}"/*.rpm
    else
        die "No .deb or .rpm packages found in $pkg_dir"
    fi

    log "Enabling Docker & containerd on boot…"
    sudo systemctl enable --now docker containerd

    if [[ $EUID -ne 0 ]]; then
        log "Configuring Docker for non-root usage (adding to 'docker' group)…"
        sudo groupadd -f docker
        sudo usermod -aG docker "$USER"
        warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
    fi

    log "Docker installed successfully (offline)!"
}

main "$@"
