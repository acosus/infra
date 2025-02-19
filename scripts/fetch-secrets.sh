#!/bin/bash

# Get directory of the script and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Validate arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <deploy_token> <owner> <service_name>"
    echo "Example: $0 token123 myuser frontend"
    exit 1
fi

# Load and validate environment configuration
CONFIG_FILE="$PROJECT_ROOT/.env"
if [ ! -f "$CONFIG_FILE" ]; then
    log "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Source the config file
source "$CONFIG_FILE"

DEPLOY_TOKEN=$1
OWNER=$2
SERVICE_NAME=$3

# Validate service name against VALID_SERVICES
IFS=',' read -ra VALID_SERVICES_ARR <<< "$VALID_SERVICES"
VALID_SERVICE=false
for service in "${VALID_SERVICES_ARR[@]}"; do
    if [ "$service" == "$SERVICE_NAME" ]; then
        VALID_SERVICE=true
        break
    fi
done

if [ "$VALID_SERVICE" = false ]; then
    log "Error: Invalid service name '$SERVICE_NAME'"
    log "Valid services are: $VALID_SERVICES"
    exit 1
fi

log "Fetching all secrets and variables for $SERVICE_NAME..."

# Get all environment secrets
secrets_response=$(curl -s -H "Authorization: token $DEPLOY_TOKEN" \
    "https://api.github.com/repos/$OWNER/infra/environments/$SERVICE_NAME/secrets")

# Get all environment variables
variables_response=$(curl -s -H "Authorization: token $DEPLOY_TOKEN" \
    "https://api.github.com/repos/$OWNER/infra/environments/$SERVICE_NAME/variables")

# Check for API errors in secrets response
if echo "$secrets_response" | jq -e '.message' > /dev/null; then
    log "Error fetching secrets: $(echo "$secrets_response" | jq -r '.message')"
    exit 1
fi

# Check for API errors in variables response
if echo "$variables_response" | jq -e '.message' > /dev/null; then
    log "Error fetching variables: $(echo "$variables_response" | jq -r '.message')"
    exit 1
fi

# Create the .env file in the appropriate service directory
ENV_DIR="/var/www/acosus/$SERVICE_NAME"
ENV_FILE="$ENV_DIR/.env"

# Ensure directory exists
mkdir -p "$ENV_DIR"

# Create new .env file with timestamp
echo "# Generated $(date)" > "$ENV_FILE"
echo "# WARNING: Auto-generated file - Do not edit directly" >> "$ENV_FILE"
echo "" >> "$ENV_FILE"

# Write all secrets and variables to the file
echo "$secrets_response" | jq -r '.secrets[] | select(.name != null and .value != null) | .name + "=" + .value' >> "$ENV_FILE"
echo "$variables_response" | jq -r '.variables[] | select(.name != null and .value != null) | .name + "=" + .value' >> "$ENV_FILE"

# Set proper permissions
chmod 600 "$ENV_FILE"

# Count fetched items
secret_count=$(echo "$secrets_response" | jq '.secrets | length')
variable_count=$(echo "$variables_response" | jq '.variables | length')

log "Successfully fetched and saved:"
log "- $secret_count secrets"
log "- $variable_count variables"
log "Environment file saved to: $ENV_FILE"

# Verify the file was created and has content
if [ ! -s "$ENV_FILE" ]; then
    log "Warning: .env file is empty. Please verify your secrets and variables exist in GitHub."
    exit 1
fi