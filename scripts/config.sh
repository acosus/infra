#!/bin/bash

# Get directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="/var/www/acosus"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate arguments
validate_args() {
    if [ "$#" -ne 1 ]; then
        log "Usage: $0 <deploy_token>"
        log "Example: $0 ghp_1234567890abcdef"
        return 1
    fi
    
    DEPLOY_TOKEN=$1
    return 0
}

# Function to validate environment
validate_environment() {
    log "Validating environment..."
    
    # Check for root .env file
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log "Error: Root .env file not found"
        return 1
    fi
    
    # Source the environment file
    source "$PROJECT_ROOT/.env"
    
    # Check required variables
    if [ -z "$VALID_SERVICES" ] || [ -z "$OWNER" ]; then
        log "Error: Required variables VALID_SERVICES or OWNER not found in .env"
        return 1
    fi
    
    return 0
}

# Function to setup service environment
setup_service_env() {
    local service=$1
    local deploy_token=$2
    
    log "Setting up environment for $service..."
    
    # Validate service directory
    if [ ! -d "$PROJECT_ROOT/$service" ]; then
        log "Error: Service directory $service not found"
        return 1
    fi
    
    # Check if service is a git repository
    if [ ! -d "$PROJECT_ROOT/$service/.git" ]; then
        log "Error: Service $service is not a git repository"
        return 1
    fi
    
    # Create/update .env file
    if [ ! -f "$PROJECT_ROOT/$service/.env" ] || \
       [ $(find "$PROJECT_ROOT/$service/.env" -mmin +1440) ]; then  # Older than 24 hours
        log "Fetching secrets for $service..."
        
        if [ -f "$PROJECT_ROOT/scripts/fetch-secrets.sh" ]; then
            "$PROJECT_ROOT/scripts/fetch-secrets.sh" "$deploy_token" "$OWNER" "$service"
            if [ $? -ne 0 ]; then
                log "Error: Failed to fetch secrets for $service"
                return 1
            fi
        else
            log "Error: fetch-secrets.sh not found"
            return 1
        fi
    else
        log "Environment file for $service is up to date"
    fi
    
    return 0
}

# Function to validate service configuration
validate_service_config() {
    local service=$1
    
    log "Validating configuration for $service..."
    
    # Check required files
    local required_files=(".env" "Dockerfile")
    for file in "${required_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$service/$file" ]; then
            log "Error: Required file $file not found in $service"
            return 1
        fi
    done
    
    # Validate .env file
    if [ ! -s "$PROJECT_ROOT/$service/.env" ]; then
        log "Error: Empty .env file in $service"
        return 1
    fi
    
    return 0
}

# Function to check service dependencies
check_dependencies() {
    local service=$1
    
    log "Checking dependencies for $service..."
    
    # Read docker-compose file
    local compose_file="$PROJECT_ROOT/docker/docker-compose.prod.yml"
    if [ ! -f "$compose_file" ]; then
        log "Error: docker-compose.prod.yml not found"
        return 1
    fi
    
    # Check if service depends on other services
    local depends_on=$(grep -A 5 "^  $service:" "$compose_file" | grep "depends_on:" -A 5 | grep -v "depends_on:" | grep "^      - " | cut -d "-" -f 2)
    
    if [ -n "$depends_on" ]; then
        log "Service $service depends on: $depends_on"
        for dep in $depends_on; do
            if [ ! -d "$PROJECT_ROOT/$dep" ] || [ ! -f "$PROJECT_ROOT/$dep/.env" ]; then
                log "Error: Dependency $dep not properly configured"
                return 1
            fi
        done
    fi
    
    return 0
}

# Main execution
main() {
    log "Starting configuration process..."
    
    # Validate arguments
    validate_args "$@" || exit 1
    
    # Check if running as deploy user
    if [ "$(id -un)" != "deploy" ]; then
        log "Error: Script must be run as 'deploy' user"
        exit 1
    fi
    
    # Validate environment
    validate_environment || exit 1
    
    # Process each service
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    for service in "${SERVICES[@]}"; do
        log "Processing service: $service"
        
        setup_service_env "$service" "$DEPLOY_TOKEN" || continue
        validate_service_config "$service" || continue
        check_dependencies "$service" || continue
        
        log "Service $service configured successfully"
    done
    
    log "Configuration completed"
}

main "$@"