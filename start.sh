#!/bin/bash

# Create nginx pid directory
mkdir -p /run/nginx

# Start Xray in background (listens on 8081, 8082, 8083)
/usr/local/bin/xray run -config /etc/xray/config.json &

# Start keepalive in background
/usr/local/bin/keepalive.sh &

# Start nginx in foreground (listens on 8080, proxies to Xray)
exec nginx -g 'daemon off;'
