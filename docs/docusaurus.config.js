// @ts-check

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'AgentLint',
  tagline: '33 checks for AI-ready repos. Every one backed by data.',
  url: 'https://docs.agentlint.app',
  baseUrl: '/',
  organizationName: '0xmariowu',
  projectName: 'AgentLint',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  trailingSlash: false,

  presets: [
    [
      '@docusaurus/preset-classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
          path: 'content',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      navbar: {
        title: 'AgentLint',
        items: [
          {
            href: 'https://github.com/0xmariowu/AgentLint',
            label: 'GitHub',
            position: 'right',
          },
          {
            href: 'https://www.agentlint.app',
            label: 'Website',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Introduction', to: '/' },
              { label: 'Check Reference', to: '/checks' },
              { label: 'Scoring', to: '/scoring' },
            ],
          },
          {
            title: 'Community',
            items: [
              { label: 'GitHub', href: 'https://github.com/0xmariowu/AgentLint' },
              { label: 'Issues', href: 'https://github.com/0xmariowu/AgentLint/issues' },
            ],
          },
        ],
        copyright: 'AgentLint — MIT License',
      },
      colorMode: {
        defaultMode: 'light',
        respectPrefersColorScheme: true,
      },
    }),
};

export default config;
