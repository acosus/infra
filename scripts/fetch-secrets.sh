#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <github_token> <repository>"
    exit 1
fi

GITHUB_TOKEN=$1
REPO=$2

echo "Fetching secrets for $REPO..."

secrets=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/acosus/$REPO/environments/production/secrets")

echo "# Generated $(date)" > "/var/www/acosus/$REPO/.env"
echo "$secrets" | jq -r '.secrets[] | .name + "=" + .value' >> "/var/www/acosus/$REPO/.env"

chmod 600 "/var/www/acosus/$REPO/.env"