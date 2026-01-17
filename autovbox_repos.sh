#!/bin/bash

# ============================================
# Script to add Oracle VirtualBox repositories
# Does NOT install VirtualBox, only configures repos
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   Oracle VirtualBox Repository Configuration   ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run this script as root (use sudo)${NC}"
    exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    DISTRO_LIKE=$ID_LIKE
    VERSION_CODENAME=${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo "")}
else
    echo -e "${RED}[ERROR] Unable to detect distribution${NC}"
    exit 1
fi

echo -e "${YELLOW}[INFO] Detected distribution: ${DISTRO} (${VERSION_CODENAME})${NC}"
echo ""

# Function for Debian/Ubuntu based distributions
setup_debian_ubuntu() {
    echo -e "${GREEN}[1/4] Installing required dependencies...${NC}"
    apt-get update -qq
    apt-get install -y -qq wget gnupg2 apt-transport-https ca-certificates

    echo -e "${GREEN}[2/4] Downloading and importing Oracle GPG keys...${NC}"
    
    # Create directory for keys if it doesn't exist
    mkdir -p /etc/apt/keyrings
    
    # Download and import Oracle GPG keys
    wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox-2016.gpg
    wget -qO- https://www.virtualbox.org/download/oracle_vbox.asc | gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox.gpg

    echo -e "${GREEN}[3/4] Adding VirtualBox repository...${NC}"
    
    # Determine correct codename
    if [ -z "$VERSION_CODENAME" ]; then
        echo -e "${RED}[ERROR] Unable to determine distribution codename${NC}"
        exit 1
    fi
    
    # Add the repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian ${VERSION_CODENAME} contrib" > /etc/apt/sources.list.d/virtualbox.list

    echo -e "${GREEN}[4/4] Updating package list...${NC}"
    apt-get update

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Repository configured successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}To install VirtualBox, run:${NC}"
    echo -e "${BLUE}   sudo apt install virtualbox-7.1${NC}"
    echo ""
    echo -e "${YELLOW}To see available versions:${NC}"
    echo -e "${BLUE}   apt-cache search virtualbox${NC}"
    echo ""
}

# Function for Fedora/RHEL based distributions
setup_fedora_rhel() {
    echo -e "${GREEN}[1/3] Installing required dependencies...${NC}"
    dnf install -y -q wget

    echo -e "${GREEN}[2/3] Downloading and configuring VirtualBox repository...${NC}"
    
    # Download VirtualBox repo file
    wget -q https://download.virtualbox.org/virtualbox/rpm/fedora/virtualbox.repo -O /etc/yum.repos.d/virtualbox.repo

    echo -e "${GREEN}[3/3] Updating repository cache...${NC}"
    dnf check-update -q || true

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Repository configured successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}To install VirtualBox, run:${NC}"
    echo -e "${BLUE}   sudo dnf install VirtualBox-7.1${NC}"
    echo ""
    echo -e "${YELLOW}To see available versions:${NC}"
    echo -e "${BLUE}   dnf search virtualbox${NC}"
    echo ""
}

# Function for openSUSE
setup_opensuse() {
    echo -e "${GREEN}[1/3] Adding VirtualBox repository...${NC}"
    
    # Determine openSUSE version
    if [[ "$VERSION_ID" == "tumbleweed" ]] || [[ "$PRETTY_NAME" == *"Tumbleweed"* ]]; then
        SUSE_VERSION="openSUSE_Tumbleweed"
    else
        SUSE_VERSION="openSUSE_Leap_${VERSION_ID}"
    fi
    
    zypper addrepo --refresh "https://download.virtualbox.org/virtualbox/rpm/${SUSE_VERSION}/virtualbox.repo"

    echo -e "${GREEN}[2/3] Importing GPG key...${NC}"
    rpm --import https://www.virtualbox.org/download/oracle_vbox_2016.asc

    echo -e "${GREEN}[3/3] Refreshing repositories...${NC}"
    zypper refresh

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}   Repository configured successfully!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}To install VirtualBox, run:${NC}"
    echo -e "${BLUE}   sudo zypper install VirtualBox-7.1${NC}"
    echo ""
}

# Run configuration based on distribution
case "$DISTRO" in
    ubuntu|debian|linuxmint|pop|elementary|zorin)
        setup_debian_ubuntu
        ;;
    fedora)
        setup_fedora_rhel
        ;;
    rhel|centos|rocky|almalinux)
        echo -e "${YELLOW}[INFO] Detected RHEL-based distribution, using Fedora configuration...${NC}"
        # Use ol for Oracle Linux or el for others
        wget -q https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo -O /etc/yum.repos.d/virtualbox.repo
        dnf check-update -q || true
        echo -e "${GREEN}Repository configured! Install with: sudo dnf install VirtualBox-7.1${NC}"
        ;;
    opensuse*|sles)
        setup_opensuse
        ;;
    arch|manjaro|endeavouros)
        echo -e "${YELLOW}[INFO] On Arch Linux, VirtualBox is available in the official repositories.${NC}"
        echo -e "${BLUE}Install with: sudo pacman -S virtualbox${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}[ERROR] Unsupported distribution: ${DISTRO}${NC}"
        echo -e "${YELLOW}Supported distributions: Ubuntu, Debian, Linux Mint, Fedora, RHEL, CentOS, openSUSE${NC}"
        exit 1
        ;;
esac

echo -e "${YELLOW}[NOTE] Remember to also install Guest Additions and Extension Pack if needed!${NC}"
echo ""
