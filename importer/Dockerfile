# Bouwen vanuit de repo-root:  docker build -f importer/Dockerfile importer
FROM docker.io/library/python:3.14-alpine

# Geen afhankelijkheden buiten de standaardbibliotheek; alleen het pakket zelf.
COPY pyproject.toml /src/
COPY src /src/src
RUN pip install --no-cache-dir /src && rm -rf /src

# Logregels meteen zichtbaar in `kubectl logs`.
ENV PYTHONUNBUFFERED=1
USER 1000:1000
EXPOSE 9100
ENTRYPOINT ["homemaps-traffic"]
