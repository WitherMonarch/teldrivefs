# teldrivefs
Deploy [Teldrive](https://github.com/tgdrive/teldrive) as a local network share using Samba and Rclone

# Usage and Requirements

## Requirements

* A Telegram account
* A server (or VM) with 35 GB storage
* At least 1 Telegram bot
## Recommendations

TeldriveFS is verified on the following distributions, feel free to test on others:

- **Debian 13** (Cloud & Standard)
- **Ubuntu 24.04** (Standard)

> **Recommendation:** Use Cloud images (tested primarily on Proxmox) for the lowest resource footprint (1 CPU, 1 GB RAM given the the VM only).

## Usage

TeldriveFS is installed using an install script, it can be customized by downloading it, editing it and then running it.

One-line install:
```
wget -qO- https://raw.githubusercontent.com/WitherMonarch/teldrivefs/main/teldrivefs-install.sh | sudo bash
```

To use the network drive, use the account **user-rw** for write permissions and **user-ro** for read-only permissions. Their password is their username by default but can be changed during the install.

Customise the installation by downloading the script and editing it
```
wget https://raw.githubusercontent.com/WitherMonarch/teldrivefs/main/teldrivefs-install.sh
```

# TeldriveFS Architecture

TeldriveFS creates a Samba share backed by Telegram storage, using local caching for performance and a custom quota manager to prevent disk overflow.

## Data Flow

`Telegram` ↔ `Teldrive (Docker)` ↔ `Rclone (hasher)` ↔ `/mnt/teldrivefs` ↔ `Samba`

## Component Breakdown

* **Docker (`teldrivefs-docker.service`)**: Runs the PostgreSQL database and the Teldrive API container.
* **Rclone (`teldrivefs-rclone.service`)**: Mounts the Teldrive remote via a `hasher` wrapper. Handles VFS caching and transparent encryption/decryption.
* **Samba (`smbd`)**: Exposes the Rclone mount point to the network as a Windows/macOS/Linux share.
* **dfree.sh**: A script injected into Samba that forces the OS to report a fixed free space (20GB). This prevents clients from attempting to copy files larger than the local cache.

## Management

All configuration and control files are symlinked to `/opt/teldrivefs/symlinks/`:

| File                        | Purpose                              |
| :-------------------------- | :----------------------------------- |
| `config.toml`               | Teldrive settings and secrets        |
| `rclone.conf`               | Rclone connection & mount parameters |
| `smb.conf`                  | Samba share definitions              |
| `teldrivefs-docker.service` | Docker container control             |
| `teldrivefs-rclone.service` | Rclone mount control                 |
| `vfs/`                      | The active Rclone cache directory    |
