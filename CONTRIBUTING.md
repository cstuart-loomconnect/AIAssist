# Contributing to AIAssist

## Branching

- `master`: release-ready code only.
- `development`: integration branch. Every feature is merged here and tested together.
- `feature/<name>`: one branch per piece of work, created from `development`.

Open pull requests from `feature/*` into `development`. Merge `development` into `master` only for a release.
Keep your branch current with `git merge development`.

## Pull request titles

Titles must follow `type: subject`, with a lowercase subject. Allowed types: `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `chore`.

Examples: `feat: add agent wizard`, `fix: handle empty message queue`.

PRs are labelled automatically (`apex`, `lwc`, `aura`, `objects`, `flows`, `security`, `ci`, `docs`) from the files they change.

## Naming conventions

API names are checked on every PR by `scripts/ci/check-naming.js`. The `__c`, `__mdt`, `__e` suffix is added by Salesforce and is not checked; the name in front of it is.

| Metadata                                                                                        | Rule                          | Example                                     |
| ----------------------------------------------------------------------------------------------- | ----------------------------- | ------------------------------------------- |
| Custom objects, fields, custom metadata types                                                   | PascalCase, letters and digits only | `AIAgent__c`, `ModelName__c`          |
| Record types, validation rules, field sets, list views                                          | PascalCase                    | `RequireAgentName`                          |
| Custom metadata records                                                                         | PascalCase                    | `AIConfig.DefaultModel`                     |
| Apex classes and triggers                                                                       | PascalCase                    | `AIAgentManager`                            |
| Lightning Web Components                                                                        | camelCase                     | `aiChatWindow`                              |
| Aura components                                                                                 | Letters and digits only       | `aiConsole`                                 |
| Permission sets, flows, flexipages, apps, tabs, static resources, credentials                   | PascalCase                    | `AIAssistAdmin`                             |

Not allowed anywhere: spaces, underscores, hyphens or other symbols in the name, and spaces in any file or folder name under `force-app` (layouts and reports are exempt).

If a name genuinely has to break a rule, for example a name that already shipped in a released package, add its path to `.github/naming-exceptions.txt` with a comment explaining why.

## Automated checks

| Check                     | What it does                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------- |
| Prettier + ESLint         | Formatting and LWC/Aura lint                                                          |
| SLDS Validator            | SLDS styling rules in LWC HTML and CSS                                                |
| Salesforce Code Analyzer  | PMD, ESLint, security and AppExchange rules. Fails on High severity or worse          |
| Naming conventions        | The table above                                                                       |
| Dependency audit          | `npm audit` at high severity                                                          |
| Scratch org + Apex tests  | Creates a scratch org, deploys, runs all local tests and requires 75% coverage        |
| PR title / labels         | Conventional title and area labels                                                    |
| Nightly build             | Full scratch org test run on `development` every night. Opens an issue if it fails    |

Results are posted as a comment on each pull request.
