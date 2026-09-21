# De web-build wordt buiten dit image gemaakt (flutter build web, zie de workflow)
# en hier alleen ingepakt. Bouwen vanuit de repo-root:
#   docker build -f docker/web/Dockerfile .
FROM nginxinc/nginx-unprivileged:1.31-alpine

# Welke variabelen de entrypoint in het template invult. Zonder filter vervangt
# envsubst óók nginx' eigen $uri en $host.
ENV NGINX_ENVSUBST_FILTER='^(VALHALLA_UPSTREAM|PHOTON_UPSTREAM|TILES_UPSTREAM|NGINX_LOCAL_RESOLVERS)$' \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    VALHALLA_UPSTREAM=http://valhalla:8002 \
    PHOTON_UPSTREAM=http://photon:2322 \
    TILES_UPSTREAM=http://tileserver:8080

COPY docker/web/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY app/build/web /usr/share/nginx/html

EXPOSE 8080
