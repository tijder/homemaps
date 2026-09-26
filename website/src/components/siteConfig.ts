import {useEffect, useState} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';

/**
 * Runtime configuration of the site, served by nginx as /config.json from a
 * ConfigMap (chart value `website.config`). Every field is optional; an empty
 * string hides the matching button. Without the file only the GitHub buttons
 * show.
 */
export type SiteConfig = {
  /** The web app of this installation, e.g. https://maps.example.org */
  appUrl?: string;
  /** TestFlight invitation link for the iOS beta */
  testflightUrl?: string;
  /** Google Play listing */
  playStoreUrl?: string;
  /** App Store listing */
  appStoreUrl?: string;
};

export function useSiteConfig(): SiteConfig {
  const url = useBaseUrl('/config.json');
  const [config, setConfig] = useState<SiteConfig>({});
  useEffect(() => {
    let cancelled = false;
    fetch(url, {cache: 'no-cache'})
      .then((r) => (r.ok ? r.json() : {}))
      .then((c) => {
        if (!cancelled && c && typeof c === 'object') setConfig(c as SiteConfig);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [url]);
  return config;
}
