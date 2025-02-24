#!/bin/bash

# Get directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/var/www/acosus"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check SELinux status and fix contexts
check_selinux() {
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce)
        log "SELinux status: $selinux_status"
        
        if [ "$selinux_status" != "Disabled" ]; then
            log "Setting SELinux context for project directories"
            sudo -n semanage fcontext -a -t httpd_sys_content_t "$PROJECT_ROOT(/.*)?"
            sudo -n restorecon -Rv "$PROJECT_ROOT"
        fi
    fi
}

# Function to validate project structure
validate_structure() {
    local required_dirs=("ssl" "logs" "backups" "docker" "scripts")
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            log "Error: Required directory $dir not found"
            return 1
        fi
    done
    
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log "Error: Root .env file not found"
        return 1
    fi
    
    return 0
}

# Function to create service directories and clone repositories
clone_service_directories() {
    log "Creating service directories..."
    source "$PROJECT_ROOT/.env"
    
    if [ -z "$VALID_SERVICES" ]; then
        log "Warning: VALID_SERVICES not defined in .env"
        return 1
    fi
    
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    for service in "${SERVICES[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$service" ]; then
            log "Creating directory for service: $service"
            mkdir -p "$PROJECT_ROOT/$service"
            chmod 755 "$PROJECT_ROOT/$service"
            
            # Clone the repository using the specific SSH config
            if [ -f ~/.ssh/$service ]; then
                git clone git@github.com-$service:acosus/$service.git "$PROJECT_ROOT/$service"
                log "Cloned repository for service: $service"
            else
                log "Warning: SSH key ~/.ssh/$service not found"
            fi
        fi
    done
}

# Function to copy infra files
copy_infra_files() {
    log "Copying infrastructure files..."
    
    # Copy docker compose file if it exists and has changes
    if [ -f "$PROJECT_ROOT/infra/docker/docker-compose.prod.yml" ]; then
        if ! cmp -s "$PROJECT_ROOT/infra/docker/docker-compose.prod.yml" "$PROJECT_ROOT/docker/docker-compose.prod.yml"; then
            cp "$PROJECT_ROOT/infra/docker/docker-compose.prod.yml" "$PROJECT_ROOT/docker/"
            log "Updated docker-compose.prod.yml"
        fi
    else
        log "Error: docker-compose.prod.yml not found in infra repository"
        return 1
    fi
    
    # Copy and make scripts executable
    if [ -d "$PROJECT_ROOT/infra/scripts" ]; then
        for script in "$PROJECT_ROOT/infra/scripts"/*; do
            if [ -f "$script" ]; then
                local script_name=$(basename "$script")
                if [ ! -f "$PROJECT_ROOT/scripts/$script_name" ] || \
                   ! cmp -s "$script" "$PROJECT_ROOT/scripts/$script_name"; then
                    cp "$script" "$PROJECT_ROOT/scripts/"
                    chmod +x "$PROJECT_ROOT/scripts/$script_name"
                    log "Updated script: $script_name"
                fi
            fi
        done
    else
        log "Error: Scripts directory not found in infra repository"
        return 1
    fi
}

# Function to setup SSL if not already configured
setup_ssl() {
    log "Checking SSL configuration..."
    
    if [ ! -f "$PROJECT_ROOT/ssl/certificate.crt" ] || \
       [ ! -f "$PROJECT_ROOT/ssl/private.key" ]; then
        if [ -f "$PROJECT_ROOT/scripts/ssl-setup.sh" ]; then
            log "Running SSL setup..."
            "$PROJECT_ROOT/scripts/ssl-setup.sh"
        else
            log "Error: ssl-setup.sh script not found"
            return 1
        fi
    fi
}

# Function to validate services
validate_services() {
    log "Validating services..."
    
    # Source the environment file
    source "$PROJECT_ROOT/.env"
    
    if [ -z "$VALID_SERVICES" ]; then
        log "Error: VALID_SERVICES not defined in .env"
        return 1
    fi
    
    # Check each service directory
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    for service in "${SERVICES[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$service" ]; then
            log "Warning: Service directory $service not found"
        elif [ ! -d "$PROJECT_ROOT/$service/.git" ]; then
            log "Warning: Service $service is not a git repository"
        fi
    done
}

# Function to setup logging
setup_logging() {
    log "Setting up logging configuration..."
    
    # Create logrotate configuration using sudo -n (non-interactive)
    if [ ! -f "/etc/logrotate.d/acosus" ]; then
        # Check if we have passwordless sudo for this specific command
        if sudo -n true 2>/dev/null; then
            log "Creating logrotate configuration..."
            sudo -n tee /etc/logrotate.d/acosus > /dev/null << EOL
/var/www/acosus/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 deploy deploy
}
EOL
            log "Created logrotate configuration"
        else
            log "Warning: Cannot create logrotate configuration - sudo password required"
            log "Please run: sudo tee /etc/logrotate.d/acosus > /dev/null << EOL
/var/www/acosus/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 deploy deploy
}
EOL"
        fi
    fi
}

# Main execution
main() {
    log "Starting initialization process..."
    
    # Check if running as deploy user
    if [ "$(id -un)" != "deploy" ]; then
        log "Error: Script must be run as 'deploy' user"
        exit 1
    fi
    
    # Validate project structure
    validate_structure || exit 1

    # Create service directories
    clone_service_directories || exit 1
    
    # Copy infrastructure files
    copy_infra_files || exit 1
    
    # Setup SSL
    # setup_ssl || exit 1
    
    # Validate services
    # validate_services
    
    # Setup logging
    setup_logging
    
    log "Initialization completed successfully"
}

main