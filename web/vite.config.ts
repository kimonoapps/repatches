import { enhancedImages } from '@sveltejs/enhanced-img';
import { sveltekit } from '@sveltejs/kit/vite';
import tailwindcss from '@tailwindcss/vite';
import { svelteTesting } from '@testing-library/svelte/vite';
import { visualizer } from 'rollup-plugin-visualizer';
import { defineConfig, type Plugin, type ProxyOptions, type UserConfig } from 'vite';
import path from 'node:path';

// Kimono Photos: swap @immich/ui's built-in Immich logos for Kimono Photos' own, at build time.
// @immich/ui's <Logo> and `immichLogo` export load their SVGs from the package's own assets folder;
// redirecting those imports keeps every <Logo> in the app (sidebar, auth pages, share pages, errors)
// branded without touching each call site. The replacement SVGs are copied into src/lib/assets/kimono
// by repatches' branding/web/install.sh.
const assets = path.resolve(__dirname, 'src/lib/assets/kimono');
const logo = /[/\\]assets[/\\]immich-logo(?:-(inline|stacked|futo))*(?:-(dark|light))?\.svg$/;

const kimonoBrand = (): Plugin => ({
  name: 'kimono-brand',
  enforce: 'pre',
  resolveId(source, importer) {
    if (!importer?.includes('@immich/ui') && !source.includes('@immich/ui')) {
      return;
    }
    const match = logo.exec(source);
    if (!match) {
      return;
    }
    const [, wide, theme] = match;
    return path.join(assets, wide ? `logo-inline-${theme ?? 'light'}.svg` : 'logo-icon.svg');
  },
  transform(code, id) {
    if (!id.includes('@immich/ui')) {
      return;
    }
    if (id.endsWith('Logo.svelte')) {
      return code.replace('alt="Immich logo"', 'alt="Kimono Photos"');
    }
    // Hooks for web/src/kimono.css: seals, Mincho headings, the sidebar's selected marker.
    if (id.endsWith('internal/Button.svelte')) {
      return code.replaceAll(
        'class={classList}',
        "class={classList} data-k={icon ? 'icon' : 'seal'} data-k-variant={variant} data-k-color={color}",
      );
    }
    if (id.endsWith('Heading/Heading.svelte')) {
      return code.replace(
        '<Text {tag} {fontWeight} class={classList}',
        '<Text {tag} {fontWeight} class={classList} data-k-heading',
      );
    }
    if (id.endsWith('Avatar/Avatar.svelte')) {
      return code.replace(
        '<figure class={cleanClass(styles({ size, color }), className)}>',
        '<figure class={cleanClass(styles({ size, color }), className)} data-k-avatar>',
      );
    }
    if (id.endsWith('Navbar/NavbarItem.svelte')) {
      return code.replace(
        "class={cleanClass(styles({ active, variant: variant ?? 'default' }), className)}",
        "class={cleanClass(styles({ active, variant: variant ?? 'default' }), className)} data-k-nav={active ? 'active' : 'idle'}",
      );
    }
  },
});

const upstream = {
  target: process.env.IMMICH_SERVER_URL || 'http://immich-server:2283/',
  secure: true,
  changeOrigin: true,
  logLevel: 'info',
  ws: true,
};

const proxy: Record<string, string | ProxyOptions> = {
  '/api': upstream,
  '/.well-known/immich': upstream,
  '/custom.css': upstream,
};

export default defineConfig({
  build: {
    target: 'es2022',
  },
  resolve: {
    alias: {
      'xmlhttprequest-ssl': './node_modules/engine.io-client/lib/xmlhttprequest.js',
      // eslint-disable-next-line unicorn/prefer-module
      '@test-data': path.resolve(import.meta.dirname, './src/test-data'),
      // '@immich/ui': path.resolve(import.meta.dirname, '../../ui/packages/ui'),
    },
  },
  server: {
    // connect to a remote backend during web-only development
    proxy,
    allowedHosts: true,
  },
  preview: {
    proxy,
  },
  plugins: [
    kimonoBrand(),
    enhancedImages(),
    tailwindcss(),
    sveltekit(),
    process.env.BUILD_STATS === 'true'
      ? visualizer({
          emitFile: true,
          filename: 'stats.html',
        })
      : undefined,
    svelteTesting(),
  ],
  optimizeDeps: {
    entries: ['src/**/*.{svelte,ts,html}'],
  },
  test: {
    name: 'web:unit',
    include: ['src/**/*.{test,spec}.{js,ts}'],
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./src/test-data/setup.ts'],
    sequence: {
      hooks: 'list',
    },
    env: {
      TZ: 'UTC',
    },
  },
} as UserConfig);
