#!/bin/bash

DIR="${DIR:-"/usr/local/bin"}"

ARCH=$(uname -m)
case $ARCH in
    i386|i686) ARCH=x86 ;;
    armv6*) ARCH=armv6 ;;
    armv7*) ARCH=armv7 ;;
    aarch64*) ARCH=arm64 ;;
esac

LATEST_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
FILE_NAME="lazydocker_${LATEST_VERSION}_$(uname -s)_${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/jesseduffield/lazydocker/releases/download/v${LATEST_VERSION}/${FILE_NAME}"

curl -L -o lazydocker.tar.gz $DOWNLOAD_URL
tar xzvf lazydocker.tar.gz lazydocker
sudo install -Dm 755 lazydocker -t "$DIR"
rm lazydocker lazydocker.tar.gz