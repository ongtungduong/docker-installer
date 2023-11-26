#!/bin/bash

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

# Manage Docker as a non-root user
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker installation by displaying the version
docker --version
docker compose version