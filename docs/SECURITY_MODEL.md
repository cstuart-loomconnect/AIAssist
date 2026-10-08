# AI Assist security model

How AI Assist decides who may see and do what, where it runs with more access than the user and why, and what protects the org it is installed in. Companion documents: [DATA_FLOW.md](DATA_FLOW.md) for what leaves Salesforce, [INSTALL.md](INSTALL.md) for set-up, [OPERATIONS.md](OPERATIONS.md) for running it.

## 1. Principles

1. **Nothing is granted by default.** The three permission sets list every field on purpose. None carries a system permission, Modify All, or Delete on conversations, violations or terms acknowledgments.
2. **Object permission gates configuration; ownership gates conversations.** Configuration objects are Public Read/Write, but only the Admin set can write them. Conversation data is Private.
3. **Sharing decides first.** A setting inside AI Assist can narrow what the org's sharing allows. It never widens it.
4. **Configuration is read in system mode, the user's data in user mode.** The user is never given access to prompts, connection details or other users' usage in order to chat.
5. **Nobody reads PII mappings.** `AIPIIMapping__c` (real value to stand-in value) is granted to no permission set.
6. **Audit records are write-once.** Terms acknowledgments are locked by validation rules as well as field permissions.
7. **The key is never held.** A provider API key goes straight to the platform's credential store. AI Assist does not store, log or return it.

## 2. Access matrix

CRED = create / read / edit / delete. `+all` = View All Records.

| Object                     | OWD                | User | Super User | Admin    |
| -------------------------- | ------------------ | ---- | ---------- | -------- |
| AIAgentAssignment__c       | ControlledByParent | -    | R          | CRED     |
| AIAgentDataSource__c       | ControlledByParent | -    | R          | CRED     |
| AIAgentObject__c           | ControlledByParent | -    | R          | CRED     |
| AIAgentWorkflowAction__c   | ControlledByParent | -    | R          | CRED     |
| AIAgent__c                 | ReadWrite          | R    | R          | CRED     |
| AIConversationMessage__c   | ControlledByParent | CR   | CR +all    | CR       |
| AIConversation__c          | Private            | CRE  | CRE +all   | CRE +all |
| AIDataSource__c            | ReadWrite          | -    | R          | CRED     |
| AIExecutionStep__c         | ControlledByParent | -    | R +all     | R +all   |
| AIFeedback__c              | Private            | CR   | CR +all    | CR +all  |
| AIModelConfiguration__c    | ReadWrite          | -    | R          | CRED     |
| AIPIIFieldMetadata__c      | ControlledByParent | -    | R          | R        |
| AIPIIMapping__c            | ControlledByParent | -    | -          | -        |
| AIPIIMaskingRecord__c      | ControlledByParent | -    | R +all     | R +all   |
| AIPIIRegistry__c           | ReadWrite          | -    | R          | CRED     |
| AIPlatformLog__c           | Private            | -    | R +all     | R +all   |
| AIPromptTemplate__c        | ReadWrite          | -    | R          | CRED     |
| AITermsAcknowledgment__c   | Private            | CR   | CR         | CR +all  |
| AIUsagePolicyAssignment__c | ControlledByParent | -    | R          | CRED     |
| AIUsagePolicy__c           | ReadOnly           | -    | R          | CRED     |
| AIUserSettings__c          | ReadWrite          | -    | R          | CRE      |
| AIWorkflowAction__c        | ReadWrite          | -    | R          | CRED     |
| The four platform events   | -                  | CR   | CR         | CR       |

Field permissions: User 39, Super User 233, Admin 246. `AIChatCommand__mdt` is Protected, so only the package ships chat commands. The two custom settings are Public; only an administrator edits them.

**Roles.** Each permission set is self-contained: assign one.

- **AI Assist User** chats. Creates and reads their own conversations, messages, feedback and terms acknowledgment. Cannot edit a message once written.
- **AI Assist Super User** reads every conversation, message, step, feedback and log, reads all configuration, including connection details, but cannot change it, and reviews violations.
- **AI Assist Admin** builds configuration and sets per-user limits. Sees all conversations, feedback, logs and acknowledgments. Admin has no View All on messages, so cannot read other users' message bodies.

**Custom permissions.**

| Permission                        | Grants                                                                                     | In           |
| --------------------------------- | ------------------------------------------------------------------------------------------ | ------------ |
| `AIAssistManageConfiguration`     | The set-up controllers: credentials, connection test, health check, plan usage, checklist. | Admin        |
| `AIAssistViewSharedConversations` | Lets the All Conversations scope take effect without View All. Never widens sharing.       | Super, Admin |
| `AIAssistDebugMode`               | The debug trace of the user's own replies, as Debug Mode Enabled on a policy does.         | Super, Admin |
| `AIAssistRunActions`              | Running suggested Workflow Actions, as Workflow Actions Enabled on a policy does.          | Admin        |

## 3. Where AI Assist runs with more access than the user

Four classes are `without sharing`. Every statement in them names its access level, and none decides who may do something: the caller authorises the user first.

| Class                                    | Why it cannot run with sharing                                                                                                                                                                                                      |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AIMessagingSelector`                    | Reads the configuration a turn runs on (model connection, prompt, data sources, user settings, assignments, usage). Only Admin and Super User may read those; a chat user must not be given that access in order to chat.           |
| `AIMessagingDataService`                 | Writes system-managed data the user cannot write: a message's status and tokens, the reply, usage rows, evidence. It also marks a write as the package's own, which is what stops a user creating a message that looks like the AI. |
| `AIConversationLockService`              | Sets and clears the processing lock on a conversation, a system-managed field the user cannot edit, including when a finalizer hands the lock on.                                                                                   |
| `AIAssistGlobalUtility.UniquenessLookup` | Checks a Developer Name against every record of the object. The unique index is global, so a check limited to what the user can see would let a clash through and fail the save.                                                    |

Everything else is `with sharing` or `inherited sharing`. `AIConversationVisibilityService` was `without sharing` and is now `with sharing` (section 4). Batches and the scheduler run in system mode because retention and housekeeping apply to every user's records.

## 4. Who may read a conversation

A conversation can be sent to, retried, closed, resumed, exported and acted on only by the user who started it. Reading someone else's is decided by `AIConversationVisibilityService`, which is `with sharing` and reads in user mode:

1. **Sharing.** The viewer must already be able to read the record: ownership, the role hierarchy, or View All.
2. **The agent.** `ConversationVisibility__c` must be Global. Private (the default) means the starter only, whatever the viewer holds.
3. **The viewer's scope** (`ConversationVisibilityScope__c`, from their usage policies and user settings):

| Scope                           | Reaches                                                                                                              |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| My Conversations Only (default) | Nobody else.                                                                                                         |
| My Subordinates Conversations   | Starters in a role below the viewer's.                                                                               |
| All Conversations               | Whatever sharing gives, and only for a viewer with View All on AI Conversation or `AIAssistViewSharedConversations`. |

4. **The record.** A conversation about a record is shown only to a viewer who can read that record.

A blank or unrecognised setting is the narrowest one. A conversation the viewer may not read gets the same answer as one that does not exist.

## 5. Workflow Actions, Flows and Apex

An action runs only when all of these hold, checked in `AIWorkflowActionDispatcher`: the plan includes actions, the application is on, the user may run actions, the agent still admits the user, the action is active and assigned to the agent, and a Write action has been confirmed. Every outcome, including a refusal, is recorded as an execution step.

**A Flow does not run as the user.** A Flow started from Apex runs in system context: the user's object and field permissions are not applied. AI Assist therefore controls what a Flow is handed:

| Rule                           | Detail                                                                                                                                                      |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Only declared inputs           | An input the action's schema does not declare is dropped and logged by name.                                                                                |
| `recordId` is the server's     | It is the conversation's own record. A `recordId` from the browser is dropped. This applies to Apex actions too.                                            |
| Record access is checked       | Every record Id passed to a Flow is checked with `UserRecordAccess`: read access, or edit access for a Write action. One missing record refuses the action. |
| System context without sharing | A Flow in that mode is refused, when the action is saved and again when it runs.                                                                            |

An Id that is not a shareable record (a record type, a queue) has no access row and is refused. Pass a name instead.

**Apex.** A class named on a data source or action is checked to exist and implement the package's interface before it is instantiated, at save and at run time. It runs in the user's transaction with the sharing it declares. A data source that writes to the database fails the turn and is rolled back.

## 6. Provider credentials

- Calls go through a Named Credential and nowhere else. The endpoint is the credential named on the model configuration plus its API path; there is no free URL field.
- The key is passed to the platform's credential store. It is never written to a record or a log, never returned, and is removed from any error text before that is logged or shown. Tests assert this.
- The header that carries the key is a formula on the External Credential, so the key is added by the platform at callout time.
- Users reach the credential through a named principal mapped to a permission set (`AI Assist Credential Access`, created on request).
- Every credential change is written to the Platform Log by name and user.

## 7. Limits on use

| Control              | Setting on `AIAssistSettings__c` | Behaviour                                                                               |
| -------------------- | -------------------------------- | --------------------------------------------------------------------------------------- |
| Messages in flight   | `MaxMessagesInFlight__c`         | Extra messages wait as Queued and start when a place is free. Never more than 200 jobs. |
| Daily message budget | `DailyMessageBudget__c`          | New messages are refused for the rest of the org's day.                                 |
| Daily token budget   | `GlobalTokenBudgetPerDay__c`     | New messages are refused for the rest of the org's day.                                 |
| Rate limit           | `MaxMessagesPerUserPerMinute__c` | One user's messages in any 60 seconds.                                                  |
| Message length       | `MaxMessageLength__c`            | At most 8,000 characters.                                                               |

## 8. Sandbox guard

`ActivatedOrgId__c` records the org AI Assist was switched on in. Settings copied into another org (a sandbox refreshed from production) carry production's Id, so AI Assist treats itself as off there: no provider is called with production's configuration until an administrator activates it. Retention still runs. A new install in a sandbox or scratch org starts switched off.

## 9. Retention, deletion and legal hold

- Deletion happens only inside the package. No user holds Delete on conversations, violations or acknowledgments.
- Conversations expire by their agent's retention.
- A conversation on legal hold is never deleted, and neither are its messages or steps.
- Retention runs while the application is off.

## 10. Features

One check, `AIFeatureService.isFeatureEnabled`, answers whether a feature may be used: the org (application on), then the user (custom permission or usage policy). Features are running actions, debug mode and conversation export.

## 11. Integrity rules

- **One active prompt template per agent.** A unique key (`ActiveAgentKey__c`) plus a trigger check that names the template to deactivate. It holds while the application is off.
- **Unique assignments.** Junction and per-user records carry a unique key the package stamps, so the same grant cannot be made twice.
- **Names are checked on save.** An Apex class, Named Credential or permission set that does not exist is refused with an error on the field.
- **Field history** is on for the fields that change what the AI may see, say or do: on agents, prompt templates, Workflow Actions, data sources, model configurations, violation rules, policies and assignments.
- **Identifiers.** `PublicId__c` on Agent and Conversation; `DeveloperName__c` as the External Id on configuration that moves between orgs.

## 12. Known limits of this model

- Steps are the evidence of what was sent and which actions ran. They default to 7 days. Raise `StepRetentionDays__c` if your audit policy needs longer.
- With `StepCaptureMode__c` set to Off, no steps are stored for a turn, so there is no masking evidence for it. Workflow Action steps are always stored.
- The four platform events are readable by every chat user. Their payloads carry Ids and step names, no content.
