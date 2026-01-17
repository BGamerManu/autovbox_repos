# `autovbox_repos.sh` — VirtualBox repo setup + Extension Pack downloader

This Bash script is meant to be run with `sudo` on **Debian/Ubuntu** or **Fedora-based** Linux systems. Its main goal is to **prepare the official Oracle VirtualBox repositories** (it does **not** install VirtualBox by default).

## What it does
- ~Detects the distro family via `/etc/os-release` (supports Debian/Ubuntu and Fedora)~
- Installs the minimal dependencies needed to manage repos/keys and download files (e.g., `curl/wget`, `gnupg`, certs, etc.).
- Adds the **official VirtualBox repository**:
  - Debian/Ubuntu: imports Oracle’s GPG key into a keyring, writes an `apt` repo file, and runs `apt update` (with a lock-wait helper to avoid `apt/dpkg` lock issues).
  - Fedora: installs the repo file under `/etc/yum.repos.d/`, imports Oracle’s GPG key, and refreshes metadata via `dnf makecache`.
