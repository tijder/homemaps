import React from 'react';
import Link from '@docusaurus/Link';
import Translate from '@docusaurus/Translate';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import clsx from 'clsx';
import {useSiteConfig} from './siteConfig';
import styles from './DownloadButtons.module.css';

/** Where the APK of this build lives: the exact release, or the latest one. */
export function useReleaseLinks() {
  const {siteConfig} = useDocusaurusContext();
  const version = siteConfig.customFields?.version as string;
  const repo = siteConfig.customFields?.repo as string;
  return {
    version,
    repo,
    release: version ? `${repo}/releases/tag/v${version}` : `${repo}/releases/latest`,
    apk: version
      ? `${repo}/releases/download/v${version}/homemaps-${version}.apk`
      : `${repo}/releases/latest`,
  };
}

export default function DownloadButtons({hero = false}: {hero?: boolean}) {
  const config = useSiteConfig();
  const links = useReleaseLinks();
  return (
    <div className={clsx(styles.buttons, hero && styles.hero)}>
      {config.appUrl && (
        <Link className={clsx('button button--lg', hero ? styles.heroMain : 'button--primary')} href={config.appUrl}>
          <Translate id="download.webApp">Open the web app</Translate>
        </Link>
      )}
      <Link
        className={clsx(
          'button button--lg',
          hero ? (config.appUrl ? styles.heroOther : styles.heroMain) : config.appUrl ? 'button--secondary' : 'button--primary',
        )}
        href={links.apk}>
        <Translate id="download.apk">Download for Android</Translate>
        {links.version && <span className={styles.version}>{links.version}</span>}
      </Link>
      {config.testflightUrl && (
        <Link className={clsx('button button--lg', hero ? styles.heroOther : 'button--secondary')} href={config.testflightUrl}>
          <Translate id="download.testflight">iPhone via TestFlight</Translate>
        </Link>
      )}
      {(config.playStoreUrl || config.appStoreUrl) && (
        <div className={styles.badges}>
          {config.playStoreUrl && (
            <Link className={styles.badge} href={config.playStoreUrl}>
              <span className={styles.badgeSmall}>
                <Translate id="download.getItOn">Get it on</Translate>
              </span>
              <span className={styles.badgeBig}>Google Play</span>
            </Link>
          )}
          {config.appStoreUrl && (
            <Link className={styles.badge} href={config.appStoreUrl}>
              <span className={styles.badgeSmall}>
                <Translate id="download.downloadOn">Download on the</Translate>
              </span>
              <span className={styles.badgeBig}>App Store</span>
            </Link>
          )}
        </div>
      )}
    </div>
  );
}
