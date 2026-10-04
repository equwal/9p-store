#!/bin/sh
# Install a disk-backed 9P file server (diod) on Debian/Ubuntu.
# Usage: LISTEN_ADDR=<private-ip> ./install.sh
#   LISTEN_ADDR  private address to serve on (for example a WireGuard address). Required.
#   EXPORT_DIR   directory to serve (default /srv/9pstore)
#   SQUASH_USER  account that owns every file (default 9pstore)
#   PORT         TCP port (default 564)
set -eu
: "${LISTEN_ADDR:?set LISTEN_ADDR to a private address, never a public one}"
EXPORT_DIR=${EXPORT_DIR:-/srv/9pstore}
SQUASH_USER=${SQUASH_USER:-9pstore}
PORT=${PORT:-564}

DEBIAN_FRONTEND=noninteractive apt-get install -y diod
systemctl disable --now diod 2>/dev/null || true   # Debian ships a sysv unit; use ours.
id "$SQUASH_USER" >/dev/null 2>&1 ||
  useradd -r -s /usr/sbin/nologin -d "$EXPORT_DIR" "$SQUASH_USER"
mkdir -p "$EXPORT_DIR"
chown "$SQUASH_USER": "$EXPORT_DIR"
chmod 770 "$EXPORT_DIR"

sed -e "s|@LISTEN_ADDR@|$LISTEN_ADDR|" -e "s|@EXPORT_DIR@|$EXPORT_DIR|" \
    -e "s|@SQUASH_USER@|$SQUASH_USER|" -e "s|@PORT@|$PORT|" \
    "$(dirname "$0")/9pstore.service.in" > /etc/systemd/system/9pstore.service
systemctl daemon-reload
systemctl enable --now 9pstore
ss -ltn "sport = :$PORT"
