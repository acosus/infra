#!/bin/bash

PROJECT_ROOT="/var/www/acosus"
BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="$PROJECT_ROOT/backups/$BACKUP_DATE"
LOG_FILE="$PROJECT_ROOT/logs/backup.log"

# Function to log with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Function to check SELinux status
check_selinux() {
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce)
        log "SELinux status: $selinux_status"
        
        if [ "$selinux_status" != "Disabled" ]; then
            # Ensure backup directory has correct context
            sudo -n semanage fcontext -a -t httpd_sys_content_t "$PROJECT_ROOT/backups(/.*)?"
            sudo -n restorecon -Rv "$PROJECT_ROOT/backups"
        fi
    fi
}

# Function to create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    
    if ! mkdir -p "$BACKUP_DIR"; then
        log "Error: Failed to create backup directory"
        return 1
    fi
    
    # Set appropriate permissions
    chmod 700 "$BACKUP_DIR"
}

# Function to backup SSL certificates
backup_ssl() {
    log "Backing up SSL certificates..."
    
    local ssl_dir="$PROJECT_ROOT/ssl"
    if [ ! -d "$ssl_dir" ]; then
        log "Error: SSL directory not found"
        return 1
    fi
    
    if ! tar -czf "$BACKUP_DIR/ssl.tar.gz" -C "$PROJECT_ROOT" "ssl/"; then
        log "Error: Failed to backup SSL certificates"
        return 1
    fi
    
    log "SSL certificates backed up successfully"
}

# Function to backup environment files
backup_env_files() {
    log "Backing up environment files..."
    
    # Get list of all .env files
    local env_files=$(find "$PROJECT_ROOT" -name ".env" -type f)
    if [ -z "$env_files" ]; then
        log "Warning: No .env files found"
        return 0
    fi
    
    if ! tar -czf "$BACKUP_DIR/env.tar.gz" $env_files; then
        log "Error: Failed to backup environment files"
        return 1
    fi
    
    log "Environment files backed up successfully"
}

# Function to backup database dumps if they exist
backup_databases() {
    log "Checking for database dumps..."
    
    local dumps_dir="$PROJECT_ROOT/backups/db"
    if [ -d "$dumps_dir" ]; then
        if ! tar -czf "$BACKUP_DIR/db.tar.gz" -C "$PROJECT_ROOT/backups" "db/"; then
            log "Error: Failed to backup database dumps"
            return 1
        fi
        log "Database dumps backed up successfully"
    else
        log "No database dumps directory found, skipping"
    fi
}

# Function to rotate old backups
rotate_backups() {
    log "Rotating old backups..."
    
    local retention_days=7
    local old_backups=$(find "$PROJECT_ROOT/backups" -maxdepth 1 -type d -mtime +$retention_days)
    
    if [ -n "$old_backups" ]; then
        echo "$old_backups" | while read -r backup; do
            log "Removing old backup: $backup"
            rm -rf "$backup"
        done
    else
        log "No old backups to rotate"
    fi
}

# Function to verify backup integrity
verify_backup() {
    log "Verifying backup integrity..."
    
    local failed=0
    
    # Check each backup file
    for backup in "$BACKUP_DIR"/*.tar.gz; do
        if ! tar -tzf "$backup" >/dev/null 2>&1; then
            log "Error: Backup file $backup is corrupted"
            ((failed++))
        fi
    done
    
    if [ $failed -eq 0 ]; then
        log "All backup files verified successfully"
        return 0
    else
        log "Error: $failed backup files failed verification"
        return 1
    fi
}

# Main execution
main() {
    log "Starting backup process..."
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check SELinux status
    check_selinux
    
    # Create backup directory
    create_backup_dir || exit 1
    
    # Perform backups
    backup_ssl
    backup_env_files
    backup_databases
    
    # Verify backups
    verify_backup
    
    # Rotate old backups
    rotate_backups
    
    log "Backup process completed"
}

main