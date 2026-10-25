# Browser tests

End-to-end tests that drive AI Assist in a real browser, the way a user does. They use [Playwright](https://playwright.dev) and run against a Salesforce org that already has `force-app` deployed and the AI Assist permission sets assigned.

None of this is part of the package: the folder sits outside `force-app`, so it is never deployed or packaged.

## What is covered

- `tests/agent-wizard.spec.ts`: the AI Agent Wizard tab.
  - Creates a blank agent, fills in Basics, goes through every step and saves it as a draft, then checks the `AIAgent__c` record with SOQL and finds it in the list.
  - Checks that Basics will not move on until the name and an object are filled in.

These need no seed data and never call an AI provider.

## In CI

The **Browser tests** workflow (`.github/workflows/browser-tests.yml`) creates a scratch org, deploys `force-app` and runs only these tests, with no Apex unit tests. Start it by adding the `e2e` label to a pull request (it then reruns on every push while the label is on), or by hand from **Actions > Browser tests > Run workflow**. PR Validation does not run them. It logs in with `sf org open --url-only`, so no password is stored. Failures show as annotations on the PR, and the Playwright report (screenshots, video and a step-by-step trace) is attached to the run as the `e2e-report` artifact.

## Run them on your machine

You need Node 22 and the Salesforce CLI, logged in to a scratch org or sandbox with the package deployed and the permission sets assigned.

```bash
cd e2e
npm install
npx playwright install chromium

# Log in through the CLI and hand the session to Playwright
export SF_FRONTDOOR_URL=$(sf org open --url-only --json | jq -r .result.url)
npx playwright test

# Open the report, with screenshots and traces of any failure
npx playwright show-report
```

The tests check records with `sf data query` against the CLI's default org. Set `SF_TARGET_ORG` to an alias to use another one.

Add `--headed` to watch the browser, or `--ui` to step through a test.

## Writing a test

- Find elements by role and visible text first (`getByRole('button', { name: 'Next' })`), then by class or `data-*` attribute. Do not use element ids: Lightning rewrites them at runtime.
- Give each record a unique name with `uniqueSuffix()`, so reruns never clash.
- Check what was saved with `soql()` as well as what the screen shows.
