# Build from the repo root:  docker build -f importer/Dockerfile importer
FROM docker.io/library/python:3.14-alpine

# Links the package on ghcr to the repo (visibility, README, releases).
LABEL org.opencontainers.image.source=https://github.com/tijder/homemaps

# No dependencies outside the standard library; only the package itself.
COPY pyproject.toml /src/
COPY src /src/src
RUN pip install --no-cache-dir /src && rm -rf /src

# Log lines visible right away in `kubectl logs`.
ENV PYTHONUNBUFFERED=1
USER 1000:1000
EXPOSE 9100
ENTRYPOINT ["homemaps-traffic"]
