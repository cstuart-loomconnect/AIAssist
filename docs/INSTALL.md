# Installing and setting up AI Assist

For the administrator installing AI Assist and connecting it to an AI provider. Security detail is in [SECURITY_MODEL.md](SECURITY_MODEL.md); running it day to day is in [OPERATIONS.md](OPERATIONS.md).

## 1. What installing does

| Org                    | After install                                                                                             |
| ---------------------- | --------------------------------------------------------------------------------------------------------- |
| Production             | Settings rows created from their defaults. AI Assist is switched on and recorded against the org.         |
| Sandbox or scratch org | Settings rows created. AI Assist is switched **off** until you activate it there.                         |
| Any, on upgrade        | Your settings are left alone. Numbered upgrade steps newer than your previous version run once, in order. |

A first install also schedules the daily maintenance job. Nothing else is created: credentials, agents and model configurations are yours to set up.

## 2. Getting started

Assign **AI Assist Admin** to yourself first. Setting up a credential also needs **Customize Application**, which comes from your own profile or permission set: the package's permission sets carry no setup rights.

## 3. Connecting a provider

1. **External Credential**: protocol Custom. Add a principal named `AIAssist` and an authentication parameter `ApiKey` holding the key. Add a custom header from the table below.
2. **Named Credential**: the provider's URL, your External Credential, **Allow Formulas in HTTP Header** on, **Generate Authorization Header** off, and `LoomConnect` under Allowed Namespaces for Callouts.
3. **Principal access**: on the External Credential, map the principal to a permission set your AI Assist users hold. They also need Read on User External Credentials.
4. **Model configuration**: enter the Named Credential's name, the model, and the API path.
5. Send a test message to check the connection.

## 4. Providers

| Provider value | Use for                                   | Base URL                             | API path                                     | Key header                                           |
| -------------- | ----------------------------------------- | ------------------------------------ | -------------------------------------------- | ---------------------------------------------------- |
| Anthropic      | Claude models                             | `https://api.anthropic.com`          | `/v1/messages`                               | `x-api-key: {!$Credential.<name>.ApiKey}`            |
| OpenAI         | OpenAI, and any OpenAI-compatible service | `https://api.openai.com` or your own | `/v1/chat/completions` or the service's path | `Authorization: Bearer {!$Credential.<name>.ApiKey}` |

- **Anthropic** also needs the version header `anthropic-version: 2023-06-01` on the model configuration.
- **OpenAI-compatible**: choose OpenAI and use the service's base URL on the Named Credential. The model name goes in Model Identifier.

## 5. Build in production as Assigned Users Only

Build and test an agent in production without exposing it:

1. Create the agent with **Access Mode: Assigned Users Only** (the default) and assign only yourself.
2. Test it. Nobody else is offered the agent.
3. When it is ready, assign the people or permission sets who should use it, or change Access Mode to All AI Assist Users.

A sandbox is switched off after a refresh (the sandbox guard), so production is where an agent is finally proven. Assigned Users Only is what makes that safe.

## 6. Moving configuration between orgs

Configuration records carry a unique `DeveloperName__c`, set when they are created. Use it as the External Id when you load them into another org, so a record is matched to itself and lookups resolve by name:

| Object                 | Match on           |
| ---------------------- | ------------------ |
| AI Agent               | `DeveloperName__c` |
| AI Model Configuration | `DeveloperName__c` |
| AI Prompt Template     | `DeveloperName__c` |
| AI Data Source         | `DeveloperName__c` |
| AI Workflow Action     | `DeveloperName__c` |

Order: model configurations, agents, prompt templates, data sources and actions, then the junction records. Not moved by this: the Named Credential and its key (create them in the target org), permission set assignments, and the custom settings.
