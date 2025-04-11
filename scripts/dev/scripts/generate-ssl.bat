@echo off
setlocal enabledelayedexpansion

REM SSL Certificate Generation for localhost and IP addresses
REM This script generates self-signed certificates for development/testing

REM Variables
set SSL_DIR=ssl
set HOST=%1

REM Set HOST to localhost if not provided
if "%HOST%"=="" set HOST=localhost

set DAYS_VALID=365

REM Create directory if it doesn't exist
if not exist %SSL_DIR% mkdir %SSL_DIR%

echo Generating self-signed SSL certificate for: %HOST%

REM Check if OpenSSL is installed
where openssl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: OpenSSL not found. Please install OpenSSL and ensure it's in your PATH.
    exit /b 1
)

REM Generate private key
openssl genrsa -out "%SSL_DIR%\privkey.pem" 2048

REM Determine if the input is an IP address or hostname
echo %HOST%| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul
if %ERRORLEVEL% equ 0 (
    REM It's an IP address
    set SAN_TYPE=IP
) else (
    REM It's a hostname
    set SAN_TYPE=DNS
)

REM Create OpenSSL configuration file
(
echo [req]
echo default_bits = 2048
echo prompt = no
echo default_md = sha256
echo req_extensions = req_ext
echo distinguished_name = dn
echo.
echo [dn]
echo C=US
echo ST=IL
echo L=Chicago
echo O=NEIU-ACOSUS
echo OU=R^&D
echo CN=%HOST%
echo.
echo [req_ext]
echo subjectAltName = @alt_names
echo.
echo [alt_names]
echo %SAN_TYPE%.1 = %HOST%
) > "%SSL_DIR%\openssl.cnf"

REM Add localhost and 127.0.0.1 to alt_names if they're not already the main host
if not "%HOST%"=="localhost" (
    echo DNS.2 = localhost>> "%SSL_DIR%\openssl.cnf"
)
if not "%HOST%"=="127.0.0.1" (
    echo IP.2 = 127.0.0.1>> "%SSL_DIR%\openssl.cnf"
)

REM Generate CSR using the config
openssl req -new -key "%SSL_DIR%\privkey.pem" -out "%SSL_DIR%\cert.csr" -config "%SSL_DIR%\openssl.cnf"

REM Generate self-signed certificate
openssl x509 -req -in "%SSL_DIR%\cert.csr" -signkey "%SSL_DIR%\privkey.pem" -out "%SSL_DIR%\fullchain.pem" ^
    -days %DAYS_VALID% -sha256 -extensions req_ext -extfile "%SSL_DIR%\openssl.cnf"

REM Clean up
del "%SSL_DIR%\cert.csr"
REM Keep the OpenSSL config for reference
REM del "%SSL_DIR%\openssl.cnf"

echo Self-signed SSL certificate generated successfully at %SSL_DIR%
echo   - Private key: %SSL_DIR%\privkey.pem
echo   - Certificate: %SSL_DIR%\fullchain.pem
echo   - Valid for: %DAYS_VALID% days
echo   - Configuration: %SSL_DIR%\openssl.cnf (kept for reference)
echo.
echo Note: Since this is a self-signed certificate, browsers will show a security warning.
echo For development use only.

REM Optional: Add certificate to Windows trusted store
echo.
echo To add this certificate to your Windows trusted store:
echo 1. Run certmgr.msc
echo 2. Right-click on "Trusted Root Certification Authorities" -^> "All Tasks" -^> "Import"
echo 3. Follow the wizard and select "%CD%\%SSL_DIR%\fullchain.pem"