import React from 'react';
import Translate, {translate} from '@docusaurus/Translate';
import useBaseUrl from '@docusaurus/useBaseUrl';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import clsx from 'clsx';
import styles from './Screenshots.module.css';

/**
 * The App Store screenshots that ci/e2e/screenshots.py takes of the web app,
 * in the language of the page. They land in static/img/screenshots/<lang>/
 * <iphone|ipad>/N-name.png at build time in CI; in a local build without them
 * the images are simply missing.
 */
const SHOTS = [
  {file: '1-map', caption: translate({id: 'shots.map', message: 'The map, at your location'})},
  {file: '2-search', caption: translate({id: 'shots.search', message: 'Search a place or address'})},
  {file: '3-route', caption: translate({id: 'shots.route', message: 'A planned route with alternatives'})},
  {file: '4-navigation', caption: translate({id: 'shots.navigation', message: 'Turn-by-turn navigation'})},
];

export function useScreenshot(file: string, device: 'iphone' | 'ipad' = 'iphone') {
  const {i18n} = useDocusaurusContext();
  const lang = i18n.currentLocale === 'nl' ? 'nl' : 'en';
  return useBaseUrl(`/img/screenshots/${lang}/${device}/${file}.png`);
}

function Shot({file, caption, device}: {file: string; caption: string; device: 'iphone' | 'ipad'}) {
  const src = useScreenshot(file, device);
  return (
    <figure className={clsx(styles.shot, device === 'ipad' && styles.ipad)}>
      <img src={src} alt={caption} loading="lazy" />
      <figcaption>{caption}</figcaption>
    </figure>
  );
}

export default function Screenshots() {
  return (
    <section className={styles.section}>
      <div className="container">
        <h2 className={styles.title}>
          <Translate id="shots.title">On your phone and tablet</Translate>
        </h2>
        <div className={styles.row}>
          {SHOTS.map((s) => (
            <Shot key={s.file} device="iphone" {...s} />
          ))}
        </div>
        <div className={clsx(styles.row, styles.rowIpad)}>
          <Shot device="ipad" file="3-route" caption={SHOTS[2].caption} />
          <Shot device="ipad" file="4-navigation" caption={SHOTS[3].caption} />
        </div>
      </div>
    </section>
  );
}
