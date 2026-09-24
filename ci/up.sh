#!/usr/bin/env bash
# Sets up the whole chart in a kind cluster with Andorra as the region, builds tiles
# and routing graph, and tests the whole thing -- including live traffic from a fake
# NDW feed. Idempotent: running it again updates an existing cluster.
#
#   ci/up.sh            everything
#   SCREENSHOTS=1 ci/up.sh   also the screenshots for the App Store
#   ci/up.sh --down     tear the cluster down again
#
# Expects the web build in app/build/web (flutter build web). Works with docker and
# with podman (KIND_EXPERIMENTAL_PROVIDER=podman).
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=${CLUSTER:-homemaps}
NS=${NS:-homemaps}
RELEASE=${RELEASE:-hm}
# Only for the final line: the port on which you want to open the app locally.
LOCAL_PORT=${LOCAL_PORT:-8080}
ENGINE=${ENGINE:-$(command -v docker >/dev/null 2>&1 && [ -z "${KIND_EXPERIMENTAL_PROVIDER:-}" ] && echo docker || echo podman)}
K="kubectl --context kind-$CLUSTER -n $NS"

if [ "${1:-}" = "--down" ]; then
  kind delete cluster --name "$CLUSTER"
  exit 0
fi

step() { printf '\n== %s\n' "$*"; }

step "building images ($ENGINE)"
test -f app/build/web/index.html || { echo "app/build/web is missing: run 'flutter build web' in app/ first"; exit 1; }
$ENGINE build -q -t homemaps-web:ci -f docker/web/Dockerfile .
$ENGINE build -q -t homemaps-traffic:ci -f importer/Dockerfile importer

step "kind cluster $CLUSTER"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --wait 120s
for image in homemaps-web:ci homemaps-traffic:ci; do
  if [ "$ENGINE" = podman ]; then
    # `kind load docker-image` only knows the docker daemon.
    $ENGINE save "localhost/$image" -o "/tmp/$CLUSTER-${image%%:*}.tar"
    kind load image-archive "/tmp/$CLUSTER-${image%%:*}.tar" --name "$CLUSTER"
    rm -f "/tmp/$CLUSTER-${image%%:*}.tar"
  else
    kind load docker-image "$image" --name "$CLUSTER"
  fi
done

step "fake NDW feed"
kubectl --context "kind-$CLUSTER" create namespace "$NS" --dry-run=client -o yaml | kubectl --context "kind-$CLUSTER" apply -f -
FEEDS=$(mktemp -d)
python3 ci/fake-ndw/generate.py "$FEEDS" >/dev/null
$K create configmap fake-ndw --from-file="$FEEDS" --dry-run=client -o yaml | $K apply -f -
$K apply -f ci/fake-ndw/fake-ndw.yaml
rm -rf "$FEEDS"

step "installing chart"
PREFIX=$( [ "$ENGINE" = podman ] && echo localhost/ || echo "" )
helm --kube-context "kind-$CLUSTER" upgrade --install "$RELEASE" chart/homemaps -n "$NS" \
  -f ci/values-andorra.yaml \
  --set web.image.repository="${PREFIX}homemaps-web" \
  --set valhalla.traffic.image.repository="${PREFIX}homemaps-traffic"

# The tag `ci` doesn't change, so a newly loaded image only reaches the pod after a
# restart.
$K rollout restart "deploy/$RELEASE-homemaps-web" >/dev/null

step "build jobs (tiles and routing graph)"
for pair in "tiles-planetiler:planetiler-initial" "valhalla-build:valhalla-initial"; do
  cronjob="$RELEASE-homemaps-${pair%%:*}"; job="${pair##*:}"
  # A failed job from a previous run blocks a new attempt.
  if [ "$($K get job "$job" -o jsonpath='{.status.failed}' 2>/dev/null || true)" != "" ]; then
    $K delete job "$job" --wait
  fi
  $K get job "$job" >/dev/null 2>&1 || $K create job --from="cronjob/$cronjob" "$job"
done
# Don't wait 30 minutes blindly: a job that fails (a source server that is down,
# like osmdata.openstreetmap.de for planetiler) must stop the run right away.
for _ in $(seq 1 180); do
  finished=0
  for job in valhalla-initial planetiler-initial; do
    state=$($K get job "$job" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type} {end}')
    case "$state" in
      *Failed*)
        echo "job $job failed:"; $K get pods
        $K logs "job/$job" --all-containers --tail=40 || true
        exit 1 ;;
      *Complete*) finished=$((finished + 1)) ;;
    esac
  done
  [ "$finished" -eq 2 ] && break
  sleep 10
done
[ "$finished" -eq 2 ] || { echo "build jobs not finished within 30 minutes"; $K get pods; exit 1; }

step "waiting until everything runs"
# Per deployment: without a name `rollout status` doesn't wait for a restart that
# was only just requested.
for deploy in $($K get deploy -o name); do
  $K rollout status "$deploy" --timeout=15m
done

step "helm test"
helm --kube-context "kind-$CLUSTER" test "$RELEASE" -n "$NS" --logs

step "live traffic"
ci/e2e/traffic_cluster.sh "$CLUSTER" "$NS" "$RELEASE"

step "app in the browser"
if python3 -c 'import playwright' 2>/dev/null; then
  # A free port, so a locally running app (on LOCAL_PORT) doesn't get in the way.
  TEST_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1])')
  $K port-forward "svc/$RELEASE-homemaps-web" "$TEST_PORT:8080" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
  trap 'kill $PORT_FORWARD_PID 2>/dev/null || true' EXIT
  for _ in $(seq 1 30); do
    curl -fs "http://127.0.0.1:$TEST_PORT/healthz" >/dev/null && break
    sleep 1
  done
  # From Andorra la Vella to Encamp.
  python3 ci/e2e/app_browser.py "http://127.0.0.1:$TEST_PORT" 42.5063,1.5218 42.5343,1.5801
  # For the App Store (release.yml fetches them from the green build of main).
  if [ -n "${SCREENSHOTS:-}" ]; then
    step "screenshots for the App Store"
    python3 ci/e2e/screenshots.py "http://127.0.0.1:$TEST_PORT" 42.5063,1.5218 Encamp
  fi
  kill $PORT_FORWARD_PID 2>/dev/null || true
else
  echo "skipped: no Playwright (pip install playwright && playwright install chromium)"
fi

printf '\nDone. The app: kubectl --context kind-%s -n %s port-forward svc/%s-homemaps-web %s:8080  ->  http://localhost:%s\n' "$CLUSTER" "$NS" "$RELEASE" "$LOCAL_PORT" "$LOCAL_PORT"
