#!/bin/bash
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────
readonly DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

usage() {
    cat <<EOF
Usage:
  $0 --prepare [OPTIONS]       Download Docker packages for offline installation.
  $0 <package-directory>       Install Docker from previously downloaded packages.

Prepare mode (--prepare):
  --os <os>          Target OS (ubuntu, debian, raspbian, fedora, centos, rhel).
  --os-version <ver> Target OS version/codename (e.g., noble for Ubuntu 24.04, 9 for RHEL 9).
  --arch <arch>      Target architecture (amd64, arm64, x86_64, aarch64). Default: host arch.
  --dry-run          Show what would be downloaded without actually downloading.

Install mode:
  <package-directory> Path to directory created by --prepare.

Common:
  -h, --help         Show this help message.

Examples:
  $0 --prepare --os ubuntu --os-version noble --arch amd64
  $0 ./docker-ubuntu-noble-amd64-20260320
EOF
    exit 0
}

# ── Prepare: download packages ──────────────────────────────────────
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

    local dest_dir="docker-${target_os}-${target_version}-${dpkg_arch}-$(date +%Y%m%d)"
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

# ── Install: install from local packages ─────────────────────────────
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

# ── Main ─────────────────────────────────────────────────────────────
main() {
    [[ $# -lt 1 ]] && { err "No arguments provided."; echo ""; usage; }

    case "$1" in
        -h|--help) usage ;;
        --prepare) shift; do_prepare "$@" ;;
        -*) die "Unknown option: $1. Use --help for usage." ;;
        *)  do_install "$1" ;;
    esac
}

main "$@"
