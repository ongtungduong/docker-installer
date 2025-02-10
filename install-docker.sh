#!/bin/bash

function checkOS() {
    source /etc/os-release
    if [[ ${ID} == "ubuntu" ]] && [[ $(echo "${VERSION_ID}" | cut -d'.' -f1) -ge 20 ]]; then
        echo "ubuntu"
    fi
}

function installDockerUbuntu() {
    # Update package list and install necessary dependencies
    sudo apt-get update -y
    sudo apt-get install ca-certificates curl gnupg -y

    # Create the keyrings directory if it doesn't exist
    sudo install -m 0755 -d /etc/apt/keyrings

    # Add Docker's GPG key to the keyring
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository to APT sources
    echo "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

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
	sudo usermod -aG docker $USER
	newgrp docker
}

function configureDockerToStartOnBoot() {
    sudo systemctl enable docker
    sudo systemctl enable containerd
}

function main() {
    checkDockerInstallation
    case $(checkOS) in
        "ubuntu")
            installDockerUbuntu
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