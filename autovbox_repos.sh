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

# Get real user home directory for Downloads
REAL_USER="${SUDO_USER:-$USER}"
DOWNLOADS_DIR="/home/${REAL_USER}/Downloads"

# Function to download Extension Pack
download_extension_pack() {
    echo -e "${GREEN}[+] Downloading VirtualBox Extension Pack...${NC}"
    
    # Create Downloads folder if needed
    mkdir -p "$DOWNLOADS_DIR"
    
    # Get latest stable version
    VBOX_VERSION=$(wget -qO- https://download.virtualbox.org/virtualbox/LATEST-STABLE.TXT)
    
    if [ -z "$VBOX_VERSION" ]; then
        echo -e "${YELLOW}[WARNING] Unable to detect latest VirtualBox version${NC}"
        echo -e "${YELLOW}[INFO] Using default version 7.1.6${NC}"
        VBOX_VERSION="7.1.6"
    fi
    
    echo -e "${YELLOW}[INFO] Latest stable version: ${VBOX_VERSION}${NC}"
    
    EXTPACK_URL="https://download.virtualbox.org/virtualbox/${VBOX_VERSION}/Oracle_VirtualBox_Extension_Pack-${VBOX_VERSION}.vbox-extpack"
    EXTPACK_FILE="${DOWNLOADS_DIR}/Oracle_VirtualBox_Extension_Pack-${VBOX_VERSION}.vbox-extpack"
    
    # Download Extension Pack
    if wget -q --show-progress -O "$EXTPACK_FILE" "$EXTPACK_URL"; then
        # Set correct ownership
        chown "${REAL_USER}:${REAL_USER}" "$EXTPACK_FILE"
        echo -e "${GREEN}[OK] Extension Pack downloaded successfully!${NC}"
        echo -e "${YELLOW}[INFO] Saved to: ${EXTPACK_FILE}${NC}"
        echo ""
        echo -e "${YELLOW}To install Extension Pack after installing VirtualBox, run:${NC}"
        echo -e "${BLUE}   sudo VBoxManage extpack install --replace \"${EXTPACK_FILE}\"${NC}"
    else
        echo -e "${RED}[ERROR] Failed to download Extension Pack${NC}"
        echo -e "${YELLOW}[INFO] You can download it manually from: https://www.virtualbox.org/wiki/Downloads${NC}"
    fi
    echo ""
}

# Function for Debian/Ubuntu based distributions
# Logic: Only pure Ubuntu and Debian use native codenames, ALL derivatives use Ubuntu LTS
setup_debian_ubuntu() {
    echo -e "${GREEN}[1/5] Installing required dependencies...${NC}"
    apt-get update -qq
    apt-get install -y -qq wget gnupg2 apt-transport-https ca-certificates

    echo -e "${GREEN}[2/5] Downloading and importing Oracle GPG keys...${NC}"
    
    # Create directory for keys if it doesn't exist
    mkdir -p /etc/apt/keyrings
    
    # Download and import Oracle GPG keys
    wget -qO- https://www.virtualbox.org/download/oracle_vbox_2016.asc | gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox-2016.gpg
    wget -qO- https://www.virtualbox.org/download/oracle_vbox.asc | gpg --dearmor -o /etc/apt/keyrings/oracle-virtualbox.gpg

    echo -e "${GREEN}[3/5] Adding VirtualBox repository...${NC}"
    
    # Ubuntu LTS codename - used for ALL derivatives
    UBUNTU_LTS_CODENAME="noble"  # Ubuntu 24.04 LTS
    
    # List of supported codenames in VirtualBox repository
    # Ubuntu: noble (24.04), jammy (22.04), focal (20.04), bionic (18.04)
    # Debian: bookworm, bullseye, buster
    SUPPORTED_UBUNTU="noble jammy focal bionic"
    SUPPORTED_DEBIAN="bookworm bullseye buster"
    
    # Determine correct codename based on distribution type
    # ONLY pure "ubuntu" and "debian" use their native codenames
    # ALL other distributions (derivatives) use Ubuntu LTS
    if [ "$DISTRO" = "debian" ]; then
        # Pure Debian: use native codename if supported, otherwise fallback to bookworm
        if echo "$SUPPORTED_DEBIAN" | grep -qw "$VERSION_CODENAME"; then
            REPO_CODENAME="$VERSION_CODENAME"
        else
            echo -e "${YELLOW}[WARNING] Debian codename '${VERSION_CODENAME}' not supported${NC}"
            echo -e "${YELLOW}[INFO] Using fallback: Debian bookworm${NC}"
            REPO_CODENAME="bookworm"
        fi
    elif [ "$DISTRO" = "ubuntu" ]; then
        # Pure Ubuntu: use native codename if supported, otherwise fallback to LTS
        if echo "$SUPPORTED_UBUNTU" | grep -qw "$VERSION_CODENAME"; then
            REPO_CODENAME="$VERSION_CODENAME"
        else
            echo -e "${YELLOW}[WARNING] Ubuntu codename '${VERSION_CODENAME}' not supported${NC}"
            echo -e "${YELLOW}[INFO] Using fallback: Ubuntu 24.04 LTS (${UBUNTU_LTS_CODENAME})${NC}"
            REPO_CODENAME="$UBUNTU_LTS_CODENAME"
        fi
    else
        # ANY other distribution = Ubuntu/Debian derivative
        # Always use Ubuntu LTS repository
        echo -e "${YELLOW}[INFO] Derivative distribution detected (${DISTRO})${NC}"
        echo -e "${YELLOW}[INFO] Using Ubuntu 24.04 LTS repository${NC}"
        REPO_CODENAME="$UBUNTU_LTS_CODENAME"
    fi
    
    echo -e "${YELLOW}[INFO] Using repository codename: ${REPO_CODENAME}${NC}"
    
    # Add the repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian ${REPO_CODENAME} contrib" > /etc/apt/sources.list.d/virtualbox.list

    echo -e "${GREEN}[4/5] Updating package list...${NC}"
    apt-get update

    echo -e "${GREEN}[5/5] Downloading Extension Pack...${NC}"
    download_extension_pack

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
    echo -e "${GREEN}[1/4] Installing required dependencies...${NC}"
    dnf install -y -q wget

    echo -e "${GREEN}[2/4] Downloading and configuring VirtualBox repository...${NC}"
    
    # Download VirtualBox repo file
    wget -q https://download.virtualbox.org/virtualbox/rpm/fedora/virtualbox.repo -O /etc/yum.repos.d/virtualbox.repo

    echo -e "${GREEN}[3/4] Updating repository cache...${NC}"
    dnf check-update -q || true

    echo -e "${GREEN}[4/4] Downloading Extension Pack...${NC}"
    download_extension_pack

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
    echo -e "${GREEN}[1/4] Adding VirtualBox repository...${NC}"
    
    # Determine openSUSE version
    if [[ "$VERSION_ID" == "tumbleweed" ]] || [[ "$PRETTY_NAME" == *"Tumbleweed"* ]]; then
        SUSE_VERSION="openSUSE_Tumbleweed"
    else
        SUSE_VERSION="openSUSE_Leap_${VERSION_ID}"
    fi
    
    zypper addrepo --refresh "https://download.virtualbox.org/virtualbox/rpm/${SUSE_VERSION}/virtualbox.repo"

    echo -e "${GREEN}[2/4] Importing GPG key...${NC}"
    rpm --import https://www.virtualbox.org/download/oracle_vbox_2016.asc

    echo -e "${GREEN}[3/4] Refreshing repositories...${NC}"
    zypper refresh

    echo -e "${GREEN}[4/4] Downloading Extension Pack...${NC}"
    download_extension_pack

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
    linuxmint)
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}   Linux Mint - Manual Installation Required${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${RED}Regarding Linux Mint, we cannot find a way to make this script work.${NC}"
        echo -e "${RED}You need to download the .deb file from the VirtualBox website${NC}"
        echo -e "${RED}every time and install the .deb with: sudo apt -f install${NC}"
        echo ""
        echo -e "${BLUE}Download page: https://www.virtualbox.org/wiki/Linux_Downloads${NC}"
        echo ""
        exit 0
        ;;
    ubuntu|debian)
        # Pure Ubuntu or Debian: use native codename when supported
        setup_debian_ubuntu
        ;;
    pop|elementary|zorin|zorinos|neon|kubuntu|xubuntu|lubuntu|ubuntumate|ubuntubudgie|ubuntustudio|ubuntukylin|ubuntucinnamon|bodhi|peppermint|feren|voyager|lxle|linux-lite|galliumos)
        # Ubuntu derivatives: function will detect and use Ubuntu LTS
        setup_debian_ubuntu
        ;;
    fedora)
        setup_fedora_rhel
        ;;
    rhel|centos|rocky|almalinux)
        echo -e "${YELLOW}[INFO] Detected RHEL-based distribution, using Fedora configuration...${NC}"
        echo -e "${GREEN}[1/3] Installing dependencies...${NC}"
        dnf install -y -q wget
        echo -e "${GREEN}[2/3] Adding repository...${NC}"
        # Use ol for Oracle Linux or el for others
        wget -q https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo -O /etc/yum.repos.d/virtualbox.repo
        dnf check-update -q || true
        echo -e "${GREEN}[3/3] Downloading Extension Pack...${NC}"
        download_extension_pack
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
        # Check if it's an Ubuntu/Debian derivative via ID_LIKE
        if echo "$DISTRO_LIKE" | grep -qw "ubuntu"; then
            echo -e "${YELLOW}[INFO] Detected Ubuntu-based derivative: ${DISTRO}${NC}"
            setup_debian_ubuntu
        elif echo "$DISTRO_LIKE" | grep -qw "debian"; then
            echo -e "${YELLOW}[INFO] Detected Debian-based derivative: ${DISTRO}${NC}"
            setup_debian_ubuntu
        else
            echo -e "${RED}[ERROR] Unsupported distribution: ${DISTRO}${NC}"
            echo -e "${YELLOW}Supported distributions: Ubuntu, Debian, Linux Mint, Fedora, RHEL, CentOS, openSUSE${NC}"
            echo -e "${YELLOW}Ubuntu/Debian derivatives are also supported automatically${NC}"
            exit 1
        fi
        ;;
esac

echo -e "${YELLOW}[NOTE] Remember to also install Guest Additions inside your VMs if needed!${NC}"
echo -e "${YELLOW}[NOTE] Extension Pack has been downloaded to: ${DOWNLOADS_DIR}${NC}"
echo ""
