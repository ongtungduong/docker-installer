# Docker installer for Ubuntu servers

**This project is a bash script that aims to setup Docker on Ubuntu servers, as easily as possible!**

- Make sure that your OS matches Docker Engine's requirements.

- You need to uninstall any conflicting packages before running the script.
  ```bash
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done
  sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
  ```

- This script will install the latest version of Docker Engine and Docker Compose.

## Usage

Run the following command to install Docker on your Ubuntu server:

```bash
bash <(curl -sSL https://github.com/ongtungduong/docker-installer/raw/main/install-docker.sh)
```

To install specific version of Docker. For example version 20.10.24:

```bash
version="20.10.24" bash <(curl -sSL https://github.com/ongtungduong/docker-installer/raw/main/install-docker.sh)
```
