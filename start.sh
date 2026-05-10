#!/bin/bash

# Start keepalive in background
/usr/local/bin/keepalive.sh &

# Start Xray
exec /usr/local/bin/xray run -config /etc/xray/config.json
