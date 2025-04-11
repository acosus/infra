#!/bin/bash

# SSL Certificate Generation for IP Address
# This script generates self-signed certificates for development/testing

# Variables
SSL_DIR="ssl"    # Directory to store SSL certificates
IP_ADDRESS="$1"  # Pass IP address as first argument
# Set IP_ADDRESS to localhost if not provided
if [ -z "$IP_ADDRESS" ]; then
    IP_ADDRESS="localhost"
fi
DAYS_VALID=365   # Certificate validity in days

# Create directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Generate certificates
cate for IP: $IP_ADDRESS"


# REM Check if OpenSSL is installed
if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: OpenSSL not found. Please install OpenSSL."
  exit 1
fi

# Generate private key
openssl genrsa -out "$SSL_DIR/privkey.pem" 2048

# Determine if input is IP address or hostname
if [[ $IP_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # It's an IP address
    SAN_CONFIG="IP.1 = $IP_ADDRESS"
else
    # It's a hostname
    SAN_CONFIG="DNS.1 = $IP_ADDRESS"
fi

# Generate CSR with IP in Subject Alternative Name
cat > "$SSL_DIR/openssl.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
C=US
ST=IL
L=Chicago
O=NEIU-ACOSUS
OU=R&D
CN=$IP_ADDRESS

[req_ext]
subjectAltName = @alt_names

[alt_names]
# IP.1 = $IP_ADDRESS
$SAN_CONFIG
EOF

# Generate CSR using the config
openssl req -new -key "$SSL_DIR/privkey.pem" -out "$SSL_DIR/cert.csr" -config "$SSL_DIR/openssl.cnf"

# Generate self-signed certificate
openssl x509 -req -in "$SSL_DIR/cert.csr" -signkey "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem" \
    -days $DAYS_VALID -sha256 -extensions req_ext -extfile "$SSL_DIR/openssl.cnf"

# Clean up
rm "$SSL_DIR/cert.csr" "$SSL_DIR/openssl.cnf"

# Set proper permissions
chmod 600 "$SSL_DIR/privkey.pem"
chmod 644 "$SSL_DIR/fullchain.pem"

echo "Self-signed SSL certificate generated successfully at $SSL_DIR"
echo "  - Private key: $SSL_DIR/privkey.pem"
echo "  - Certificate: $SSL_DIR/fullchain.pem"
echo "  - Valid for: $DAYS_VALID days"
echo ""
echo "Note: Since this is a self-signed certificate, browsers will show a security warning."