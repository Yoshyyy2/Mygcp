#!/bin/bash
/usr/local/bin/keepalive.sh &
exec /usr/local/bin/xray run -config /etc/xray/config.json
