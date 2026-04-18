#!/bin/bash
# Start keepalive
/usr/local/bin/keepalive.sh &

# Start nginx
nginx -g 'daemon off;' &

# Start Xray
exec /usr/local/bin/xray run -config /etc/xray/config.json
