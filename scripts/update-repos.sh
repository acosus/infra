#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <repository>"
    exit 1
fi

REPO=$1

echo "Updating $REPO..."

if [ -d "/var/www/acosus/$REPO" ]; then
    cd "/var/www/acosus/$REPO"
    git pull origin main
else
    cd /var/www/acosus
    git clone "git@github.com:acosus/$REPO.git"
fi