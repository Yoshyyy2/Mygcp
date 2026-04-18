FROM alpine:3.19

ENV XRAY_VERSION=1.8.11

RUN apk add --no-cache curl ca-certificates unzip bash nginx

# Install Xray
RUN curl -L "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /tmp/xray && \
    mv /tmp/xray/xray /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray /tmp/xray.zip

RUN mkdir -p /etc/xray /usr/share/nginx/html

COPY config.json /etc/xray/config.json
COPY keepalive.sh /usr/local/bin/keepalive.sh
COPY start.sh /usr/local/bin/start.sh
COPY index.html /usr/share/nginx/html/index.html

# Nginx config - serve landing page on 8080, proxy ws to xray
RUN cat > /etc/nginx/nginx.conf << 'NGINX'
worker_processes 1;
events { worker_connections 1024; }
http {
  server {
    listen 8080;
    location /Yosh {
      proxy_pass http://127.0.0.1:8081;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
    }
    location /Ryo {
      proxy_pass http://127.0.0.1:8082;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
    }
    location /Xyoshy {
      proxy_pass http://127.0.0.1:8083;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
    }
    location / {
      root /usr/share/nginx/html;
      index index.html;
    }
  }
}
NGINX

RUN chmod +x /usr/local/bin/keepalive.sh /usr/local/bin/start.sh

EXPOSE 8080

CMD ["/usr/local/bin/start.sh"]
