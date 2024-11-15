ARG VERSION=dev
FROM nineaiyu/xadmin-client:${VERSION} AS client

FROM nginx:1.24-bullseye

ARG APT_MIRROR=http://deb.debian.org

ARG TOOLS="                           \
        ca-certificates               \
        curl                          \
        "

RUN set -ex \
    && rm -f /etc/apt/apt.conf.d/docker-clean \
    && sed -i "s@http://.*.debian.org@${APT_MIRROR}@g" /etc/apt/sources.list \
    && apt-get update > /dev/null \
    && apt-get -y install --no-install-recommends ${TOOLS} \
    && apt-get clean && rm -rf /var/lib/apt/lists /var/cache/apt/archives

WORKDIR /opt

COPY --from=client /usr/share/nginx/html /opt/xadmin-client

COPY nginx.conf /etc/nginx/nginx.conf
COPY xadmin-api-conf /etc/nginx/conf.d/xadmin-api-conf
COPY default.conf /etc/nginx/conf.d/default.conf
COPY http_server.conf /etc/nginx/sites-enabled/http_server.conf
COPY init.sh /docker-entrypoint.d/40-init-config.sh
