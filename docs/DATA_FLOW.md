# AI Assist data flow

What data AI Assist reads, what it sends to an AI provider, what it keeps, and who can see it. For a security reviewer or a customer's data protection officer.

## 1. The short version

- Data goes from the customer's Salesforce org to the AI provider the customer chose, and back. **Nothing passes through Loom Connect.** Loom Connect operates no server in the path and receives no customer data.
- The call is made by the customer's org, with the customer's own API key, under the customer's own agreement with the provider.
- Personal data in registered fields is replaced with stand-in values before it leaves Salesforce.
- The only thing Loom Connect receives is two counts a month per customer (section 7).

## 2. One turn

1. The user sends a message. It is saved as a message in their conversation.
2. A background job, running as that user, loads the conversation's history in user mode and the agent's configuration in system mode.
3. The request is assembled: the system prompt (persona, prompt template, rules), the conversation so far, and the definitions of the agent's data sources.
4. Personal data is masked (section 4).
5. The org calls the provider through the Named Credential on the model configuration.
6. If the model asks for data, the data source runs as the user, its results are masked, and the org calls the provider again.
7. The reply is saved. Stand-in values are put back when it is shown to the user who owns the conversation.

## 3. What is sent to the provider

| Sent                                                                                   | Not sent                                                    |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| The agent's persona and prompt template text                                           | The API key (the platform adds it as a header)              |
| The conversation's messages, up to 8,000 characters each, bounded by count and size    | Messages of other conversations                             |
| Names and descriptions of the agent's data sources and Workflow Actions                | Records the model did not ask a data source for             |
| Records a data source returned, limited to its row cap and to fields the user can read | Fields the user cannot read                                 |
| The user's language                                                                    | The user's name, email or Id, unless a record contains them |

A data source runs as the user: sharing and field-level security apply, so the model can never be shown a record or field the user could not open.

## 4. Masking

- An administrator registers objects whose fields hold personal data. The registry is synced by the maintenance job.
- Before a request is sent, values in registered fields are replaced with stand-ins. The mapping from real to stand-in value is kept in `AIPIIMapping__c`, which no permission set can read.
- The reply is restored for display to the user who owns the conversation.
- If masking fails, the request is **not sent**. The turn fails with a privacy message and a violation is recorded.
- Each provider call records which objects and field names were sent and whether masking ran (`AIExecutionStep__c`, `AIPIIMaskingRecord__c`). Names and counts only, never values.

**Limit today:** the package ships no PII type or masking rule records. Without them every masked value is a generic `REDACTED-n` stand-in. Field-type-aware stand-ins need those records added.

Text a user types into a message is not masked unless it matches a registered value. Tell users not to paste personal data that is not on the record.

## 5. Providers

| Provider          | Endpoint                          | Notes                                                      |
| ----------------- | --------------------------------- | ---------------------------------------------------------- |
| Anthropic         | `api.anthropic.com`               | Messages API.                                              |
| OpenAI            | `api.openai.com`                  | Chat Completions API.                                      |
| OpenAI-compatible | The base URL the customer enters  | Same request shape as OpenAI.                              |
| Azure OpenAI      | The customer's own Azure resource | The deployment is in the URL; data stays in that resource. |

What the provider does with the data, where it is processed and how long it is kept are set by **the customer's agreement with that provider**, not by AI Assist. Check the provider's terms for retention, training use and region before choosing a tier. AI Assist sends no instruction that changes them.

## 6. What is kept in Salesforce

All of it is in the customer's org, in the package's objects.

| Record         | Holds                                                           | Kept for (default)                             |
| -------------- | --------------------------------------------------------------- | ---------------------------------------------- |
| Conversation   | Agent, record it is about, status, totals                       | The agent's retention (90 days)                |
| Message        | What the user and the AI said                                   | 30 days, or the conversation's life if shorter |
| Execution step | What ran: provider, model, objects and field names sent, timing | 7 days                                         |
| Step payload   | The request and response JSON, already masked                   | Only when Step Capture Mode is Full            |
| PII mapping    | Real to stand-in values                                         | With the conversation                          |
| Feedback       | Rating and comment                                              | With the conversation                          |
| Usage          | Counts per user, agent, model and day                           | Kept; anonymised by a deletion request         |
| Violation      | Rule, type, severity; no message content                        | 365 days, once reviewed                        |
| Platform log   | Errors and audit entries                                        | 30 days                                        |

Retention runs daily and continues while AI Assist is switched off. A conversation on legal hold, with its messages and steps, is kept until the hold is lifted. A data deletion request removes a person's conversations on approval and records what was removed.

## 7. What Loom Connect receives

Through Salesforce's licence management, once a day:

| Value                 | What it is                             |
| --------------------- | -------------------------------------- |
| `MonthlyMessagesUsed` | The number of messages this month.     |
| `MonthlyErrors`       | The number of failed turns this month. |

Two integers. No content, no user, no record, no prompt. Loom Connect sets the customer's plan limits the same way, in the other direction.

## 8. Who can see what inside the org

| Data                           | User                            | Super User   | Admin                            |
| ------------------------------ | ------------------------------- | ------------ | -------------------------------- |
| Their own conversations        | Yes                             | Yes          | Yes                              |
| Other users' conversations     | Only under the visibility rules | Yes          | Conversation, not message bodies |
| Prompts and connection details | No                              | Prompts only | Yes                              |
| Execution steps and payloads   | No                              | Yes          | Timings, not payloads            |
| PII mappings                   | No                              | No           | No                               |

The visibility rules are in section 4 of [SECURITY_MODEL.md](SECURITY_MODEL.md).
