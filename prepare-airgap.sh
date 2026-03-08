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
Usage: $0 [OPTIONS]

Download Docker packages for offline installation (airgap).
If no options are provided, the script attempts to auto-detect target OS, version, and architecture.

Options:
  --os <os>          Target OS (ubuntu, debian, raspbian, fedora, centos, rhel).
  --os-version <ver> Target OS version/codename (e.g., noble for Ubuntu 24.04, 9 for RHEL 9).
  --arch <arch>      Target architecture (amd64, arm64, x86_64, aarch64). Default: host arch.
  -h, --help         Show this help message.

Example for Ubuntu 24.04 (noble) on amd64:
  $0 --os ubuntu --os-version noble --arch amd64
EOF
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    local target_os="" target_version="" target_arch=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --os) target_os="$2"; shift 2 ;;
            --os-version) target_version="$2"; shift 2 ;;
            --arch) target_arch="$2"; shift 2 ;;
            -h|--help) usage ;;
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
            log "Downloading $file..."
            if ! curl -fSL "${base_url}${file}" -o "${dest_dir}/${file}"; then
                err "Download failed for $file"
                failed=$((failed + 1))
            fi
        else
            err "Could not find any package matching $pkg at $base_url"
            failed=$((failed + 1))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        warn "Some packages failed to download. Check the errors above."
    else
        log "Completed! All files downloaded to ./${dest_dir}"
    fi
}

main "$@"
