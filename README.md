# `autovbox_repos.sh` — VirtualBox repo setup + Extension Pack downloader

This Bash script is meant to be run with `sudo` on **Debian/Ubuntu** or **Fedora-based** Linux systems. Its main goal is to **prepare the official Oracle VirtualBox repositories** (it does **not** install VirtualBox by default).

## What it does
- Detects the distro family via `/etc/os-release` (supports Debian/Ubuntu and Fedora).
- Installs the minimal dependencies needed to manage repos/keys and download files (e.g., `curl/wget`, `gnupg`, certs, etc.).
- Adds the **official VirtualBox repository**:
  - Debian/Ubuntu: imports Oracle’s GPG key into a keyring, writes an `apt` repo file, and runs `apt update` (with a lock-wait helper to avoid `apt/dpkg` lock issues).
  - Fedora: installs the repo file under `/etc/yum.repos.d/`, imports Oracle’s GPG key, and refreshes metadata via `dnf makecache`.
- Shows which **VirtualBox packages/versions are installable** from the newly added repo.

## Optional features (flags)
- ~~`--latest-vbox`: after adding the repo, automatically installs the **latest available** VirtualBox package for your distro.~~
- `--vbox-version-txt`: creates a text file in the calling user’s **Downloads** listing installable VirtualBox versions/packages.
- ~~`-h`~~ / `--help`: prints usage.

## Always downloads the Extension Pack
~~At the end, it fetches Oracle’s `LATEST.TXT` to determine the newest VirtualBox version, then downloads the matching **Oracle VM VirtualBox Extension Pack** into:
`~/Downloads/Downloaded Extension Pack/`~~

## Known issues
- The script is currently known to **fail to automatically download the Extension Pack** in some environments.
- The script is currently known to **fail to automatically install the latest VirtualBox version** even when `--latest-vbox` is requested.
