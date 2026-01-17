# VirtualBox repo setup + Extension Pack downloader

This Bash script is meant to be run with `sudo` on **Debian/Ubuntu** or **Fedora-based** Linux systems. Its main goal is to **add the official Oracle VirtualBox repositories** (it does **not** install VirtualBox by default).

# Problems after adding archive
Some people have reported to me via DM on Discord and Telegram that after adding the repositories and performing the normal installation from the terminal, it fails because it detects a conflict between two identical packages, neither of which can be installed.

This is a problem related to Virtualbox repositories, and I don't think I can do much with my script. I ran some tests in vm, and the only solution at the moment would be to wait for everything to return to normal.
