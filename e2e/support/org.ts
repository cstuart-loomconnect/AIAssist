import { execFileSync } from 'child_process';
import { readFileSync } from 'fs';
import type { Page } from '@playwright/test';

// The Lightning origin the login setup saved, e.g. https://xyz.scratch.lightning.force.com
export function lightningOrigin(): string {
  return readFileSync('.auth/origin.txt', 'utf8').trim();
}

// Opens a Lightning tab by its API name and waits for the page shell to load.
export async function openTab(page: Page, tabApiName: string): Promise<void> {
  await page.goto(`${lightningOrigin()}/lightning/n/${tabApiName}`);
}

// Runs a SOQL query with the Salesforce CLI and returns the records. Uses the CLI's default org,
// or SF_TARGET_ORG when it is set, so it checks the same org the browser is logged in to.
export function soql<T = Record<string, unknown>>(query: string): T[] {
  const args = ['data', 'query', '--query', query, '--json'];
  if (process.env.SF_TARGET_ORG) args.push('--target-org', process.env.SF_TARGET_ORG);
  const output = execFileSync('sf', args, { encoding: 'utf8' });
  return JSON.parse(output).result.records as T[];
}

// A short value that makes record names unique between runs, so a rerun never clashes with an earlier one.
export function uniqueSuffix(): string {
  return Date.now().toString(36).toUpperCase();
}
