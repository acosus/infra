# AIACOSUS Development Environment

This repository contains everything needed to run the AIACOSUS development environment using Docker.

## Project Structure

When setting up the project, make sure all files are in the same directory:

```
your-project-directory/
├── docker-compose.yml         # Docker Compose configuration
├── generate-ssl.sh            # SSL generator script for Linux/macOS
├── generate-ssl.bat           # SSL generator script for Windows
├── ssl/                       # Directory for SSL certificates (created by the scripts)
└── README.md                  # This file
```

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- OpenSSL (included with macOS and most Linux distributions, Windows users can install via [Git for Windows](https://git-scm.com/download/win))

## Getting Started

### 1. Generate SSL Certificates

Before starting the containers, you need to generate SSL certificates. Run the script from your project's root directory:

**On macOS or Linux:**

```bash
# First, make the script executable
chmod +x generate-ssl.sh

# Then run it with your IP address
./generate-ssl.sh [your-ip-address]
```

**On Windows:**

```batch
generate-ssl.bat [your-ip-address]
```

Where `[your-ip-address]` should be:

- For local development: You can omit this parameter, and it will default to `localhost`
- For team development: Use the IP address of the machine hosting the application (e.g., `192.168.1.100`)
- For server deployment: Use the public IP address of your server (e.g., `34.206.101.247`)

### 2. Start the Environment

```bash
docker-compose --file docker-compose.dev-image.yml up -d
```

This will start all necessary containers:

- Frontend (NGINX server)
- Backend (Node.js)
- Model (Python/Flask)
- MongoDB

### 3. Access the Application

- Frontend: https://localhost (or https://your-server-ip-address)
- Backend API: http://localhost:3000
- Database: mongodb://localhost:27017

Note: When accessing from another machine, replace "localhost" with the IP address of the machine running the containers.

## Troubleshooting

### Fixing SSL Certificate Errors

If you see an error like this:

```
cannot load certificate "/etc/nginx/ssl/fullchain.pem": BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory...)
```

It means the container can't find the SSL certificates. Make sure:

1. You've run the SSL generation script before starting the containers
2. The `ssl` directory contains the following files:
   - `fullchain.pem`
   - `privkey.pem`
   - `certificate.crt`
   - `private.key`
3. The SSL directory is properly mounted in the docker-compose.yml file

### SSL Certificate Warnings

Since we're using self-signed certificates, browsers will show security warnings. You can:

1. Click "Advanced" and proceed anyway
2. Or add the certificate to your system/browser trust store

### "No matching manifest" Errors

If you see this error on Macs with Apple Silicon (M1/M2/M3):

- The `platform: linux/amd64` settings in docker-compose.yml force Docker to use emulation
- This is necessary because the images are only available for AMD64 architecture
- Performance may be slightly reduced due to emulation

## Data Persistence

- MongoDB data is stored in a Docker volume (`mongodb_data`)
- ML models are stored in a Docker volume (`models`)

These volumes persist even if you stop or remove the containers.

## Environment Variables

You can modify environment variables directly in the `docker-compose.yml` file.

Key variables you might want to change:

- `OPENAI_API_KEY` in the model service
- `AUTH_SECRET`, `ACCESS_TOKEN_SECRET`, and `REFRESH_TOKEN_SECRET` in the backend service
