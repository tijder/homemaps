#!/bin/sh
set -eu

STYLES="osm-bright-gl-style:v1.11:osm-bright
positron-gl-style:v1.9:positron
dark-matter-gl-style:v1.9:dark-matter"

mkdir -p /data/styles /data/fonts /data/tiles

echo "$STYLES" | while IFS=: read -r repo tag name; do
  [ -n "$repo" ] || continue
  if [ -f "/data/styles/$name/style-local.json" ]; then
    echo "style $name already present"
    continue
  fi
  echo "fetching style $name ($repo $tag)"
  rm -rf "/data/styles/$name.tmp"
  mkdir -p "/data/styles/$name.tmp"
  wget -q -O /tmp/style.zip \
    "https://github.com/openmaptiles/$repo/releases/download/$tag/$tag.zip"
  unzip -q -o /tmp/style.zip -d "/data/styles/$name.tmp"
  rm -f /tmp/style.zip
  # style-local.json refers to mbtiles://{v3} and {styleJsonFolder}/sprite,
  # so not a single external URL. style-cdn.json and style-mb.json do: they
  # point to api.maptiler.com and are therefore removed.
  rm -f "/data/styles/$name.tmp/style-cdn.json" \
        "/data/styles/$name.tmp/style-mb.json" \
        "/data/styles/$name.tmp/index.html"
  rm -rf "/data/styles/$name"
  mv "/data/styles/$name.tmp" "/data/styles/$name"
done

# All font stacks in one archive (~74 MB, ~250 MB unpacked). Besides Noto Sans
# it also contains Metropolis, which positron and dark-matter need; the separate
# noto-sans.zip from the same release is therefore not enough.
if [ -d "/data/fonts/Metropolis Regular" ]; then
  echo "fonts already present"
else
  echo "fetching fonts"
  rm -rf /data/fonts.tmp
  mkdir -p /data/fonts.tmp
  wget -q -O /tmp/fonts.zip \
    "https://github.com/openmaptiles/fonts/releases/download/v2.0/v2.0.zip"
  unzip -q -o /tmp/fonts.zip -d /data/fonts.tmp
  rm -f /tmp/fonts.zip
  rm -rf /data/fonts
  mv /data/fonts.tmp /data/fonts
fi

# tileserver-gl exits with an error if the mbtiles file is missing. On a fresh
# install the planetiler CronJob has not run yet; waiting is then neater than a
# CrashLoopBackOff.
while [ ! -f /data/tiles/map.mbtiles ]; do
  echo "waiting for /data/tiles/map.mbtiles -- run the planetiler job:"
  echo "  kubectl create job --from=cronjob/$PLANETILER_CRONJOB planetiler-initial"
  sleep 60
done
echo "done"
