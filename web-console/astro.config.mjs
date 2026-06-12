import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  // La toolbar dev injecte ses propres <h1> dans le DOM, ce qui casse les
  // sélecteurs stricts Playwright (locator('h1') → 5 éléments).
  devToolbar: { enabled: false },
});
