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
readonly APT_KEY_FINGERPRINT="9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88"
readonly RPM_KEY_FINGERPRINT="060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35"
# Only these two are pinned by --version; the rest follow the repo's latest.
readonly VERSION_PINNED_PACKAGES=(docker-ce docker-ce-cli)
readonly CURL_OPTS=(-fsSL --retry 3 --connect-timeout 15)

# ── Global flags (online mode) ───────────────────────────────────────
ASSUME_YES=false
UPGRADE=false
DOCKER_VERSION=""
ALLOW_UNVERIFIED=false
TMP_KEY=""
CREATED_FILES=()   # config files this run created; removed on failure

# ── Logging helpers ──────────────────────────────────────────────────
log()  { printf '\033[1;32m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$@"; exit 1; }

# curl with retries and a hard time limit: fetch <max-seconds> <curl args…>
fetch() {
    local max="$1"; shift
    curl "${CURL_OPTS[@]}" --max-time "$max" "$@"
}

# Option parsing: ensure an option that takes a value actually has one.
need_value() {
    [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "Option $1 requires a value. Use --help for usage."
}

# ── Shared: enable services & configure non-root access ──────────────
enable_and_group() {
    log "Enabling Docker & containerd on boot…"
    sudo systemctl enable --now docker containerd

    if [[ $EUID -ne 0 ]]; then
        log "Configuring Docker for non-root usage (adding to 'docker' group)…"
        sudo groupadd -f docker
        sudo usermod -aG docker "$USER"
        warn "Members of the 'docker' group have root-equivalent privileges on this host."
        warn "Log out and back in (or run 'newgrp docker') for group changes to take effect."
    fi
}

# ── Cleanup (online mode only) ───────────────────────────────────────
# Removes the temp key always, and on failure only the files this run created;
# pre-existing repo/key files are never touched.
track_new() { [[ -e "$1" ]] || CREATED_FILES+=("$1"); }

cleanup() {
    local exit_code=$?
    if [[ -n "$TMP_KEY" ]]; then rm -f "$TMP_KEY"; fi
    if [[ $exit_code -ne 0 && ${#CREATED_FILES[@]} -gt 0 ]]; then
        warn "Installation failed (exit code: $exit_code). Removing files created by this run…"
        sudo rm -f "${CREATED_FILES[@]}" 2>/dev/null || true
    fi
}

usage() {
    cat <<EOF
Usage:
  $0 [OPTIONS]                          Install Docker online (default).
  $0 --airgap --prepare [OPTIONS]       Download Docker packages for offline use.
  $0 --airgap [--allow-unverified] <package-directory>
                                        Install Docker offline from downloaded packages.

Online options:
  -y, --yes          Non-interactive mode (skip confirmation prompts).
  --version <ver>    Pin docker-ce and docker-ce-cli to a version (e.g., 5:29.8.2-1~ubuntu.24.04~noble
                     on apt, 29.8.2-1.el9 on dnf). Other packages are not pinned.
  --upgrade          Upgrade Docker if already installed (instead of aborting).

Airgap prepare options (with --airgap --prepare):
  --os <os>          Target OS (ubuntu, debian, raspbian, fedora, centos, rhel).
  --os-version <ver> Target OS version/codename (e.g., noble for Ubuntu 24.04, 9 for RHEL 9).
  --arch <arch>      Target architecture (amd64, arm64, x86_64, aarch64). Default: host arch.
  --dry-run          Show what would be downloaded without actually downloading.

Airgap install options (with --airgap <package-directory>):
  --allow-unverified Install even if checksums.sha256 is missing (otherwise refused).
                     Integrity is checked against checksums.sha256 only; .rpm bundles
                     also carry the Docker GPG key (docker.gpg) whose fingerprint is
                     verified and used with 'rpm -K'. .deb bundles have no signature check.

Common:
  -h, --help         Show this help message.

Examples:
  $0 --yes
  $0 --version 5:29.8.2-1~ubuntu.24.04~noble
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
# Distro-packaged Docker/container packages that conflict with docker-ce.
check_conflicts() {
    local os="$1" p
    local installed=() remove_cmd
    case "$os" in
        ubuntu|debian|raspbian)
            for p in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
                # shellcheck disable=SC2016  # ${db:…} is a dpkg-query format, not a shell expansion
                [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null)" == ii* ]] && installed+=("$p")
            done
            remove_cmd="sudo apt-get remove" ;;
        rhel|centos|fedora)
            for p in docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc; do
                rpm -q "$p" >/dev/null 2>&1 && installed+=("$p")
            done
            remove_cmd="sudo dnf remove" ;;
        *) return 0 ;;
    esac
    [[ ${#installed[@]} -eq 0 ]] && return 0
    die "Conflicting packages are installed: ${installed[*]}
Remove them first (this may also remove containers/images they manage):
  ${remove_cmd} ${installed[*]}"
}

preflight() {
    local os="$1"
    check_conflicts "$os"
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

# verify_key_fingerprint <keyfile> <expected fingerprint> — dies unless the file
# holds exactly one primary key with the expected fingerprint.
verify_key_fingerprint() {
    local keyfile="$1" expected="${2// /}" actual
    command -v gpg >/dev/null 2>&1 || die "gpg is required to verify the Docker key fingerprint."
    log "Verifying Docker GPG key fingerprint…"
    actual=$(gpg --show-keys --with-colons "$keyfile" 2>/dev/null \
        | awk -F: '/^pub:/{n++} /^fpr:/ && !f{fp=$10; f=1} END{if (n==1) print fp}')
    [[ "$actual" == "$expected" ]] || die "GPG fingerprint mismatch! Expected: $2, Got: ${actual:-<none>}"
    log "GPG fingerprint verified: $2"
}

# Download the repo key to a temp file (kept until exit; removed by cleanup).
download_key() {
    local url="$1"
    TMP_KEY=$(mktemp) || die "Could not create a temporary file."
    fetch 30 "$url" -o "$TMP_KEY" || die "Failed to download GPG key from $url"
}

# ── Build package list (--version pins docker-ce and docker-ce-cli only) ──
# build_package_list <version-separator> <array-name>   (apt: "=", dnf: "-")
build_package_list() {
    local sep="$1" pin
    # shellcheck disable=SC2178  # nameref to a caller array, not a string
    local -n _pkgs=$2
    _pkgs=()
    for pkg in "${DOCKER_PACKAGES[@]}"; do
        if [[ -n "$DOCKER_VERSION" ]]; then
            for pin in "${VERSION_PINNED_PACKAGES[@]}"; do
                [[ "$pkg" == "$pin" ]] && pkg="${pkg}${sep}${DOCKER_VERSION}"
            done
        fi
        _pkgs+=("$pkg")
    done
}

# ── Online installers ────────────────────────────────────────────────
install_docker_apt() {
    local os="$1"
    log "Installing prerequisites…"
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg

    log "Adding Docker GPG key…"
    download_key "https://download.docker.com/linux/${os}/gpg"
    verify_key_fingerprint "$TMP_KEY" "$APT_KEY_FINGERPRINT"
    sudo install -m 0755 -d /etc/apt/keyrings
    track_new /etc/apt/keyrings/docker.asc
    sudo install -m 0644 "$TMP_KEY" /etc/apt/keyrings/docker.asc

    log "Adding Docker APT repository…"
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "$os" == "raspbian" ]]; then
        track_new /etc/apt/sources.list.d/docker.list
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
            "$(dpkg --print-architecture)" "$os" "${VERSION_CODENAME:-}" | \
            sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    else
        track_new /etc/apt/sources.list.d/docker.sources
        sudo tee /etc/apt/sources.list.d/docker.sources <<EOF >/dev/null
Types: deb
URIs: https://download.docker.com/linux/${os}
Suites: ${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    fi

    log "Installing Docker Engine…"
    sudo apt-get update -y
    local pkgs=()
    build_package_list "=" pkgs
    sudo apt-get install -y "${pkgs[@]}" || die "Failed to install Docker packages."
}

install_docker_dnf() {
    local os="$1"
    log "Installing dnf-plugins-core…"
    sudo dnf install -y dnf-plugins-core
    command -v curl >/dev/null 2>&1 || sudo dnf install -y curl
    command -v gpg >/dev/null 2>&1 || sudo dnf install -y gnupg2

    log "Importing Docker RPM GPG key…"
    download_key "https://download.docker.com/linux/${os}/gpg"
    verify_key_fingerprint "$TMP_KEY" "$RPM_KEY_FINGERPRINT"
    sudo rpm --import "$TMP_KEY" || die "Failed to import Docker GPG key."

    local repo_url="https://download.docker.com/linux/${os}/docker-ce.repo"
    track_new /etc/yum.repos.d/docker-ce.repo
    if [[ "$os" == "fedora" ]]; then
        # dnf5 syntax (Fedora 41+)
        sudo dnf config-manager addrepo --from-repofile "$repo_url"
    else
        sudo dnf config-manager --add-repo "$repo_url"
    fi

    log "Installing Docker Engine…"
    local pkgs=()
    build_package_list "-" pkgs
    sudo dnf install -y "${pkgs[@]}" || die "Failed to install Docker packages."
}

# ── Online mode entry point ──────────────────────────────────────────
run_online() {
    trap cleanup EXIT

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes) ASSUME_YES=true; shift ;;
            --version) need_value "$@"; DOCKER_VERSION="$2"; shift 2 ;;
            --upgrade) UPGRADE=true; shift ;;
            -h|--help) usage ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done

    local os
    os=$(detect_os)
    log "Detected OS: $os"
    preflight "$os"

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
            --os) need_value "$@"; target_os="$2"; shift 2 ;;
            --os-version) need_value "$@"; target_version="$2"; shift 2 ;;
            --arch) need_value "$@"; target_arch="$2"; shift 2 ;;
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
        ppc64le) dpkg_arch="ppc64el" ;;
        ppc64el) rpm_arch="ppc64le" ;;
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
    index_html=$(fetch 30 "$base_url") || die "Failed to fetch index from $base_url. Check OS/Version/Arch."

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
                if ! fetch 600 "${base_url}${file}" -o "${dest_dir}/${file}"; then
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
        die "$failed package(s) failed to find/download — the bundle would be incomplete. Check the errors above."
    fi

    # rpm bundles carry the repo key so the offline host can check signatures.
    local extra_files=()
    if [[ "$ext" == "rpm" ]]; then
        local key_url="https://download.docker.com/linux/${target_os}/gpg"
        if [[ "$dry_run" == "true" ]]; then
            log "[DRY RUN] Would download and verify GPG key from $key_url"
        else
            log "Downloading RPM GPG key…"
            fetch 30 "$key_url" -o "${dest_dir}/docker.gpg" || die "Failed to download GPG key from $key_url"
            verify_key_fingerprint "${dest_dir}/docker.gpg" "$RPM_KEY_FINGERPRINT"
            extra_files=(docker.gpg)
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        log "Dry run completed successfully!"
        rmdir "$dest_dir" 2>/dev/null || true
    else
        log "Generating SHA256 checksums…"
        (cd "$dest_dir" && sha256sum -- *."${ext}" "${extra_files[@]}" > checksums.sha256)
        log "Completed! All files downloaded to ./${dest_dir}"
        log "Checksums saved to ./${dest_dir}/checksums.sha256"
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
        [[ "$ALLOW_UNVERIFIED" == "true" ]] || die "No checksums.sha256 found in $pkg_dir. Refusing to install unverified packages (use --allow-unverified to override)."
        warn "No checksums.sha256 found — installing UNVERIFIED packages (--allow-unverified)."
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
        command -v dnf >/dev/null 2>&1 || die "dnf is required to install .rpm bundles."
        if [[ -f "${pkg_dir}/docker.gpg" ]]; then
            if command -v gpg >/dev/null 2>&1; then
                verify_key_fingerprint "${pkg_dir}/docker.gpg" "$RPM_KEY_FINGERPRINT"
            else
                warn "gpg not found — bundled GPG key fingerprint not verified."
            fi
            sudo rpm --import "${pkg_dir}/docker.gpg" || die "Failed to import bundled GPG key."
            rpm -K "${pkg_dir}"/*.rpm || die "RPM signature verification failed!"
        else
            warn "No docker.gpg in bundle — RPM signatures not checked (checksums only)."
        fi
        # dnf resolves dependencies against already-installed packages, so a
        # normal target (which already has base OS deps) installs offline.
        sudo dnf install -y "${pkg_dir}"/*.rpm
    else
        die "No .deb or .rpm packages found in $pkg_dir"
    fi

    # Confirm the packages actually installed (catches arch mismatch, unmet
    # dependencies, or a partial dpkg/rpm run that would otherwise look fine).
    command -v docker >/dev/null 2>&1 || die "Offline install failed: 'docker' not found after install. Check the architecture and dependency errors above."

    enable_and_group

    log "Docker installed successfully (offline)!"
}

# ── Airgap mode entry point ──────────────────────────────────────────
run_airgap() {
    local prepare=false args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            --prepare) prepare=true ;;
            --allow-unverified) ALLOW_UNVERIFIED=true ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    if [[ "$prepare" == "true" ]]; then
        do_prepare "${args[@]}"
        return
    fi

    [[ ${#args[@]} -lt 1 ]] && { err "Airgap mode requires --prepare or a package directory."; echo ""; usage; }
    [[ ${#args[@]} -gt 1 ]] && die "Expected a single package directory, got: ${args[*]}"
    [[ "${args[0]}" == -* ]] && die "Unknown airgap option: ${args[0]}. Use --help for usage."
    do_install "${args[0]}"
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    # `local -n` (used below) needs bash 4.3+; this guard must stay 3.2-parseable.
    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
        die "bash 4.3 or newer is required (found ${BASH_VERSION})."
    fi

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
