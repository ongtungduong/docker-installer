#!/bin/bash

function getOS(){
    source /etc/os-release
    echo "${ID}"
}

function installDockerUbuntu() {
    # Update package list and install necessary dependencies
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl -y

    # Create the keyrings directory if it doesn't exist
    sudo install -m 0755 -d /etc/apt/keyrings

    # Add Docker's GPG key to the keyring
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository to APT sources
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list again to include Docker repository
    sudo apt-get update -y

    # Install Docker Engine, Docker CLI, containerd.io, docker-buildx-plugin, and docker-compose-plugin
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
}

function installDockerDebian() {
    # Update package list and install necessary dependencies
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl -y

    # Create the keyrings directory if it doesn't exist
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list again to include Docker repository
    sudo apt-get update -y

    # Install Docker Engine, Docker CLI, containerd.io, docker-buildx-plugin, and docker-compose-plugin
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
}

function checkDockerInstallation() {
	if docker --version > /dev/null 2>&1; then
		echo "Docker is already installed"
		echo "If you want to install a different version, you must uninstall the current version first"
		exit 1
	fi
}

function manageDockerAsNonRootUser() {
    sudo groupadd docker
	sudo usermod -aG docker $n
	newgrp docker
}

function configureDockerToStartOnBoot() {
    sudo systemctl enable docker --now
    sudo systemctl enable containerd --now
}

function main() {
    checkDockerInstallation

    case $(getOS) in
        "ubuntu")
            installDockerUbuntu
            ;;
        "debian")
            installDockerDebian
            ;;
        *)
            echo "Your operating system is not supported."
            exit 1
            ;;
    esac
    
    manageDockerAsNonRootUser
    configureDockerToStartOnBoot
}

main