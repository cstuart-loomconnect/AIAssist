import { test, expect, type Page } from '@playwright/test';
import { openTab, soql, uniqueSuffix } from '../support/org';

// The AI Agent Wizard tab, driven the way an admin uses it. A fresh scratch org has no model
// configurations, data sources or workflow actions, so these paths need no seed data and never call an AI.

const WIZARD_TAB = 'AIAgentWizard';

// The Next button changes its label on some steps: "Next (no model)" when there are no active models,
// "Continue read-only" when no workflow actions are picked.
const NEXT_BUTTON = /^(Next|Next \(no model\)|Continue read-only)$/;

// The panel title of each step after Basics, in order. These match STEP_NAMES in aiAgentWizardSettings.js.
const STEP_TITLES_AFTER_BASICS = ['Model', 'Skills', 'Data sources', 'Workflow actions', 'Conversations', 'Limits', 'Access', 'Review and activate'];

type AgentRecord = { Name: string; DeveloperName__c: string; IsActive__c: boolean; ObjectApiNames__c: string | null; AIModelConfiguration__c: string | null };

// Opens the wizard and goes from the list of agents to the first step of a blank agent.
async function startBlankAgent(page: Page) {
  await openTab(page, WIZARD_TAB);
  await expect(page.getByRole('heading', { name: 'AI Agent Wizard', level: 1 })).toBeVisible({ timeout: 90_000 });

  // The list has a "+ New agent" button at the top, and a second one in the empty state.
  await page.getByRole('button', { name: '+ New agent' }).first().click();
  await expect(page.getByRole('heading', { name: 'Create an agent' })).toBeVisible();

  await page.getByRole('button', { name: /Blank agent/ }).click();
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(panelTitle(page)).toHaveText('Basics');
}

function panelTitle(page: Page) {
  return page.locator('c-ai-agent-wizard h2.aiaw-panel-title');
}

test.describe('AI Agent Wizard', () => {
  test('creates a draft agent with no model, then lists it', async ({ page }) => {
    const agentName = `E2E Draft ${uniqueSuffix()}`;

    await test.step('start a blank agent', async () => {
      await startBlankAgent(page);
    });

    let developerName = '';
    await test.step('fill in Basics', async () => {
      await page.getByLabel(/Agent name/).fill(agentName);

      // The API name is made from the name until the admin edits it.
      const apiNameInput = page.getByLabel(/API name/);
      await expect(apiNameInput).not.toHaveValue('');
      developerName = await apiNameInput.inputValue();

      await page.getByPlaceholder('Search objects...').fill('Account');
      await page.locator('button.aiawba-match[data-key="Account"]').click();
      await expect(page.locator('.aiawba-chip', { hasText: 'Account' })).toBeVisible();

      await page.getByLabel(/Description/).fill('Created by the Playwright browser tests.');
    });

    await test.step('go through every step to Review', async () => {
      for (const title of STEP_TITLES_AFTER_BASICS) {
        await page.getByRole('button', { name: NEXT_BUTTON }).click();
        await expect(panelTitle(page)).toHaveText(title);
      }
    });

    await test.step('save as a draft', async () => {
      await page.getByRole('button', { name: 'Save as draft' }).click();
      await expect(page.getByRole('heading', { name: `${agentName} is saved as a draft` })).toBeVisible();
    });

    await test.step('check the saved record', async () => {
      const agents = soql<AgentRecord>(`SELECT Name, DeveloperName__c, IsActive__c, ObjectApiNames__c, AIModelConfiguration__c FROM AIAgent__c WHERE DeveloperName__c = '${developerName}'`);
      expect(agents).toHaveLength(1);
      expect(agents[0].Name).toBe(agentName);
      expect(agents[0].IsActive__c).toBe(false);
      expect(agents[0].ObjectApiNames__c ?? '').toContain('Account');
      expect(agents[0].AIModelConfiguration__c).toBeNull();
    });

    await test.step('find it in the list as a draft', async () => {
      await page.locator('c-ai-agent-wizard-done').getByRole('button', { name: 'Back to all agents' }).click();
      await page.getByPlaceholder('Search by name, page or model').fill(agentName);
      const row = page.locator('tr.aiawl-row', { hasText: agentName });
      await expect(row).toBeVisible();
      await expect(row).toContainText('Draft');
    });
  });

  test('will not leave Basics until the required fields are filled in', async ({ page }) => {
    await startBlankAgent(page);

    await page.getByRole('button', { name: NEXT_BUTTON }).click();

    await expect(page.getByText('Enter a name.')).toBeVisible();
    await expect(page.getByText('Choose at least one object.')).toBeVisible();
    await expect(panelTitle(page)).toHaveText('Basics');
  });
});
