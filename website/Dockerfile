# The documentation site: Docusaurus, built once, served by nginx. Built only
# by release.yml, with the App Store screenshots copied into
# static/img/screenshots/ first and VERSION set to the release.
FROM node:22-alpine AS build
WORKDIR /site
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# The release version goes into the download links; empty = latest release.
ARG VERSION=""
ENV VERSION=$VERSION
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.31-alpine
LABEL org.opencontainers.image.source="https://github.com/tijder/homemaps"
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /site/build /usr/share/nginx/html
# Only this variable gets substituted in the template: nginx's own $variables
# must stay as they are.
ENV NGINX_ENVSUBST_FILTER="^SITE_URL$"
# The absolute address of the site, without a trailing slash. Empty = derived
# from the request (Host and X-Forwarded-Proto).
ENV SITE_URL=""
EXPOSE 8080
