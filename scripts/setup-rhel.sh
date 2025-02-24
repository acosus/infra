#!/bin/bash

# Validate arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <github_pat>"
    exit 1
fi

GITHUB_PAT=$1

# Default configurations if not provided in environment
: "${PROJECT_ROOT:=/var/www/acosus}"
: "${LOCAL_DIRS:=ssl,logs,backups,docker,scripts}"
: "${INSTALL_DEPS:=curl,git,jq}"
: "${INSTALL_CERTBOT:=false}"
: "${INSTALL_FIREWALL:=true}"
: "${INSTALL_DOCKER:=true}"
: "${GITHUB_OWNER:=acosus}"
: "${GITHUB_REPO:=infra}"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a package is installed
is_package_installed() {
    if rpm -q "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get server IP
get_server_ip() {
    local ip=""
    if command -v curl &> /dev/null; then
        ip=$(curl -s ifconfig.me)
    elif command -v wget &> /dev/null; then
        ip=$(wget -qO- ifconfig.me)
    else
        ip=$(hostname -I | awk '{print $1}')
    fi
    echo "$ip"
}

# Function to fetch secret from GitHub
fetch_github_secret() {
    local secret_name=$1
    local response=$(curl -s -H "Authorization: token $GITHUB_PAT" \
        "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/actions/secrets/$secret_name")
    
    if echo "$response" | jq -e '.message' > /dev/null; then
        log "Error fetching secret $secret_name: $(echo "$response" | jq -r '.message')"
        return 1
    fi
    
    echo "$response"
}

# Function to fetch all required secrets
fetch_required_secrets() {
    log "Fetching required secrets from GitHub..."
    
    # Fetch SSH authorized key
    SSH_AUTHORIZED_KEY=$(fetch_github_secret "SSH_AUTHORIZED_KEY")
    if [ $? -ne 0 ]; then
        log "Failed to fetch SSH_AUTHORIZED_KEY"
        return 1
    fi
    
    # Fetch Resend API key
    RESEND_API_KEY=$(fetch_github_secret "RESEND_API_KEY")
    if [ $? -ne 0 ]; then
        log "Failed to fetch RESEND_API_KEY"
        return 1
    fi
    
    # Fetch notification email
    NOTIFICATION_EMAIL=$(fetch_github_secret "NOTIFICATION_EMAIL")
    if [ $? -ne 0 ]; then
        log "Failed to fetch NOTIFICATION_EMAIL"
        return 1
    fi 
}


# Function to check if a service is installed and running
is_service_running() {
    if systemctl is-active --quiet "$1"; then
        return 0
    else
        return 1
    fi
}

# Function to send email notification using Resend API
send_notification() {
    local subject="$1"
    local content="$2"
    
    curl -X POST 'https://api.resend.com/emails' \
     -H "Authorization: Bearer $RESEND_API_KEY" \
     -H 'Content-Type: application/json' \
     -d "{
        \"from\": \"delivered@resend.dev\",
        \"to\": \"$NOTIFICATION_EMAIL\",
        \"subject\": \"$subject\",
        \"html\": \"$content\"
     }"
}

# Function to setup deploy user
setup_deploy_user() {
    log "Setting up deploy user..."
    
    # Create deploy user if it doesn't exist
    if ! id -u deploy &>/dev/null; then
        sudo useradd -m -s /bin/bash deploy
        log "Created deploy user"
    fi

    # Setup SSH directory with correct permissions
    sudo mkdir -p /home/deploy/.ssh
    sudo chmod 700 /home/deploy/.ssh
    sudo chown -R deploy:deploy /home/deploy/.ssh

    # Add authorized key
    echo "$SSH_AUTHORIZED_KEY" | sudo -u deploy tee /home/deploy/.ssh/authorized_keys > /dev/null
    sudo chmod 600 /home/deploy/.ssh/authorized_keys

    # Output server information
    local server_ip=$(get_server_ip)
    echo -e "\n=== Server Deployment Information ==="
    echo "Add these secrets to your GitHub repositories:"
    echo -e "\nSERVER_IP=$server_ip"
    echo "SERVER_USER=deploy"
    echo "==================================="  
}

# Function to install system packages
install_system_packages() {
    log "Checking and installing system packages..."
    
    # Enable EPEL repository if needed
    if ! is_package_installed "epel-release" && [[ "$INSTALL_DEPS" == *"epel-release"* ]]; then
        sudo subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
        sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    fi
    
    # Install base dependencies
    IFS=',' read -ra DEPS <<< "$INSTALL_DEPS"
    for package in "${DEPS[@]}"; do
        if ! is_package_installed "$package"; then
            sudo dnf install -y "$package"
            log "Installed $package"
        else
            log "$package is already installed"
        fi
    done
    
    # Install certbot if requested
    if [ "${INSTALL_CERTBOT}" = "true" ]; then
        if ! is_package_installed "certbot"; then
            sudo dnf install -y certbot python3-certbot-nginx
            log "Installed certbot"
        fi
    fi
    
    # Install and configure firewall if requested
    if [ "${INSTALL_FIREWALL}" = "true" ]; then
        if ! is_package_installed "firewalld"; then
            sudo dnf install -y firewalld
            log "Installed firewalld"
        fi
        
        if ! is_service_running "firewalld"; then
            sudo systemctl enable firewalld
            sudo systemctl start firewalld
            log "Started firewalld service"
        fi
        
        # Configure firewall
        sudo firewall-cmd --permanent --add-port=80/tcp
        sudo firewall-cmd --permanent --add-port=443/tcp
        sudo firewall-cmd --reload
        log "Configured firewall ports"
    fi
    
    # Install Docker if requested
    if [ "${INSTALL_DOCKER}" = "true" ]; then
        if ! command -v docker &> /dev/null; then
            sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            log "Installed Docker"
            
            # Add deploy user to docker group
            sudo usermod -aG docker deploy
            log "Added deploy user to docker group"
            
            sudo systemctl enable docker
            sudo systemctl start docker
            log "Started Docker service"
        else
            log "Docker is already installed"
            
            if ! is_service_running "docker"; then
                sudo systemctl enable docker
                sudo systemctl start docker
                log "Started Docker service"
            fi
        fi
    fi
}

# Function to create project directories
create_project_structure() {
    log "Creating project structure..."
    
    # Create base project directory
    sudo mkdir -p "$PROJECT_ROOT"
    
    # Create local directories
    IFS=',' read -ra DIRS <<< "$LOCAL_DIRS"
    for dir in "${DIRS[@]}"; do
        sudo mkdir -p "$PROJECT_ROOT/$dir"
        log "Created directory: $dir"
    done
    
    # Set permissions
    sudo chown -R deploy:deploy "$PROJECT_ROOT"
    sudo chmod 755 "$PROJECT_ROOT"
}

# Function to clone/update infrastructure repository
setup_infra_repo() {
    log "Setting up infrastructure repository..."
    
    if [ ! -d "$PROJECT_ROOT" ]; then
        log "Error: Project root directory does not exist"
        return 1
    fi
    
    # Switch to deploy user for git operations
    sudo -u deploy bash << EOF
        cd "$PROJECT_ROOT"
        if [ -d "infra" ]; then
            cd infra
            git pull origin main
        else
            git clone https://github.com/acosus/infra.git infra
        fi
EOF
    # Source VALID_SERVICES from .env.example
    if [ -f "$PROJECT_ROOT/infra/.env.example" ]; then
        sudo -u deploy cp "$PROJECT_ROOT/infra/.env.example" "$PROJECT_ROOT/.env"
        # Export variables from .env file
        export $(sudo -u deploy cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
    else
        log "Error: .env.example not found in infra repository"
        return 1
    fi
}

# Function to setup SSH configuration
setup_ssh_config() {
    log "Setting up SSH configuration..."
    
    # Must be run after infra repo is cloned and VALID_SERVICES is available
    if [ -z "$VALID_SERVICES" ]; then
        log "Error: VALID_SERVICES not defined"
        return 1
    fi
    
    # Generate SSH keys and configure
    local keys_content="<h2>Deploy Keys</h2><ul>"
    IFS=',' read -ra SERVICES <<< "$VALID_SERVICES"
    SERVICES+=("infra")
    
    for service in "${SERVICES[@]}"; do
        sudo -u deploy bash << EOF
            if [ ! -f "/home/deploy/.ssh/$service" ]; then
                ssh-keygen -t ed25519 -C "$service@acosus" -f "/home/deploy/.ssh/$service" -N ""
            fi
EOF
        keys_content+="<li><strong>$service</strong>:<br><pre>$(sudo cat /home/deploy/.ssh/$service.pub)</pre></li>"
    done
    keys_content+="</ul>"
    
    # Setup SSH config
    local ssh_config="/home/deploy/.ssh/config"
    sudo -u deploy touch "$ssh_config"
    
    for service in "${SERVICES[@]}"; do
        if ! grep -q "github.com-$service" "$ssh_config"; then
            echo "
Host github.com-$service
    HostName github.com
    User git
    IdentityFile ~/.ssh/$service
    IdentitiesOnly yes" | sudo -u deploy tee -a "$ssh_config"
        fi
    done
    
    sudo chmod 600 "$ssh_config"
    
    # Send notification with deploy keys
    send_notification "ACOSUS Deploy Keys" "$keys_content"
}

# Main execution
main() {
    log "Starting RHEL server setup..."

    # Fetch required secrets first
    fetch_required_secrets || exit 1
    
    # Install system packages first
    install_system_packages
    
    # Setup deploy user
    setup_deploy_user
    
    # Create project structure
    create_project_structure
    
    # Setup infra repository
    setup_infra_repo
    
    # Setup SSH configuration
    setup_ssh_config
    
    # Run init and config scripts if they exist
    if [ -f "$PROJECT_ROOT/scripts/init.sh" ]; then
        sudo -u deploy "$PROJECT_ROOT/scripts/init.sh"
    fi
    
    if [ -f "$PROJECT_ROOT/scripts/config.sh" ]; then
        sudo -u deploy "$PROJECT_ROOT/scripts/config.sh" "$GITHUB_PAT"
    fi
    
    log "RHEL server setup completed successfully"
    log "Please check the console output for deployment information"
}

main