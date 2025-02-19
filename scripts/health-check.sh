#!/bin/bash

# Check container health
docker ps -a --format "{{.Names}}: {{.Status}}" | \
while read container; do
    if [[ $container != *"Up"* ]]; then
        echo "Container $container is not running!"
    fi
done

# Check SSL certificate expiration
CERT_FILE="/var/www/acosus/ssl/certificate.crt"
EXPIRY=$(openssl x509 -enddate -noout -in $CERT_FILE | cut -d= -f2)
EXPIRY_TS=$(date -d "$EXPIRY" +%s)
NOW_TS=$(date +%s)
DAYS_LEFT=$(( ($EXPIRY_TS - $NOW_TS) / 86400 ))

if [ $DAYS_LEFT -lt 30 ]; then
    echo "SSL certificate will expire in $DAYS_LEFT days!"
fi