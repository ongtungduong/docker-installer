# Docker Installer — Project Roadmap

## Current State

**Stable features** (shipped, CI-tested):
- Online installation via apt (Ubuntu, Debian, Raspberry Pi OS)
- Online installation via dnf (RHEL, CentOS Stream, Fedora)
- Airgap prepare mode (download packages on internet-connected machine)
- Airgap install mode (install from pre-downloaded packages on offline machine)
- GPG fingerprint verification (apt only)
- SHA256 checksum validation (airgap mode)
- Automated CI testing on 13 distributions, 2 package managers

**Current limitations**:
- dnf path lacks fingerprint verification (manual prompt only)
- No package manager support for zypper (SUSE/openSUSE)
- Limited architecture auto-detection for ARM edge devices
- Docker daemon configuration is manual (user edits `/etc/docker/daemon.json`)

---

## Planned Improvements

### Phase 1: DNF GPG Verification (Medium Priority)

**Objective**: Implement fingerprint validation for dnf installs to match apt security.

**Scope**:
- Add dnf GPG fingerprint check logic to `install_docker_dnf()`
- Requires parsing dnf config or using `rpm --import` + verification

**Effort**: Low (2–3 functions, ~20 LOC)

**Risk**: dnf ecosystem less uniform than apt; may need OS-specific tweaks.

### Phase 2: zypper Support (Low Priority)

**Objective**: Extend to SUSE Linux Enterprise, openSUSE.

**Scope**:
- Add `install_docker_zypper()` function
- Airgap mode support (prepare + install)
- CI: Add openSUSE 15/Tumbleweed to GitHub Actions matrix

**Effort**: Medium (~80 LOC per function; low complexity)

**User Demand**: Minimal; SUSE ecosystem uses Docker less frequently than Ubuntu/RHEL.

### Phase 3: ARM Architecture Refinement (Low-Medium Priority)

**Objective**: Improve auto-detection and documentation for ARM servers.

**Scope**:
- Better `uname -m` → architecture mapping (armv6, armv7 edge cases)
- Raspberry Pi OS version mapping refinement
- Documentation: ARM deployment patterns, known issues

**Effort**: Low (20–30 LOC); mostly documentation.

### Phase 4: Docker Version Pinning in Airgap (Medium Priority)

**Objective**: Allow `--prepare --version X.Y.Z` to lock specific Docker releases.

**Scope**:
- Add `--version` flag to airgap prepare mode
- Filter package downloads by exact version match
- Update checksums.sha256 path naming for version clarity

**Effort**: Medium (~40 LOC; adds complexity to version matching)

**Benefit**: Reproducible offline environments, compliance auditing.

---

## Not Planned

### Systemd Socket Activation

**Why deferred**:
- Docker defaults to traditional service startup
- Benefits unclear for target users (DevOps/SRE automation)
- Would add config file generation (scope creep)

### Audit Logging to Syslog

**Why deferred**:
- Syslog availability varies by distro
- Bash lacks structured logging libraries
- Installation logs already printed to console
- Integration: user can wrap script with `tee` to capture

### Custom Docker Daemon Tuning

**Why not in scope**:
- `/etc/docker/daemon.json` varies by workload
- Script keeps YAGNI principle: install, don't configure
- Users customize post-install based on needs

### Network Mirror Support

**Why not in scope**:
- Complexity: cache invalidation, fallback logic, mirror selection
- Alternative: users run `--prepare` on internal network gateway (simpler)

---

## Known Limitations & Workarounds

| Limitation | Impact | Workaround |
|---|---|---|
| **DNF lacks fingerprint verification** | dnf installs trust repos implicitly (accepts manual prompt) | Monitor Docker repo changes; consider signed RPMs in future |
| **Airgap prepare requires internet** | Must run on connected machine first | Use GitHub Actions to auto-prepare and cache packages in private repos |
| **No daemon.json auto-generation** | Users manually configure Docker settings | Provide example configs in deployment guide; document common patterns |
| **Limited exotic arch support** | armv6/armv8 edge cases may need manual fixes | Test on actual hardware; document workarounds per distro |
| **Container systemd limitations** | Docker services may not start in CI containers | Mock systemctl in CI; install succeeds but services unmanaged (acceptable for CI) |

---

## Success Metrics

| Metric | Target | Current |
|---|---|---|
| **Distro coverage** | Top 13 Linux distros across apt/dnf | 13/13 ✓ |
| **Test automation** | 100% CI pass before merge | 28 jobs (13 distros × 2 modes + 2 real airgap installs) ✓ |
| **Script size** | <500 LOC single script | ~428 LOC (unified online + airgap) ✓ |
| **Install speed** | <90 seconds on modern hardware | ~30–45 seconds (verified) ✓ |
| **Security** | GPG verification + checksum validation | apt ✓, airgap ✓, dnf → pending |
| **User adoption** | Steady GitHub stars, low issue rate | Tracking |

---

## Release Timeline (Aspirational)

| Version | Target | Content |
|---|---|---|
| **v1.0** | Q2 2025 | Online + airgap core features, 13 distros |
| **v1.1** | Q3 2025 | DNF fingerprint verification, improved ARM docs |
| **v1.2** | Q4 2025 | Airgap version pinning, zypper exploration |
| **v2.0** | 2026+ | zypper support, extended architecture coverage |

*Note: Timeline flexible based on user feedback and community contributions.*
