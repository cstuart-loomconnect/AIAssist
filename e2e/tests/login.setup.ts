import { test as setup, expect } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'fs';

// Logs in once through the frontdoor URL from `sf org open --url-only`, then saves the session and the
// Lightning origin for the tests. No username or password is ever stored.
setup('log in to the org', async ({ page }) => {
  const frontdoorUrl = process.env.SF_FRONTDOOR_URL;
  if (!frontdoorUrl) throw new Error('SF_FRONTDOOR_URL is not set. Run: export SF_FRONTDOOR_URL=$(sf org open --url-only --json | jq -r .result.url)');

  // [1] Open the frontdoor URL, which signs in and redirects to Lightning
  await page.goto(frontdoorUrl);
  await page.waitForURL(/\/lightning\//, { timeout: 120_000 });
  await expect(page.locator('one-app-nav-bar, .slds-global-header').first()).toBeVisible({ timeout: 120_000 });

  // [2] Save the session cookies and the Lightning origin for the tests
  mkdirSync('.auth', { recursive: true });
  await page.context().storageState({ path: '.auth/session.json' });
  writeFileSync('.auth/origin.txt', new URL(page.url()).origin);
});
