ARG VERSION=dev
FROM nineaiyu/xadmin-client:${VERSION} AS client

FROM nginx:1.31.5-alpine

ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org

ARG TOOLS="                           \
        ca-certificates               \
        curl                          \
        "

RUN set -ex \
    && sed -i "s@dl-cdn.alpinelinux.org@${ALPINE_MIRROR}@g" /etc/apk/repositories \
    && apk add --no-cache ${TOOLS}

WORKDIR /opt

COPY --from=client /usr/share/nginx/html /opt/xadmin-client

COPY nginx.conf /etc/nginx/nginx.conf
COPY xadmin-api-conf /etc/nginx/conf.d/xadmin-api-conf
COPY default.conf /etc/nginx/conf.d/default.conf
COPY http_server.conf /etc/nginx/sites-enabled/http_server.conf
COPY init.sh /docker-entrypoint.d/40-init-config.sh
