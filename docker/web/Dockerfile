# The web build is made outside this image (flutter build web, see the workflow)
# and only packaged here. Build from the repo root:
#   docker build -f docker/web/Dockerfile .
FROM nginxinc/nginx-unprivileged:1.31-alpine

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
