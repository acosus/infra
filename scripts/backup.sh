#!/bin/bash

BACKUP_DIR="/var/www/acosus/backups/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup SSL certificates
tar -czf $BACKUP_DIR/ssl.tar.gz /var/www/acosus/ssl/

# Backup environment files
tar -czf $BACKUP_DIR/env.tar.gz /var/www/acosus/*/.env

# Rotate backups (keep last 7 days)
find /var/www/acosus/backups -type d -mtime +7 -exec rm -rf {} +