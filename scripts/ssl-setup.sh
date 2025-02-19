#!/bin/bash

# Create SSL directory
mkdir -p /var/www/acosus/ssl
cd /var/www/acosus/ssl

# Generate initial self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout private.key \
    -out certificate.crt \
    -subj "/CN=$(curl -s ifconfig.me)"

chmod 600 private.key
chmod 644 certificate.crt

# If domain is provided, get Let's Encrypt certificate
if [ ! -z "$DOMAIN" ]; then
    certbot certonly --standalone \
        --preferred-challenges http \
        --agree-tos \
        --email $EMAIL \
        -d $DOMAIN
        
    # Copy Let's Encrypt certificates
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem certificate.crt
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem private.key
fi

# Set up auto-renewal
# echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -