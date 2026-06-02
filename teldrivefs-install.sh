#!/bin/bash

# Ensure running as root
if [[ $EUID -ne 0 ]]; then echo "This script must be run as root"; exit 1; fi

# Error handling: exit if any command fails
set -e
trap 'echo "--------------------------------------------------------"; echo "ERROR: Script failed at line $LINENO. Command exited with status $?."; echo "--------------------------------------------------------"; exit 1' ERR

USER_RUNNING_SCRIPT=${SUDO_USER:-$USER}

echo "--- Phase 1: Dependencies ---"
apt update && apt install -y fuse3 unzip samba curl
curl https://get.docker.com | sh
curl -sSL instl.vercel.app/rclone | bash
sleep 1

# Enable FUSE allow_other
if grep -q "^#user_allow_other" /etc/fuse.conf; then
    sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
fi
echo "--- Phase 1: Done ---"

echo "--- Phase 2: Users & Groups ---"
# Check if users exist to avoid errors
id -u teldrivefs &>/dev/null || adduser --system --shell /usr/sbin/nologin --group teldrivefs
id -u user-rw &>/dev/null || adduser --system --shell /usr/sbin/nologin --group user-rw
id -u user-ro &>/dev/null || adduser --system --shell /usr/sbin/nologin --group user-ro

RW_UID=$(id -u user-rw)
RW_GID=$(id -g user-rw)

usermod -aG docker teldrivefs
usermod -aG docker $USER_RUNNING_SCRIPT
usermod -aG teldrivefs $USER_RUNNING_SCRIPT
echo "--- Phase 2: Done ---"

echo "--- Phase 3: Directory Structure ---"
mkdir -p /opt/teldrivefs /etc/teldrivefs /var/lib/teldrivefs/vfs /mnt/teldrivefs
chown -R teldrivefs:teldrivefs /opt/teldrivefs /var/lib/teldrivefs /mnt/teldrivefs /etc/teldrivefs
chmod -R 775 /opt/teldrivefs /var/lib/teldrivefs /mnt/teldrivefs
chmod 750 /etc/teldrivefs
echo "--- Phase 3: Done ---"

echo "--- Phase 4: Secrets & Configs ---"
JWT_SECRET=$(openssl rand -hex 64)
ENC_KEY=$(openssl rand -base64 32)
echo "JWT sectet: $JWT_SECRET"
echo "Encryption key: $ENC_KEY"
echo "Save these secrets, if you lose them, you lose access to teldrive!"
read -p "Press [Enter] when done..."
read -p "Enter your Telegram Username (handle without @): " TG_USER

# Create config.toml
cat <<EOF > /etc/teldrivefs/config.toml
[db]
data-source = "postgres://teldrive:secret@postgres/postgres"

[jwt]
allowed-users = ["$TG_USER"]
secret = "$JWT_SECRET"

[tg.uploads]
encryption-key = "$ENC_KEY"
EOF
chown teldrivefs:teldrivefs /etc/teldrivefs/config.toml
chmod 640 /etc/teldrivefs/config.toml

# Create rclone.conf
cat <<EOF > /etc/teldrivefs/rclone.conf
[teldrive]
type = teldrive
api_host = http://localhost:8080/
access_token = 
chunk_size = 500M
upload_concurrency = 4
encrypt_files = true
random_chunk_name = true

[hasher]
type = hasher
remote = teldrive:
hashes = teldrive
max_age = off
EOF
chown teldrivefs:teldrivefs /etc/teldrivefs/rclone.conf
chmod 640 /etc/teldrivefs/rclone.conf
echo "--- Phase 4: Done ---"

echo "--- Phase 5: Docker Setup ---"
docker network create postgres 2>/dev/null || true
docker volume create postgres_data 2>/dev/null || true

cat <<EOF > /opt/teldrivefs/docker-compose.yml
services:
  postgres:
    image: groonga/pgroonga:latest-alpine-17
    container_name: postgres_db
    restart: always
    networks:
     - postgres
    environment:
      - POSTGRES_USER=teldrive
      - POSTGRES_PASSWORD=secret
      - POSTGRES_DB=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

  teldrive:
    image: ghcr.io/tgdrive/teldrive
    restart: always
    container_name: teldrive
    networks:
     - postgres
    volumes:
      - /etc/teldrivefs/config.toml:/config.toml
    ports:
      - 8080:8080

networks:
  postgres:
    external: true

volumes:
  postgres_data:
    external: true
EOF
echo "--- Phase 5: Done ---"

echo "--- Phase 6: Systemd Services ---"
cat <<EOF > /etc/systemd/system/teldrivefs-docker.service
[Unit]
Description=Teldrive Docker Compose Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/teldrivefs
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=teldrivefs
Group=teldrivefs

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/teldrivefs-rclone.service
[Unit]
Description=Rclone Mount for Teldrive
Requires=teldrivefs-docker.service
After=teldrivefs-docker.service network-online.target

[Service]
Type=simple
User=teldrivefs
Group=teldrivefs
ExecStart=/usr/bin/rclone mount hasher:teldrivefs /mnt/teldrivefs \\
    --config /etc/teldrivefs/rclone.conf \\
    --uid ${RW_UID} \\
    --gid ${RW_GID} \\
    --dir-perms 0775 \\
    --file-perms 0664 \\
    --vfs-cache-mode full \\
    --vfs-cache-max-age 24h \\
    --vfs-cache-max-size 20G \\
    --vfs-write-back 10s \\
    --allow-other \\
    --allow-non-empty \\
    --delete-before \\
    --teldrive-hash-enabled=false \\
    --cache-dir /var/lib/teldrivefs/vfs \\
    --log-level NOTICE

ExecStop=/bin/fusermount -u /mnt/teldrivefs
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "Pulling docker images and starting teldrive..."
systemctl daemon-reload
systemctl enable teldrivefs-docker
systemctl start teldrivefs-docker
echo "--- Phase 6: Done ---"

echo "--- Phase 7: Interactive Setup ---"
IP_ADDR=$(hostname -I | awk '{print $1}')
echo "1. Teldrive is initializing..."
echo "2. Open http://$IP_ADDR:8080 in your browser. Login to your telegram account."
read -p "Press [Enter] when done..."
echo "3. Login, go to Settings -> Account, then refresh the channels and select the right one."
read -p "Press [Enter] when done..."
echo "4. After selecting the channel, add at least 1 telegram bot."
read -p "Press [Enter] when done..."
echo "5. Create a folder in My Drive and name it teldrivefs."
read -p "Press [Enter] when done..."
echo "6. Press F12, go to network, reload the page, go to session and copy the session token."
read -p "Once you have the token, paste it here: " TELD_TOKEN

awk -v token="$TELD_TOKEN" '/^access_token =/ {$0 = "access_token = " token} 1' /etc/teldrivefs/rclone.conf > /etc/teldrivefs/rclone.conf.tmp && mv /etc/teldrivefs/rclone.conf.tmp /etc/teldrivefs/rclone.conf

chown teldrivefs:teldrivefs /etc/teldrivefs/rclone.conf
chmod 640 /etc/teldrivefs/rclone.conf

echo "Starting Rclone Mount..."
systemctl enable teldrivefs-rclone
systemctl start teldrivefs-rclone
echo "--- Phase 7: Done ---"

echo "--- Phase 8: Samba Configuration ---"
# Create dfree script
cat <<'EOF' > /opt/teldrivefs/dfree.sh
#!/bin/bash
# --- CONFIGURATION (in GB) ---
# How much space should samba let users write on
CAP_GB=20
# -----------------------------
# Conversion factor
BLOCKS_PER_GB=$((1024 * 1024))
CAP_KB=$((CAP_GB * BLOCKS_PER_GB))
read total_kb free_kb <<< $(df -B 1024 --output=size,avail / | tail -1)
# Logic: Report the smaller of the two (Reality vs Cap)
if [ "$free_kb" -lt "$CAP_KB" ]; then
    reported_free=$free_kb
else
    reported_free=$CAP_KB
fi
# Output for Samba
echo "$total_kb $reported_free"
EOF
chmod +x /opt/teldrivefs/dfree.sh

# Function to set samba password
set_smb_password() {
    local user=$1
    echo "Set password for Samba user: $user (Press Enter to use '$user' as default)"
    stty -echo
    read -p "Password: " PASS
    stty echo
    echo
    [ -z "$PASS" ] && PASS=$user
    (echo "$PASS"; echo "$PASS") | smbpasswd -s -a "$user"
}
set_smb_password "user-rw"
set_smb_password "user-ro"

# Configure smb.conf
cat <<EOF > /etc/samba/smb.conf
[global]
    server role = standalone server
    workgroup = WORKGROUP
    logging = syslog
    passdb backend = tdbsam

[teldrivefs]
    path = /mnt/teldrivefs
    browseable = yes
    dfree command = /opt/teldrivefs/dfree.sh
    read only = no
    force user = user-rw
    valid users = user-rw user-ro
    write list = user-rw
    create mask = 0644
    directory mask = 0755
    kernel oplocks = no
    kernel share modes = no
    posix locking = no
    nt acl support = no
    ea support = no
    vfs objects = catia
EOF

# Setup Service Dependencies
mkdir -p /etc/systemd/system/smbd.service.d
cat <<EOF > /etc/systemd/system/smbd.service.d/override.conf
[Unit]
BindsTo=teldrivefs-rclone.service
After=teldrivefs-rclone.service
EOF

systemctl daemon-reload
systemctl restart smbd
systemctl enable smbd nmbd
systemctl disable samba
systemctl start smbd nmbd
echo "--- Phase 8: Done ---"

echo "--- Phase 9: Finalizing Permissions ---"
chown -R teldrivefs:teldrivefs /opt/teldrivefs /var/lib/teldrivefs /mnt/teldrivefs /etc/teldrivefs
chmod 750 /etc/teldrivefs
chmod 640 /etc/teldrivefs/config.toml /etc/teldrivefs/rclone.conf
echo "--- Phase 9: Done ---"

echo "--- Phase 10: Organizing /opt/teldrivefs ---"

# Create symlinks to all configuration and service files
mkdir -p /opt/teldrivefs/symlinks
ln -sf /etc/teldrivefs/config.toml /opt/teldrivefs/symlinks/config.toml
ln -sf /etc/teldrivefs/rclone.conf /opt/teldrivefs/symlinks/rclone.conf
ln -sf /etc/samba/smb.conf /opt/teldrivefs/symlinks/smb.conf
ln -sf /etc/systemd/system/teldrivefs-docker.service /opt/teldrivefs/symlinks/teldrivefs-docker.service
ln -sf /etc/systemd/system/teldrivefs-rclone.service /opt/teldrivefs/symlinks/teldrivefs-rclone.service
ln -sf /var/lib/teldrivefs/vfs /opt/teldrivefs/symlinks/vfs

chown -R teldrivefs:teldrivefs /opt/teldrivefs/symlinks
chown -h teldrivefs:teldrivefs /opt/teldrivefs/symlinks/*
echo "--- Phase 10: Done ---"

echo "--- Setup Complete! ---"
echo "Make sure to save your config.toml secrets!"
echo "Please logout and login for group changes to take effect."
