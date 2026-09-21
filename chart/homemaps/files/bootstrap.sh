#!/bin/sh
set -eu

STYLES="osm-bright-gl-style:v1.11:osm-bright
positron-gl-style:v1.9:positron
dark-matter-gl-style:v1.9:dark-matter"

mkdir -p /data/styles /data/fonts /data/tiles

echo "$STYLES" | while IFS=: read -r repo tag naam; do
  [ -n "$repo" ] || continue
  if [ -f "/data/styles/$naam/style-local.json" ]; then
    echo "stijl $naam staat er al"
    continue
  fi
  echo "stijl $naam ophalen ($repo $tag)"
  rm -rf "/data/styles/$naam.tmp"
  mkdir -p "/data/styles/$naam.tmp"
  wget -q -O /tmp/style.zip \
    "https://github.com/openmaptiles/$repo/releases/download/$tag/$tag.zip"
  unzip -q -o /tmp/style.zip -d "/data/styles/$naam.tmp"
  rm -f /tmp/style.zip
  # style-local.json verwijst naar mbtiles://{v3} en {styleJsonFolder}/sprite,
  # dus geen enkele externe URL. style-cdn.json en style-mb.json wel: die
  # wijzen naar api.maptiler.com en gaan er daarom uit.
  rm -f "/data/styles/$naam.tmp/style-cdn.json" \
        "/data/styles/$naam.tmp/style-mb.json" \
        "/data/styles/$naam.tmp/index.html"
  rm -rf "/data/styles/$naam"
  mv "/data/styles/$naam.tmp" "/data/styles/$naam"
done

# Alle fontstacks in één archief (~74 MB, uitgepakt ~250 MB). Bevat naast
# Noto Sans ook Metropolis, dat positron en dark-matter nodig hebben; de
# losse noto-sans.zip uit dezelfde release is dus niet genoeg.
if [ -d "/data/fonts/Metropolis Regular" ]; then
  echo "fonts staan er al"
else
  echo "fonts ophalen"
  rm -rf /data/fonts.tmp
  mkdir -p /data/fonts.tmp
  wget -q -O /tmp/fonts.zip \
    "https://github.com/openmaptiles/fonts/releases/download/v2.0/v2.0.zip"
  unzip -q -o /tmp/fonts.zip -d /data/fonts.tmp
  rm -f /tmp/fonts.zip
  rm -rf /data/fonts
  mv /data/fonts.tmp /data/fonts
fi

# tileserver-gl stopt met een fout als het mbtiles-bestand ontbreekt. Bij een
# verse installatie is de planetiler-CronJob nog niet gedraaid; wachten is dan
# netter dan een CrashLoopBackOff.
while [ ! -f /data/tiles/kaart.mbtiles ]; do
  echo "wacht op /data/tiles/kaart.mbtiles -- draai de planetiler-job:"
  echo "  kubectl create job --from=cronjob/$PLANETILER_CRONJOB planetiler-eerste"
  sleep 60
done
echo "klaar"
