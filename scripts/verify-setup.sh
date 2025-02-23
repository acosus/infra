#!/bin/bash

PROJECT_ROOT="/var/www/acosus"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check directory existence and permissions
check_directory() {
    local dir=$1
    local expected_owner=$2
    local expected_perms=$3
    
    if [ ! -d "$dir" ]; then
        log "ERROR: Directory not found: $dir"
        return 1
    fi
    
    local actual_owner=$(stat -c '%U:%G' "$dir")
    local actual_perms=$(stat -c '%a' "$dir")
    
    if [ "$actual_owner" != "$expected_owner" ]; then
        log "ERROR: Wrong ownership on $dir. Expected: $expected_owner, Got: $actual_owner"
        return 1
    fi
    
    if [ "$actual_perms" != "$expected_perms" ]; then
        log "ERROR: Wrong permissions on $dir. Expected: $expected_perms, Got: $actual_perms"
        return 1
    fi
    
    log "OK: Directory $dir checks passed"
    return 0
}

# Function to check file existence and permissions
check_file() {
    local file=$1
    local expected_owner=$2
    local expected_perms=$3
    
    if [ ! -f "$file" ]; then
        log "ERROR: File not found: $file"
        return 1
    fi
    
    local actual_owner=$(stat -c '%U:%G' "$file")
    local actual_perms=$(stat -c '%a' "$file")
    
    if [ "$actual_owner" != "$expected_owner" ]; then
        log "ERROR: Wrong ownership on $file. Expected: $expected_owner, Got: $actual_owner"
        return 1
    fi
    
    if [ "$actual_perms" != "$expected_perms" ]; then
        log "ERROR: Wrong permissions on $file. Expected: $expected_perms, Got: $actual_perms"
        return 1
    fi
    
    log "OK: File $file checks passed"
    return 0
}

# Function to check service status
check_service() {
    local service=$1
    
    if ! systemctl is-active --quiet "$service"; then
        log "ERROR: Service $service is not running"
        return 1
    fi
    
    log "OK: Service $service is running"
    return 0
}

# Function to check Docker container status
check_container() {
    local container=$1
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        log "ERROR: Container $container is not running"
        return 1
    fi
    
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
    if [ "$health" != "healthy" ] && [ -n "$health" ]; then
        log "ERROR: Container $container health check failed: $health"
        return 1
    fi
    
    log "OK: Container $container is running and healthy"
    return 0
}

# Function to check repository setup
check_repository() {
    local repo=$1
    
    if [ ! -d "$PROJECT_ROOT/$repo/.git" ]; then
        log "ERROR: Repository $repo is not properly cloned"
        return 1
    fi
    
    if [ ! -f "$PROJECT_ROOT/$repo/.env" ]; then
        log "ERROR: Repository $repo is missing .env file"
        return 1
    fi
    
    log "OK: Repository $repo is properly setup"
    return 0
}

# Function to check SSH configuration
check_ssh_config() {
    local ssh_dir="/home/deploy/.ssh"
    local config_file="$ssh_dir/config"
    
    # Check SSH directory permissions
    check_directory "$ssh_dir" "deploy:deploy" "700" || return 1
    
    # Check SSH config file
    check_file "$config_file" "deploy:deploy" "600" || return 1
    
    # Source VALID_SERVICES
    source "$PROJECT_ROOT/.env"
    
    # Check SSH keys for each service
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    SERVICES+=("infra")
    
    for service in "${SERVICES[@]}"; do
        if [ ! -f "$ssh_dir/$service" ]; then
            log "ERROR: SSH key missing for $service"
            return 1
        fi
        check_file "$ssh_dir/$service" "deploy:deploy" "600" || return 1
        check_file "$ssh_dir/$service.pub" "deploy:deploy" "644" || return 1
    done
    
    log "OK: SSH configuration is correct"
    return 0
}

# Main verification function
main() {
    local errors=0
    
    log "Starting setup verification..."
    
    # Check base directories
    for dir in "" "/ssl" "/logs" "/backups" "/docker" "/scripts"; do
        check_directory "$PROJECT_ROOT$dir" "deploy:deploy" "755" || ((errors++))
    done
    
    # Check services
    check_service "docker" || ((errors++))
    
    if command -v firewalld &> /dev/null; then
        check_service "firewalld" || ((errors++))
    elif command -v ufw &> /dev/null; then
        check_service "ufw" || ((errors++))
    fi
    
    # Check repositories
    source "$PROJECT_ROOT/.env"
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    for service in "${SERVICES[@]}"; do
        check_repository "$service" || ((errors++))
    done
    
    # Check SSH configuration
    check_ssh_config || ((errors++))
    
    # Check containers if they should be running
    if [ -f "$PROJECT_ROOT/docker/docker-compose.prod.yml" ]; then
        for service in "${SERVICES[@]}"; do
            check_container "acosus_${service}_1" || ((errors++))
        done
    fi
    
    # Summary
    log "Verification completed with $errors errors"
    if [ "$errors" -eq 0 ]; then
        log "All checks passed successfully"
        return 0
    else
        log "Some checks failed. Please review the logs above"
        return 1
    fi
}

main