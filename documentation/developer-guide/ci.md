# CI and releases

This page says what each GitHub workflow does, which ones are currently switched off, the pull request and commit conventions, and how this documentation site is built and published. The source files are in `.github/workflows/` and `CONTRIBUTING.md`.

## Workflows

| Workflow | File | What it does | Trigger now |
|---|---|---|---|
| PR Validation | `pr-validation.yml` | Runs the checks below on a pull request or push. | **Switched off.** Manual (`workflow_dispatch`) only. |
| PR Hygiene | `pr-hygiene.yml` | Labels a PR by the files it changes and checks the title format. | **Switched off.** Manual only. |
| Nightly Build | `nightly.yml` | Full scratch org test run against `development`. Opens or updates an issue called "Nightly build failing on development" if it fails. | **Schedule switched off.** Manual only. |
| Scratch Org Apex Tests | `scratch-org-tests.yml` | Reusable. Creates a scratch org, deploys, runs all local tests, enforces coverage, deletes the org. | Called by the two above (`workflow_call`). |
| Documentation site | `docs-site.yml` | Generates the reference pages, builds this site and publishes it to GitHub Pages. | **On.** Push to `development`, or manual. |

The switched-off triggers are commented out in the YAML with a "CI switched off" note, and [Codebase health](../codebase-health.md) counts them. Until they are switched back on, none of the checks below run on a pull request automatically: run the equivalent locally (see the commands in each workflow) or start the workflow by hand from the Actions tab.

### What PR Validation checks

| Job | Check |
|---|---|
| Prettier + ESLint | `npm run prettier:verify` and ESLint over the `aura` and `lwc` folders. |
| SLDS Validator | SLDS styling rules in LWC HTML and CSS. |
| Salesforce Code Analyzer | PMD, ESLint, regex, retire-js and security rules with the `Recommended` and `AppExchange` selectors. Fails on severity 2 (High) or worse. Configured in `code-analyzer.yml`. |
| Dependency audit | `npm audit --audit-level=high` (does not fail the run). |
| Naming conventions | `node scripts/ci/check-naming.js`. Exceptions go in `.github/naming-exceptions.txt`. |
| Scratch org + Apex tests | Runs when the checks above have not failed. Creates a scratch org from `config/project-scratch-def.json`, does a check-only deploy, deploys, assigns the permission sets (`scripts/ci/assign-permsets.js`), runs `RunLocalTests` and requires 75% coverage (`scripts/ci/check-coverage.js`). |
| Post results to PR | On a pull request, posts one comment with the results (`scripts/ci/pr-comment.js`). |

The scratch org job needs a repository secret, `DEVHUB_SFDX_AUTH_URL`, created with `sf org auth show-sfdx-auth-url --target-org <devhub> --no-prompt`.

Dependabot (`.github/dependabot.yml`) opens weekly update pull requests for npm and GitHub Actions, targeting `development`.

## Branches

| Branch | Use |
|---|---|
| `development` | The main branch. Features merge here, the nightly build targets it and the docs site is published from it. |
| `feature/<name>` | One branch per piece of work, created from `development`. |
| `master` | Release-ready code only, and the GitHub default branch. Merge `development` into it only for a release. |

Scheduled workflows only run from the default branch, so the nightly schedule would only start working once it reaches `master`.

## Pull requests and commits

Open pull requests from `feature/*` into `development`. The title (and the commit messages in this repository's history) use `type: subject`, with a lowercase subject.

| Type | Use for |
|---|---|
| `feat` | A new capability |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `refactor` | A change that does not alter behaviour |
| `test` | Tests only |
| `perf` | A performance change |
| `build` | Build or dependency changes |
| `ci` | Workflows and CI scripts |
| `chore` | Anything else that is housekeeping |

Examples: `feat: add agent wizard`, `fix: handle empty message queue`. Dependabot titles are exempt.

PRs are labelled from the files they change (`.github/labeler.yml`):

| Label | Files |
|---|---|
| `apex` | `classes`, `triggers` |
| `lwc` | `lwc` |
| `aura` | `aura` |
| `objects` | `objects`, `customMetadata` |
| `flows` | `flows` |
| `security` | `permissionsets`, `externalCredentials`, `namedCredentials` |
| `ci` | `.github`, `scripts`, `code-analyzer.yml`, `package.json` |
| `docs` | any `.md` file |

API names must follow the table in `CONTRIBUTING.md` (PascalCase for objects, fields, classes and permission sets; camelCase for Lightning web components; letters and digits only for Aura). Run `node scripts/ci/check-naming.js` to check before you push.

A pre-commit hook (`.husky`) runs `lint-staged`: Prettier and ESLint on the files you changed, plus `sfdx-lwc-jest` on related LWC files with `--passWithNoTests`.

## The documentation site

The site is MkDocs Material. The hand-written pages are in `documentation/` and the navigation is in `mkdocs.yml`. Some pages are generated from the source on every build, so they cannot go stale, and are not committed (they are listed in `.gitignore`):

| Generated | Contents |
|---|---|
| `documentation/_stats.md` | The numbers on the home page |
| `documentation/changelog.md` | Merged pull requests, from git |
| `documentation/codebase-health.md` | Checks worked out from the source |
| `documentation/reference/` | Apex, data model and object pages, Lightning web components, permission sets |

`scripts/docs/generate.py` writes them. It uses only the Python standard library and git, so run it from the repository root, with full git history if you want a complete changelog.

### Run it locally

```bash
pip install -r scripts/docs/requirements.txt
python3 scripts/docs/generate.py
mkdocs serve
```

`npm run docs:serve` does the last two steps. Use `mkdocs build --strict` to check for broken links: the publish workflow uses it, so a warning fails the build.

### How it is published

`docs-site.yml` runs on every push to `development` that touches `documentation/`, `mkdocs.yml`, `scripts/docs/`, `force-app/`, `docs/known-issues.txt` or the workflows. It checks out the full history, installs Python 3.12 and the requirements, runs `generate.py`, then `mkdocs build --strict`, and deploys the `site` folder to GitHub Pages.

One-off setup in GitHub: **Settings > Pages > Build and deployment > Source = GitHub Actions**, and allow the `development` branch under **Settings > Environments > github-pages > Deployment branches**.

To edit a hand-written page, change the file under `documentation/` and open a `docs:` pull request. Do not edit generated pages: change the source, or `scripts/docs/generate.py`.
