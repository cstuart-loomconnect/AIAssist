import { defineConfig, devices } from '@playwright/test';

// Browser tests for AI Assist. They run against a Salesforce org that already has the package source
// deployed and the permission sets assigned (CI uses the scratch org the Apex tests ran in).
//
// Login: set SF_FRONTDOOR_URL to the output of `sf org open --url-only`. The setup project opens it once,
// saves the session, and every test reuses it. See README.md.
export default defineConfig({
  testDir: './tests',
  outputDir: './test-results',
  // Lightning pages are slow to load the first time, and the wizard waits on Apex calls.
  timeout: 180_000,
  expect: { timeout: 30_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]] : [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  use: {
    ...devices['Desktop Chrome'],
    viewport: { width: 1440, height: 900 },
    navigationTimeout: 90_000,
    actionTimeout: 30_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    { name: 'login', testMatch: /login\.setup\.ts/ },
    {
      name: 'chromium',
      dependencies: ['login'],
      use: { storageState: '.auth/session.json' }
    }
  ]
});
