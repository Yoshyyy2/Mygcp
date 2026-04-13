FROM alpine:3.19

ENV XRAY_VERSION=1.8.11

RUN apk add --no-cache curl ca-certificates unzip bash

RUN curl -L "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /tmp/xray && \
    mv /tmp/xray/xray /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray /tmp/xray.zip

RUN mkdir -p /etc/xray

COPY config.json /etc/xray/config.json
COPY keepalive.sh /usr/local/bin/keepalive.sh
COPY start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/keepalive.sh /usr/local/bin/start.sh

EXPOSE 8080 8081 8082

CMD ["/usr/local/bin/start.sh"]
