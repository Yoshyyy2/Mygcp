#!/bin/bash

# Create required dirs
mkdir -p /run/nginx /var/log/nginx

# Test nginx config first
nginx -t 2>&1

# Start Xray in background
/usr/local/bin/xray run -config /etc/xray/config.json &

# Small delay to let xray start
sleep 2

# Start keepalive in background
/usr/local/bin/keepalive.sh &

# Start nginx in foreground
exec nginx -g 'daemon off;'
