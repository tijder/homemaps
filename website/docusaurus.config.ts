import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// The site is built once and runs under any hostname: nginx rewrites this
// placeholder in every HTML and XML response (canonical, hreflang, sitemap) to
// the real origin. See nginx/default.conf.template.
const SITE_URL_PLACEHOLDER = 'https://homemaps.invalid';

const repo = 'https://github.com/tijder/homemaps';

const config: Config = {
  title: 'HomeMaps',
  tagline: 'Your own map and route planner',
  favicon: 'img/favicon.png',

  future: {
    v4: true,
    faster: true,
  },

  url: SITE_URL_PLACEHOLDER,
  baseUrl: '/',
  trailingSlash: false,

  organizationName: 'tijder',
  projectName: 'homemaps',

  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: {
    hooks: {onBrokenMarkdownLinks: 'throw'},
  },

  // The release version, so the download button points at the exact asset.
  // Empty on a development build: then the button goes to the latest release.
  customFields: {
    version: process.env.VERSION ?? '',
    repo,
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'nl'],
    localeConfigs: {
      en: {label: 'English', htmlLang: 'en'},
      nl: {label: 'Nederlands', htmlLang: 'nl'},
    },
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: `${repo}/tree/main/website/`,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
        sitemap: {
          changefreq: 'weekly',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.png',
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'HomeMaps',
      logo: {
        alt: 'HomeMaps',
        src: 'img/logo.png',
      },
      items: [
        {type: 'docSidebar', sidebarId: 'user', position: 'left', label: 'Using the app'},
        {type: 'docSidebar', sidebarId: 'admin', position: 'left', label: 'Self-hosting'},
        {type: 'localeDropdown', position: 'right'},
        {href: repo, position: 'right', className: 'header-github-link', 'aria-label': 'GitHub'},
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {label: 'Getting started', to: '/docs/user/getting-started'},
            {label: 'Navigation', to: '/docs/user/navigation'},
            {label: 'Install the server', to: '/docs/admin/install'},
          ],
        },
        {
          title: 'Project',
          items: [
            {label: 'GitHub', href: repo},
            {label: 'Releases', href: `${repo}/releases`},
            {label: 'Issues', href: `${repo}/issues`},
          ],
        },
        {
          title: 'Built on',
          items: [
            {label: 'OpenStreetMap', href: 'https://www.openstreetmap.org/copyright'},
            {label: 'Valhalla', href: 'https://github.com/valhalla/valhalla'},
            {label: 'MapLibre', href: 'https://maplibre.org'},
            {label: 'Photon', href: 'https://photon.komoot.io'},
          ],
        },
      ],
      copyright: `Map data © OpenStreetMap contributors. HomeMaps is open source.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'yaml', 'json', 'nginx', 'docker'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
