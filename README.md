# Docker installer for Ubuntu servers

**This project is a bash script that aims to setup Docker on Ubuntu servers, as easily as possible!**

- Make sure that your OS matches Docker Engine's requirements.

- You need to uninstall any conflicting packages before running the script.

- This script will install the latest version of Docker Engine and Docker Compose.

## Usage

Run the following command to install Docker on your Ubuntu server:

```bash
curl https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh | bash
```

To install specific version of Docker. For example version 20.10.24:

```bash
curl https://raw.githubusercontent.com/ongtungduong/docker-installer/main/install-docker.sh | version="20.10.24" bash
```
