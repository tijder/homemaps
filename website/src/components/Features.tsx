import React from 'react';
import Translate from '@docusaurus/Translate';
import Link from '@docusaurus/Link';
import styles from './Features.module.css';

type Feature = {icon: string; title: React.ReactNode; text: React.ReactNode; to: string};

const FEATURES: Feature[] = [
  {
    icon: '🗺️',
    to: '/docs/user/map-and-search',
    title: <Translate id="feature.map.title">Map and search</Translate>,
    text: (
      <Translate id="feature.map.text">
        OpenStreetMap in three styles, day and night. Find addresses, postcodes with house
        numbers, places and coordinates.
      </Translate>
    ),
  },
  {
    icon: '🚲',
    to: '/docs/user/routes',
    title: <Translate id="feature.routes.title">Routes for car, bike and foot</Translate>,
    text: (
      <Translate id="feature.routes.text">
        Stops along the way, alternatives, an elevation profile and turn-by-turn directions.
        Share a route as a link.
      </Translate>
    ),
  },
  {
    icon: '🧭',
    to: '/docs/user/navigation',
    title: <Translate id="feature.nav.title">Navigation with voice</Translate>,
    text: (
      <Translate id="feature.nav.text">
        Lane guidance, speed limits, speed cameras and overhead signs. Reroutes when you miss a
        turn and offers a faster route when there is one.
      </Translate>
    ),
  },
  {
    icon: '🚧',
    to: '/docs/admin/traffic',
    title: <Translate id="feature.traffic.title">Live traffic</Translate>,
    text: (
      <Translate id="feature.traffic.text">
        Jams, closures, roadworks and open bridges from NDW open data, on the map and in the
        route. Planned closures for when you leave later.
      </Translate>
    ),
  },
  {
    icon: '🚗',
    to: '/docs/user/car',
    title: <Translate id="feature.car.title">Android Auto and CarPlay</Translate>,
    text: (
      <Translate id="feature.car.text">
        The same navigation on the car's screen: home, work and recent places, search, a route
        preview and turn-by-turn with lanes and ETA.
      </Translate>
    ),
  },
  {
    icon: '🏠',
    to: '/docs/admin/install',
    title: <Translate id="feature.selfhosted.title">Runs on your own server</Translate>,
    text: (
      <Translate id="feature.selfhosted.text">
        Tiles, routing, search and traffic in one Helm chart. Nothing leaves your network while
        you use the app.
      </Translate>
    ),
  },
  {
    icon: '👪',
    to: '/docs/user/places-and-sharing',
    title: <Translate id="feature.sharing.title">Places and location sharing</Translate>,
    text: (
      <Translate id="feature.sharing.text">
        Home, work and recent places. Share your location with your family through Dawarich, or
        send it to OwnTracks, Traccar or your own server.
      </Translate>
    ),
  },
  {
    icon: '🌍',
    to: '/docs/admin/configuration',
    title: <Translate id="feature.region.title">Any region</Translate>,
    text: (
      <Translate id="feature.region.text">
        The Netherlands by default; point the chart at another Geofabrik extract and Photon
        index and you have your own country.
      </Translate>
    ),
  },
];

export default function Features() {
  return (
    <section className={styles.section}>
      <div className="container">
        <div className={styles.grid}>
          {FEATURES.map((f, i) => (
            <Link key={i} to={f.to} className={styles.card}>
              <div className={styles.icon} aria-hidden="true">
                {f.icon}
              </div>
              <h3>{f.title}</h3>
              <p>{f.text}</p>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}
