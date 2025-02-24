#!/bin/bash

PROJECT_ROOT="/var/www/acosus"
LOG_FILE="$PROJECT_ROOT/logs/health-check.log"

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
            if ! sudo -n semanage fcontext -l | grep -q "$PROJECT_ROOT"; then
                log "Warning: SELinux context not set for $PROJECT_ROOT"
            fi
        fi
    fi
}

# Function to check container health
check_containers() {
    log "Checking container status..."
    local unhealthy_containers=0
    
    docker ps -a --format "{{.Names}}|{{.Status}}" | while IFS='|' read -r name status; do
        if [[ $status != *"Up"* ]]; then
            log "Error: Container $name is not running (Status: $status)"
            ((unhealthy_containers++))
        else
            log "Container $name is running properly"
        fi
    done
    
    if [ $unhealthy_containers -eq 0 ]; then
        log "All containers are running properly"
    else
        log "Found $unhealthy_containers unhealthy containers"
    fi
}

# Function to check SSL certificates
check_ssl() {
    log "Checking SSL certificates..."
    
    CERT_FILE="$PROJECT_ROOT/ssl/certificate.crt"
    if [ ! -f "$CERT_FILE" ]; then
        log "Error: SSL certificate not found at $CERT_FILE"
        return 1
    fi
    
    # Check certificate expiration
    local EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
    local EXPIRY_TS=$(date -d "$EXPIRY" +%s)
    local NOW_TS=$(date +%s)
    local DAYS_LEFT=$(( ($EXPIRY_TS - $NOW_TS) / 86400 ))
    
    if [ $DAYS_LEFT -lt 30 ]; then
        log "Warning: SSL certificate will expire in $DAYS_LEFT days!"
        if [ $DAYS_LEFT -lt 7 ]; then
            log "Critical: SSL certificate expiration imminent!"
        fi
    else
        log "SSL certificate is valid for $DAYS_LEFT more days"
    fi
    
    # Check certificate permissions
    local CERT_PERMS=$(stat -c "%a" "$CERT_FILE")
    if [ "$CERT_PERMS" != "644" ]; then
        log "Warning: SSL certificate has incorrect permissions: $CERT_PERMS (should be 644)"
    fi
}

# Function to check disk space
check_disk_space() {
    log "Checking disk space..."
    
    local threshold=90
    local disk_usage=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt "$threshold" ]; then
        log "Warning: Disk usage is at ${disk_usage}% (threshold: ${threshold}%)"
    else
        log "Disk usage is at ${disk_usage}% (OK)"
    fi
}

# Function to check backup status
check_backups() {
    log "Checking backup status..."
    
    local backup_dir="$PROJECT_ROOT/backups"
    local latest_backup=$(ls -t "$backup_dir" 2>/dev/null | head -n1)
    
    if [ -z "$latest_backup" ]; then
        log "Error: No backups found in $backup_dir"
    else
        local backup_age=$(( ( $(date +%s) - $(date -r "$backup_dir/$latest_backup" +%s) ) / 86400 ))
        if [ "$backup_age" -gt 1 ]; then
            log "Warning: Latest backup is $backup_age days old"
        else
            log "Latest backup is from $latest_backup (OK)"
        fi
    fi
}

# Main execution
main() {
    log "Starting health check..."
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check SELinux status
    check_selinux
    
    # Run all checks
    check_containers
    check_ssl
    check_disk_space
    check_backups
    
    log "Health check completed"
}

main