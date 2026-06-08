import { defineConfig, devices } from '@playwright/test';

const chromiumUse = {
  ...devices['Desktop Chrome'],
  ...(process.env.CHROMIUM_PATH || process.env.CI
    ? { launchOptions: { executablePath: process.env.CHROMIUM_PATH || '/usr/bin/chromium' } }
    : {}),
};

export default defineConfig({
  reporter: 'list',
  projects: [
    {
      name: 'chromium',
      testDir: 'tests/e2e',
      use: {
        ...chromiumUse,
        baseURL: 'http://localhost:4321',
      },
    },
    {
      name: 'flows',
      testDir: 'tests/flows',
      use: {
        ...chromiumUse,
        baseURL: process.env.FLOWS_BASE_URL ?? 'http://localhost:38040',
      },
    },
    {
      name: 'patient',
      testDir: 'tests/flows',
      use: {
        ...chromiumUse,
        baseURL: process.env.FLOWS_BASE_URL ?? 'http://localhost:38040',
      },
    },
    {
      name: 'practitioner',
      testDir: 'tests/flows',
      use: {
        ...chromiumUse,
        baseURL: process.env.FLOWS_BASE_URL ?? 'http://localhost:38040',
      },
    },
    {
      name: 'secretary',
      testDir: 'tests/flows',
      use: {
        ...chromiumUse,
        baseURL: process.env.FLOWS_BASE_URL ?? 'http://localhost:38040',
      },
    },
  ],
  webServer: {
    command: 'npm run dev',
    port: 4321,
    reuseExistingServer: !process.env.CI,
  },
});
