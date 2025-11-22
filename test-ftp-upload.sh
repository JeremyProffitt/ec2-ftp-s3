#!/bin/bash

# Test FTP Upload Script
# Usage: ./test-ftp-upload.sh <FTP_HOST> <FTP_USER> <FTP_PASSWORD>

if [ $# -lt 3 ]; then
    echo "Usage: $0 <FTP_HOST> <FTP_USER> <FTP_PASSWORD>"
    echo "Example: $0 192.168.1.100 ftpuser mypassword"
    exit 1
fi

FTP_HOST="$1"
FTP_USER="$2"
FTP_PASSWORD="$3"
FTP_PORT=29720

# Create test file
TEST_FILE="test-$(date +%Y%m%d-%H%M%S).txt"
echo "Test file created at $(date)" > "$TEST_FILE"
echo "Hostname: $(hostname)" >> "$TEST_FILE"
echo "This file should appear in S3 bucket under incoming/ folder" >> "$TEST_FILE"

echo "========================================="
echo "FTP Upload Test"
echo "========================================="
echo "FTP Host: $FTP_HOST"
echo "FTP Port: $FTP_PORT"
echo "FTP User: $FTP_USER"
echo "Test File: $TEST_FILE"
echo "========================================="

# Check if lftp is installed
if ! command -v lftp &> /dev/null; then
    echo "ERROR: lftp is not installed"
    echo "Install it with: sudo apt-get install lftp (Ubuntu/Debian)"
    echo "or: sudo yum install lftp (Amazon Linux/RHEL)"
    exit 1
fi

# Test FTP connection and upload
echo "Testing FTP connection..."

lftp -u "$FTP_USER,$FTP_PASSWORD" -p $FTP_PORT $FTP_HOST << FTPEOF
set ftp:ssl-allow no
cd upload
put $TEST_FILE
ls -la
quit
FTPEOF

if [ $? -eq 0 ]; then
    echo "========================================="
    echo "SUCCESS: File uploaded to FTP server!"
    echo "========================================="
    echo "The file should appear in S3 within 2 minutes"
    echo "Check: s3://YOUR_BUCKET/incoming/$TEST_FILE"
    rm -f "$TEST_FILE"
else
    echo "========================================="
    echo "ERROR: Failed to upload file to FTP server"
    echo "========================================="
    exit 1
fi
