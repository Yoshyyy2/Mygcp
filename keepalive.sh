#!/bin/bash
sleep 30
while true; do
  curl -s -o /dev/null --max-time 10 "http://localhost:${PORT:-8080}" || true
  sleep 240
done
