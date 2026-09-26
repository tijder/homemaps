import React from 'react';
import Link from '@docusaurus/Link';
import Translate, {translate} from '@docusaurus/Translate';
import Layout from '@theme/Layout';
import CodeBlock from '@theme/CodeBlock';
import Heading from '@theme/Heading';
import DownloadButtons from '@site/src/components/DownloadButtons';
import Features from '@site/src/components/Features';
import Screenshots, {useScreenshot} from '@site/src/components/Screenshots';
import styles from './index.module.css';

function Hero() {
  const phone = useScreenshot('4-navigation');
  return (
    <header className={styles.hero}>
      <div className="container">
        <div className={styles.heroInner}>
          <div className={styles.heroText}>
            <Heading as="h1" className={styles.heroTitle}>
              <Translate id="hero.title">Your own map and route planner</Translate>
            </Heading>
            <p className={styles.heroSubtitle}>
              <Translate id="hero.subtitle">
                Map, search, routes, live traffic and turn-by-turn navigation. Everything the app
                needs runs on your own server, and nothing goes out while you use it.
              </Translate>
            </p>
            <DownloadButtons hero />
            <p className={styles.heroNote}>
              <Translate id="hero.note">
                Web, Android and iOS, with Android Auto and CarPlay. In English and Dutch.
              </Translate>
            </p>
          </div>
          <div className={styles.heroPhone}>
            <img
              src={phone}
              alt={translate({id: 'hero.phoneAlt', message: 'HomeMaps navigating on a phone'})}
              width={1290}
              height={2796}
            />
          </div>
        </div>
      </div>
    </header>
  );
}

function SelfHost() {
  return (
    <section className={styles.selfhost}>
      <div className="container">
        <div className={styles.selfhostInner}>
          <div>
            <Heading as="h2">
              <Translate id="selfhost.title">Host it yourself</Translate>
            </Heading>
            <p>
              <Translate id="selfhost.text">
                One Helm chart brings the map tiles, the Valhalla router, Photon search, the web
                app and the traffic importer to your Kubernetes cluster. Start two build jobs
                once, and your country is ready.
              </Translate>
            </p>
            <Link className="button button--primary" to="/docs/admin/install">
              <Translate id="selfhost.button">Installation guide</Translate>
            </Link>
          </div>
          <CodeBlock language="bash">
            {`helm install homemaps oci://ghcr.io/tijder/charts/homemaps \\
  -n homemaps --create-namespace \\
  --set httpRoute.enabled=true \\
  --set 'httpRoute.hostnames={maps.example.org}' \\
  --set 'httpRoute.parentRefs[0].name=public-gateway'`}
          </CodeBlock>
        </div>
      </div>
    </section>
  );
}

export default function Home() {
  return (
    <Layout
      title={translate({id: 'home.title', message: 'Your own map and route planner'})}
      description={translate({
        id: 'home.description',
        message:
          'HomeMaps: self-hosted map, search, routes, live traffic and navigation for web, Android, iOS, Android Auto and CarPlay.',
      })}>
      <Hero />
      <main>
        <Features />
        <Screenshots />
        <SelfHost />
      </main>
    </Layout>
  );
}
