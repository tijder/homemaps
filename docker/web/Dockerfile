# The web build is made outside this image (flutter build web, see the workflow)
# and only packaged here. Build from the repo root:
#   docker build -f docker/web/Dockerfile .
FROM nginxinc/nginx-unprivileged:1.31.7-alpine

# Upgrade the Alpine packages the base image ships with. nginx-unprivileged is
# only rebuilt now and then, and until it is, a fixed package in the Alpine
# repo does not reach this image. On 29-10-2026 even the newest tag,
# 1.31.7-alpine (built 19-10), still had brotli-libs 1.2.0-r1: CVE-2026-111497
# (critical, fix 1.2.1-r0 since 22-10). The base runs as nginx (101); apk needs
# root for the upgrade only.
USER root
RUN apk upgrade --no-cache
USER 101

# Links the package on ghcr to the repo (visibility, README, releases).
LABEL org.opencontainers.image.source=https://github.com/tijder/homemaps

# Which variables the entrypoint fills in in the template. Without a filter
# envsubst also replaces nginx's own $uri and $host.
ENV NGINX_ENVSUBST_FILTER='^(VALHALLA_UPSTREAM|PHOTON_UPSTREAM|TILES_UPSTREAM|TRAFFIC_UPSTREAM|NGINX_LOCAL_RESOLVERS)$' \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    VALHALLA_UPSTREAM=http://valhalla:8002 \
    PHOTON_UPSTREAM=http://photon:2322 \
    TILES_UPSTREAM=http://tileserver:8080 \
    TRAFFIC_UPSTREAM=http://valhalla:9100

COPY docker/web/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY app/build/web /usr/share/nginx/html

EXPOSE 8080
