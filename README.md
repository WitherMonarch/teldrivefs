# teldrivefs

Deploy Teldrive as a local network share using Samba and Rclone with local caching and custom quota management.

## Features & Improvements over Teldrive
* **Reliable File Editing:** Uses Rclone's `hasher` overlay to manage file integrity verification, resolving file-editing and sync issues present in standard Teldrive Rclone mounts.
* **Smart Cache Protection:** Injects a custom `dfree.sh` script into Samba to report a fixed 20GB of free space, preventing clients from uploading files larger than the local disk cache.

## Prerequisites

### Requirements
* A Telegram account and at least 1 Telegram bot token.
* A server or VM with a minimum of 35 GB storage.

### Verified OS & Specs
* **Debian 13** (Cloud & Standard)
* **Ubuntu 24.04** (Standard)
* *Recommendation:* Use Cloud images (e.g., on Proxmox) for the lowest footprint (**1 CPU, 1 GB RAM**).

## Installation & Usage

### Quick Install
Run the automated installation script:

wget https://raw.githubusercontent.com/WitherMonarch/teldrivefs/main/teldrivefs-install.sh
chmod +x teldrivefs-install.sh
sudo ./teldrivefs-install.sh

### Custom Install
To customize configurations before deploying, download and edit the script manually:

wget https://raw.githubusercontent.com/WitherMonarch/teldrivefs/main/teldrivefs-install.sh
# Edit teldrivefs-install.sh with your preferred editor, then run:
chmod +x teldrivefs-install.sh
sudo ./teldrivefs-install.sh

### Accessing the Share
The installer configures two default Samba accounts (passwords match the usernames by default, but can be changed during installation):
* **Read-Write Access:** user-rw
* **Read-Only Access:** user-ro

## Architecture & Data Flow

Telegram ↔ Teldrive (Docker) ↔ Rclone (hasher) ↔ /mnt/teldrivefs ↔ Samba

### Component Breakdown
* **Docker (teldrivefs-docker.service):** Manages the PostgreSQL database and the Teldrive API container.
* **Rclone (teldrivefs-rclone.service):** Mounts the Teldrive remote via a `hasher` wrapper. Manages VFS caching and transparent data transfer.
* **Samba (smbd):** Exposes the local Rclone mount point (/mnt/teldrivefs) to the network as a standard network share.
* **dfree.sh:** A script injected into Samba that forces the OS to report a fixed 20GB free space limit to protect the local cache.

## Management & Structure

All configuration files and services are centrally managed via symlinks located in /opt/teldrivefs/symlinks/:

| File / Directory | Purpose |
| :--- | :--- |
| config.toml | Teldrive core settings and secrets |
| rclone.conf | Rclone connection and mount parameters |
| smb.conf | Samba share definitions |
| teldrivefs-docker.service | systemd unit for Docker container control |
| teldrivefs-rclone.service | systemd unit for Rclone mount control |
| vfs/ | Active Rclone local cache directory |