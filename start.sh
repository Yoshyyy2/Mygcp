#!/bin/bash
/usr/local/bin/keepalive.sh &
nginx &
exec /usr/local/bin/xray run -config /etc/xray/config.json
