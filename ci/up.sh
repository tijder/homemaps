#!/usr/bin/env bash
# Zet de hele chart op in een kind-cluster met Andorra als gebied, bouwt tiles en
# routegraaf, en toetst het geheel -- inclusief live verkeer uit een nagemaakte
# NDW-feed. Idempotent: opnieuw draaien werkt een bestaand cluster bij.
#
#   ci/up.sh            alles
#   ci/up.sh --weg      het cluster weer opruimen
#
# Verwacht de web-build in app/build/web (flutter build web). Werkt met docker en
# met podman (KIND_EXPERIMENTAL_PROVIDER=podman).
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=${CLUSTER:-homemaps}
NS=${NS:-homemaps}
RELEASE=${RELEASE:-hm}
ENGINE=${ENGINE:-$(command -v docker >/dev/null 2>&1 && [ -z "${KIND_EXPERIMENTAL_PROVIDER:-}" ] && echo docker || echo podman)}
K="kubectl --context kind-$CLUSTER -n $NS"

if [ "${1:-}" = "--weg" ]; then
  kind delete cluster --name "$CLUSTER"
  exit 0
fi

stap() { printf '\n== %s\n' "$*"; }

stap "images bouwen ($ENGINE)"
test -f app/build/web/index.html || { echo "app/build/web ontbreekt: draai eerst 'flutter build web' in app/"; exit 1; }
$ENGINE build -q -t homemaps-web:ci -f docker/web/Dockerfile .
$ENGINE build -q -t homemaps-traffic:ci -f importer/Dockerfile importer

stap "kind-cluster $CLUSTER"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 120s
for image in homemaps-web:ci homemaps-traffic:ci; do
  if [ "$ENGINE" = podman ]; then
    # `kind load docker-image` kent alleen de docker-daemon.
    $ENGINE save "localhost/$image" -o "/tmp/$CLUSTER-${image%%:*}.tar"
    kind load image-archive "/tmp/$CLUSTER-${image%%:*}.tar" --name "$CLUSTER"
    rm -f "/tmp/$CLUSTER-${image%%:*}.tar"
  else
    kind load docker-image "$image" --name "$CLUSTER"
  fi
done

stap "nagemaakte NDW-feed"
kubectl --context "kind-$CLUSTER" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "kind-$CLUSTER" apply -f -
FEEDS=$(mktemp -d)
python3 ci/nep-ndw/maak.py "$FEEDS" >/dev/null
$K create configmap nep-ndw --from-file="$FEEDS" --dry-run=client -o yaml | $K apply -f -
$K apply -f ci/nep-ndw/nep-ndw.yaml
rm -rf "$FEEDS"

stap "chart installeren"
PREFIX=$( [ "$ENGINE" = podman ] && echo localhost/ || echo "" )
helm --kube-context "kind-$CLUSTER" upgrade --install "$RELEASE" chart/homemaps -n "$NS" \
  -f ci/values-andorra.yaml \
  --set web.image.repository="${PREFIX}homemaps-web" \
  --set valhalla.verkeer.image.repository="${PREFIX}homemaps-traffic"

stap "bouwjobs (tiles en routegraaf)"
for paar in "tiles-planetiler:planetiler-eerste" "valhalla-bouw:valhalla-eerste"; do
  cronjob="$RELEASE-homemaps-${paar%%:*}"; job="${paar##*:}"
  $K get job "$job" >/dev/null 2>&1 || $K create job --from="cronjob/$cronjob" "$job"
done
$K wait --for=condition=complete --timeout=30m job/valhalla-eerste job/planetiler-eerste || {
  $K get pods; $K logs job/planetiler-eerste --all-containers --tail=30 || true
  $K logs job/valhalla-eerste --all-containers --tail=30 || true; exit 1; }

stap "wachten tot alles draait"
$K rollout status deploy --timeout=15m

stap "helm test"
helm --kube-context "kind-$CLUSTER" test "$RELEASE" -n "$NS" --logs

stap "live verkeer"
ci/e2e/verkeer_cluster.sh "$CLUSTER" "$NS" "$RELEASE"

printf '\nKlaar. De app: kubectl --context kind-%s -n %s port-forward svc/%s-homemaps-web 8080:8080  ->  http://localhost:8080\n' "$CLUSTER" "$NS" "$RELEASE"
