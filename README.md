# Docker installer for Ubuntu servers

**This project is a bash script that aims to setup Docker on Ubuntu servers, as easily as possible!**

- Make sure that your OS matches Docker Engine's requirements and uninstall any conflicting packages.

- This script will install the latest version of Docker Engine and Docker Compose.

## Usage

Run the following command to install Docker on your Ubuntu server:

```bash
bash <(curl -sSL https://github.com/ongtungduong/docker-installer/raw/main/install-docker.sh)
```

To install specific version of Docker. For example version 20.10.24:

```bash
VERSION="20.10.24" bash <(curl -sSL https://github.com/ongtungduong/docker-installer/raw/main/install-docker.sh)
```
