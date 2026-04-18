FROM alpine:3.19

ENV XRAY_VERSION=1.8.11

RUN apk add --no-cache curl ca-certificates unzip bash nginx

RUN curl -L "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /tmp/xray && \
    mv /tmp/xray/xray /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray /tmp/xray.zip

RUN mkdir -p /etc/xray /usr/share/nginx/html /run/nginx

COPY config.json /etc/xray/config.json
COPY keepalive.sh /usr/local/bin/keepalive.sh
COPY start.sh /usr/local/bin/start.sh
COPY index.html /usr/share/nginx/html/index.html
COPY nginx.conf /etc/nginx/nginx.conf

RUN chmod +x /usr/local/bin/keepalive.sh /usr/local/bin/start.sh

EXPOSE 8080

CMD ["/usr/local/bin/start.sh"]
