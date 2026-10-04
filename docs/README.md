# AI Assist documentation

Technical documentation for the AI Assist managed package. It lives in the repository so that it changes in the same pull request as the code it describes.

## What is where

| Folder or file                               | Holds                                                                        | Written from                                              |
| -------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------- |
| [review/](review/README.txt)                 | The ordered review checklist for every component in the package              |                                                           |
| [templates/](templates/)                     | Blank pages to copy when documenting a component                             |                                                           |
| [objects/](objects/)                         | One page per object, platform event, custom metadata type and custom setting | `OBJECT.md`, `PLATFORM_EVENT.md`, `CONFIGURATION_TYPE.md` |
| [objects/ERD.md](objects/ERD.md)             | The entity relationship diagram and the table of every relationship field    | Field metadata                                            |
| `features/`                                  | One page per feature: its classes, entry points, security and limits         | `FEATURE.md`                                              |
| `access/`                                    | One page per permission set                                                  | `PERMISSION_SET.md`                                       |
| [SECURITY_MODEL.md](SECURITY_MODEL.md)       | The security contract the Apex layers are built to                           |                                                           |
| [DATA_FLOW.md](DATA_FLOW.md)                 | What data goes where, including out of the org                               |                                                           |
| [MESSAGING_SERVICE.md](MESSAGING_SERVICE.md) | How a message is processed                                                   |                                                           |
| [INSTALL.md](INSTALL.md)                     | Installing and setting up                                                    |                                                           |
| [OPERATIONS.md](OPERATIONS.md)               | Running AI Assist after set-up                                               |                                                           |

`features/` and `access/` are created when the first page is added.

## Adding a page

1. Copy the matching template from `templates/` into the folder in the table above.
2. Name it after the component: `objects/AIAgent__c.md`, `features/USAGE_LIMITS.md`, `access/AIAssistUser.md`.
3. Fill it in, delete the sections that do not apply, and tick the "Documented" box in the review checklist.

## What belongs here and what belongs in the knowledge base

| Here, in the repository                                                  | In the knowledge base                                      |
| ------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Anything that must stay true to the code: fields, rules, classes, access | Anything written for people who do not read the repository |
| Diagrams as Mermaid text, which GitHub and VS Code render                | Polished visuals, screenshots, walkthrough videos          |
| Reviewed in pull requests                                                | Admin and end-user guides, release notes, support articles |

Each knowledge article links back to the page here that it is drawn from, so there is one source to correct when the model changes.

Knowledge base: _add the link here once the space exists._
