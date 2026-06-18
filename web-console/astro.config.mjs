import { defineConfig } from 'astro/config';
import node from '@astrojs/node';
import preact from '@astrojs/preact';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  integrations: [preact()],
  // La toolbar dev injecte ses propres <h1> dans le DOM, ce qui casse les
  // sélecteurs stricts Playwright (locator('h1') → 5 éléments).
  devToolbar: { enabled: false },
});
