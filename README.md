# Docker Installer for Linux

A single-command bash script to install the latest Docker Engine and Docker Compose on Linux servers.

## Features

- Installs Docker Engine, CLI, containerd, Buildx, and Compose plugin
- Supports APT-based (Ubuntu, Debian, Raspbian) and DNF-based (Fedora, RHEL, CentOS) distributions
- Automatically configures non-root Docker access when run as a non-root user
- Enables Docker and containerd to start on boot
- Pre-flight checks to prevent conflicts with existing installations

## Prerequisites

- A supported Linux distribution
- Root or sudo privileges
- No existing Docker installation (uninstall any conflicting packages first)

## Usage

```bash
bash <(curl -sSL https://github.com/ongtungduong/docker-installer/raw/main/install-docker.sh)
```

## What It Does

1. Checks if Docker is already installed
2. Detects the OS and selects the appropriate package manager
3. Adds the official Docker repository and GPG key
4. Installs Docker Engine and related packages
5. Enables Docker and containerd services on boot
6. Configures Docker for non-root usage (skipped when running as root)

## Supported Distributions

| Package Manager | Distributions            |
| --------------- | ------------------------ |
| APT             | Ubuntu, Debian, Raspbian |
| DNF             | Fedora, RHEL, CentOS     |

## Disclaimer

This script has only been tested on **Ubuntu**. While it is designed to support other distributions listed above, use it on non-Ubuntu systems at your own risk.
