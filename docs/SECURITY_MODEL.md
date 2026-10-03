# AI Assist security and object model

Status: layer 1 (object model and access). Validated with a check-only deploy to `dev` (578 components, 0 errors). Nothing has been deployed by this review. Latest check: 724 components, 0 errors.

## 1. Principles

1. **Nothing is granted by default.** The three permission sets are generated from one access matrix; every field is listed on purpose. No permission set has any system permission (`userPermissions` is empty), no `Modify All`, and no `Delete` on conversations, violations or terms acknowledgments.
2. **Object permission gates config; ownership gates conversations.** Configuration objects are Public Read/Write so admins can co-edit without `Modify All`, but only the Admin set can read or write them (the User set reads 11 agent fields). Conversation data is Private.
3. **Separation of duties.** Admin builds; Super User supports and reviews; neither can read the other's sensitive data by accident (see section 4).
4. **Nobody sees PII mappings.** `AIPIIMapping__c` (real value to fake value) is granted to no permission set and is no longer reportable. Only the package, in system mode, reads it.
5. **Audit records are write-once.** Violations (except Review Status) and terms acknowledgments are locked by validation rules as well as field permissions.

## 2. Access matrix

CRED = create / read / edit / delete. `+all` = View All Records. Field-level access is in the permission set files (User 37 field permissions, Super User 213, Admin 226).

| Object                     | OWD                | User | Super User | Admin    |
| -------------------------- | ------------------ | ---- | ---------- | -------- |
| AIAgentAssignment__c       | ControlledByParent | -    | R          | CRED     |
| AIAgentDataSource__c       | ControlledByParent | -    | R          | CRED     |
| AIAgentObject__c           | ControlledByParent | -    | R          | CRED     |
| AIAgentViolationRule__c    | ControlledByParent | -    | R          | CRED     |
| AIAgentWorkflowAction__c   | ControlledByParent | -    | R          | CRED     |
| AIAgent__c                 | ReadWrite          | R    | R          | CRED     |
| AIConversationMessage__c   | ControlledByParent | CR   | CR +all    | CR       |
| AIConversation__c          | Private            | CRE  | CRE +all   | CRE +all |
| AIDataDeletionRequest__c   | ReadWrite          | -    | -          | CRE      |
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
| AIUsageDaily__c            | Private            | -    | R +all     | R +all   |
| AIUsagePolicyAssignment__c | ControlledByParent | -    | R          | CRED     |
| AIUsagePolicy__c           | ReadOnly           | -    | R          | CRED     |
| AIUserSettings__c          | ReadWrite          | -    | R          | CRE      |
| AIViolationRule__c         | ReadOnly           | -    | R          | CRED     |
| AIViolation__c             | ReadWrite          | -    | RE         | R        |
| AIWorkflowAction__c        | ReadWrite          | -    | R          | CRED     |
| AIAgentProgressEvent__e    | -                  | CR   | CR         | CR       |
| AIMessageReadyEvent__e     | -                  | CR   | CR         | CR       |
| AIPlatformLogEvent__e      | -                  | CR   | CR         | CR       |
| AIViolationEvent__e        | -                  | CR   | CR         | CR       |

Custom metadata: `AIChatCommand__mdt` is Protected and developer-controlled, so only the package owner ships or changes chat commands; subscribers cannot see it and no permission set references it. Admin reads the three PII metadata types. Admin alone has access to both custom settings. Object tabs are `Available`, never forced `Visible`.

## 3. Roles in one line each

- **AI Assist User**: chats. Creates and reads only their own conversations, messages, feedback and terms acknowledgment. Edits seven conversation fields (agent, channel, related record, status, close reason, closed time). Cannot edit a message after it is written.
- **AI Assist Super User**: includes User. Reads every conversation, message, step, feedback and log; reads configuration except connection details; marks violations Reviewed/Dismissed (Review Status only).
- **AI Assist Admin**: includes User. Creates/edits/deletes configuration and sets per-user limits and feature gates (debug, workflow actions, export). Sees all conversations, feedback, logs and acknowledgments, plus step timings.

Each set is self-contained (assign one). It is not additive.

## 4. Deliberate exclusions (the "cannot")

| Cannot                                                                                            | Why                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Admin read other users' message bodies, step request/response JSON, violation detail              | Content can contain customer data. Configuring an agent does not need it. Field permissions are not record-scoped, so Admin has no View All on messages. |
| Super User read `NamedCredential`, `ApiPath`, API version headers                                 | Support does not need connection details.                                                                                                                |
| Anyone delete conversations, violations, acknowledgments                                          | Retention and deletion run inside the package (retention batch, a delete action in layer 2).                                                             |
| User read prompts, SOQL templates, actions, user settings, execution steps                        | Config and trace are read by the package in system mode, not by the end user.                                                                            |
| Anyone edit Terms Acknowledged on user settings, counters, sync status, Public Id, Developer Name | System-populated.                                                                                                                                        |

## 5. What this means for layer 2 (code)

These are contracts the permission model now imposes. The existing Apex (`AI-Assist` repo) does not meet all of them:

1. **Config reads run in system mode, data reads in user mode.** `AiDataSourceDispatcher` and `AiWorkflowActionDispatcher` load `AIDataSource__c` / `AIWorkflowAction__c` `WITH USER_MODE`; the User set no longer has that access. Load the definition in system mode, check it is assigned to the agent and active, then run the actual query/Apex/Flow in user mode.
2. **49 classes are `without sharing`.** Expect the security review to question each one. Give every one a written reason or switch to `inherited sharing`/`with sharing`.
3. **Remove `User.AIAssistUserType__c` and `AIAssistUserTriggerHandler`.** A field on User that auto-assigns permission sets is a privilege-escalation path (anyone who can edit it can make themselves Admin) and a trigger on User in a managed package. Admins assign permission sets directly. The field and layout are excluded from this model.
4. **Stamp Reviewed By / Reviewed Date** in a trigger when Review Status leaves New.
5. **Publish `AIPlatformLogEvent__e` and `AIViolationEvent__e` and check if Create is still required.** Salesforce forces Read with Create on platform events, which also lets a holder subscribe. Both events can carry exception text and violation detail. Test whether Apex publishing works with no event permission; if it does, remove both from all three sets.
6. **Data deletion and versioning.** A deletion action runs in system mode only when `ApprovalDecision__c` is Approved, stamps `Status__c`, `ApprovedBy__c`, `ApprovedDate__c`, `CompletedDate__c` and the counts, skips conversations on legal hold, deletes conversations/messages/feedback, and anonymises (does not delete) violations and usage rows. A Prompt Template trigger increments `Version__c` when prompt wording changes, and the reply path stamps the template and version on each message.
7. **Record evidence and honour plan limits.** For every Provider Call step set provider, model, counts, `ObjectsSent__c`, `FieldsSent__c` and `PIIMaskingApplied__c`, and write one `AIPIIMaskingRecord__c` per field masked; for every Workflow Action step (including blocked and cancelled) set target, confirmation and outcome. Do this regardless of debug mode, with no payload. Never send a request whose masking outcome is Failed. Before creating or activating agents, data sources or actions, and before each message, read the ten feature parameters with `System.FeatureManagement` and refuse with the `AI_Error_Plan_*` labels. Cache the values per transaction.
8. **Enforce the new access model.** Check `AIAgent__c.AccessMode__c` and `AIAgentAssignment__c` before a chat starts; write `AIUsageDaily__c` (upsert on `UsageKey__c`) and `UserKey__c` / `AssignmentKey__c`; check terms through `AITermsAcknowledgment__c`; honour `IsOnLegalHold__c`, `MaxRows__c`, and the two retention settings in the clean-up jobs; stamp `ProcessingStatus__c`, `FailureReason__c`, `Severity__c`.
9. **Constants to update** because picklist values changed: `My Subordinates Conversations` (no apostrophe), `Closest Match`, violation types now `Unauthorized_Data_Access` etc. on both rule and violation, `SingleActiveConversationPerRecord__c`, `SuggestedWorkflowAction__c` (lookup), `LastTriggeredDate__c` (Date/Time), `IsEnabled__c` replaces `IsApplicationActive__c`, `OpenAI` replaces `Open AI`. PII field types are free text now (they include types the picklist never had).
10. **`Type.forName` on subscriber-entered class names** (3 places) must check `instanceof` the interface before calling it. The format rules only stop junk.
11. **Named Credential calls**: `ApiPath__c` is validated to a single-host path, but keep the call pinned to the credential on the Model Configuration and never to a user-supplied one.

## 6. Object model changes

**Fixed**

- Reporting: 13 objects were not reportable (including conversations, violations and feedback), while `AIPIIMapping__c` was. Reversed: every object except the PII mapping now supports the standard report Salesforce generates for it. No custom report types are shipped; add them later if a customer needs cross-object reports.
- `PublicId__c` was 18 characters on two objects but the generator writes 36. Both fields are now removed (below).
- Sharing: six config objects and user settings moved from Public Read Only (which forced `View All`/`Modify All` on Admin) to Public Read/Write gated by object permission. Violations also, so Super Users can review without `Modify All`.
- `AIViolationEvent__e` published after commit although described as decoupled. Now publishes immediately so audit events survive a rollback.
- Validation rules used `$Label` to compare picklist API values. Labels are translated per user, so those rules break for non-English users. Replaced with literals, and the six labels removed.
- Duplicated value sets: Channel (`Mobile` missing on conversations) and Violation Type (two spellings) now share global value sets.
- Typos and conventions: `Closet Match`, `SingleActiveConversationPer_Record__c`, `Api Path` labels, emoji in plural labels, apostrophe in a picklist API value.
- Types: `SuggestedWorkflowActionId__c` (text Id) became a lookup; `LastTriggeredDate__c` Date became Date/Time; `PIIFieldType__c` picklist became text; `ApexClassName__c`, `FlowAPIName__c`, `NamedCredential__c` and similar lengthened (a namespaced class name did not fit in 50).
- Defaults now safe: 90 day retention, message/token/iteration caps, private visibility, workflow actions off, inline actions off, block on limit.
- Integrity: restrict-delete on agent, prompt template and junction lookups; required `Source Type`, `Action Type`, `Execution Type`, `Detection Method`; 39 validation rules (Write actions must require confirmation, formats for class/flow/credential/path/signal tag, ranges, required-when-active).
- Data classification added on the 17 sensitive fields.
- 46 list views (every object that lacked one, sensible columns, and review queues), 21 compact layouts, layouts corrected (system fields read-only, every field now placed, related lists rebuilt).

**Identifier fields.** `PublicId__c` exists only where a record is referenced from outside the org or the UI: Agent and Conversation. Config that needs to move between orgs (sandbox to production) uses its unique `DeveloperName__c` as the External Id: Agent, Data Source, Workflow Action, Model Configuration and Prompt Template (restored for this reason); Violation Rule uses its unique Signal Tag. Per-user and junction records do not have an external identity, so they get a unique **key** field instead, which also stops duplicates (see the next section). Sixteen other identifier fields are removed. Nothing is auto-added elsewhere.

**Is Enabled**: `IsEnabled__c` (default true) added to both settings objects. It replaces `IsApplicationActive__c`, which was the same switch.

**UI settings versus debug**: there is no separate debug settings object. Related flags, not duplicates:

| Setting                                                                                           | Scope              | Controls                                                                                            |
| ------------------------------------------------------------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------- |
| `AIAssistUISettings__c.ShowExecutionTraceToUser__c` (relabelled Show Live Progress Steps To User) | org / profile      | Step names while waiting. No content.                                                               |
| `AIUserSettings__c.DebugModeEnabled__c`                                                           | one user           | Request/response payloads, sent preview, provider call steps.                                       |
| `AIAssistSettings__c.IsExceptionLoggingEnabled__c` then `IsPlatformLoggingEnabled__c`             | org                | Step 1 stops publishing log events; step 2 stops saving them. Both are needed, help text clarified. |
| `AIAgent__c.IsTestModeEnabled__c`, `AIAssistSettings__c.AuditLoggingRecordId__c`                  | agent / one record | Test access; scoped step logging.                                                                   |

**Decisions taken on the open items**

| Item                                                                                                                  | Decision                                                                                                                                   | Plain-English reason                                                           |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| User settings kept three "terms accepted" fields that copy what the signed Terms Acknowledgment record already proves | Removed the three copies. The chat asks "is there an acknowledgment for the current terms version" instead.                                | Two places saying the same thing can disagree, and only one is legal evidence. |
| Nothing stopped a user having two settings records, or an agent getting the same data source twice                    | Added a unique **key** field (`UserKey__c`, `AssignmentKey__c`) that the platform fills in; the database then rejects duplicates.          | A lookup cannot be made unique, so the key is the only declarative way.        |
| Each execution step stores two 128 KB JSON fields                                                                     | No new field. Steps are deleted with their conversation, so conversation retention (default 90 days) bounds storage. Keep retention short. | Nothing more is needed unless storage becomes a problem.                       |
| Settings held org-specific record Ids (email template, audit record)                                                  | Left as is.                                                                                                                                | The admin picks those per org in the console; an Id is fine there.             |
| "PII" capitalised differently on two object families                                                                  | Left. Cosmetic, and a rename breaks code for no security gain.                                                                             |                                                                                |
| Provider value `Open AI`                                                                                              | Changed to `OpenAI`.                                                                                                                       | Free now, impossible after release.                                            |
| Custom settings public or protected                                                                                   | Stay **Public**. Only chat commands are Protected.                                                                                         | Admins tune these in the console and support must be able to see them.         |
| Custom settings cannot have validation rules                                                                          | Accepted. Limits there are checked in Apex.                                                                                                | Platform limitation.                                                           |
| Progress/message-ready events are readable by every chat user                                                         | Accepted; payloads are content-free (conversation Id, step name).                                                                          | Platform events cannot be filtered per user.                                   |

## 6a. What was missing from the model, and is now added

| Gap                                                                                                    | Added                                                                                                                                                                 | Why it matters                                                                  |
| ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Who may use which agent. Any user with the User set could use any active agent.                        | `AIAgentAssignment__c` (user or permission set, active flag, unique key, history) and `AIAgent__c.AccessMode__c` (default **Assigned Users Only**).                   | The only way to limit a sensitive agent to the right people. Default is closed. |
| Usage history disappeared when conversations were purged, and daily limits meant summing every message | `AIUsageDaily__c`: one row per user, agent, model and day with tokens, counts, failures and estimated cost. Admin and Super User read it; only the package writes it. | Cost and adoption reporting that survives retention, and a cheap limit check.   |
| No price data, so no cost reporting                                                                    | Input/output price per million tokens and currency on Model Configuration; `EstimatedCost__c` formula on usage rows.                                                  | Finance asks "what does this cost" on day one.                                  |
| Data source could return unlimited rows                                                                | `MaxRows__c` (default 20, 1 to 200).                                                                                                                                  | Controls prompt size, cost and how much data reaches the AI service.            |
| No legal hold                                                                                          | `IsOnLegalHold__c` on Conversation.                                                                                                                                   | Retention must never delete held records.                                       |
| Failed replies invisible in reports                                                                    | `ProcessingStatus__c` and `FailureReason__c` on Message.                                                                                                              | Failure rate by model/agent, and recovery of stuck turns.                       |
| Feedback had a rating and free text only                                                               | `Reason__c` on Feedback.                                                                                                                                              | Actionable tuning signal.                                                       |
| Violations not linked to the offending message                                                         | `AIConversationMessage__c` on Violation.                                                                                                                              | Reviewer goes straight to the evidence.                                         |
| Logs had no severity and no retention                                                                  | `Severity__c` on log and log event; `PlatformLogRetentionDays__c` (30) and `ViolationRetentionDays__c` (365) settings.                                                | Logs are operational, violations are evidence; they need different lifetimes.   |

| No way to prove what a deletion removed | `AIDataDeletionRequest__c`: scope (user or related record), received date, four-eyes approval (the requester cannot approve their own request, enforced by a validation rule), status, and counts of what was removed. Only the package sets status, approver and counts; a completed request is locked. Admin only. | A regulator or customer can be shown the request, who approved it and what was deleted, without the record holding any deleted content. |
| Could not tell which prompt wording produced an answer | `Version__c` on Prompt Template (platform-incremented when the wording changes) and `AIPromptTemplate__c` + `PromptTemplateVersion__c` on every Message. | Answers to "why did it say that" and before/after comparisons of a prompt change. |

| Execution steps could not prove who ran a write action, or what was sent to the provider | **Kept on the existing `AIExecutionStep__c`** (one concern, one object). Added: `StepType__c`; for Workflow Action steps the target object and record, whether confirmation was required, who confirmed and when; for Provider Call steps the provider, model, record and field counts, object and field **names** sent, and whether masking ran. Status gains `Blocked` and `Cancelled`. Validation rules refuse a confirmed action recorded as successful without a confirmer, and stop stamped evidence being rewritten. | "Who changed this record through the AI" and "what did we send" are answered on the step that did it. **Trade-off:** steps are children of the message, so they are deleted with the conversation (retention, or a data deletion request). Keep agent retention as long as your audit policy needs. |
| No evidence that personal data was masked | `AIPIIMaskingRecord__c`: a write-once child of the Provider Call step, one row per object and field masked (PII type, compliance group, strategy, values masked, outcome). Names and counts only; the real and fake values stay in the PII Mapping that nobody can read. `PIIValuesMasked__c` on the step rolls the counts up, and `PIIMaskingApplied__c` separates "masking ran and found nothing" from "masking did not run". The list view **Sent Without Masking** finds the second case. Admin and Super User read it; only the package writes it. | The answer to the reviewer's question "prove masking happens before data leaves Salesforce". |
| Every customer would get the same unlimited package | Ten Feature Management parameters, set per customer from the License Management Org (table below). Security features (PII masking, violations, data deletion requests, evidence on steps) are deliberately not gated. | Needed to sell tiers and trials, and to give each customer the settings that suit them. Enforced in code. |

**Feature Management parameters** (values are placeholders until you define plans; change them per customer in the License Management Org):

| Parameter                      | Type    | Default   | Enforced by                                        |
| ------------------------------ | ------- | --------- | -------------------------------------------------- |
| `MaxActiveAgents`              | Integer | 3         | Activating an agent                                |
| `MaxActiveDataSources`         | Integer | 10        | Activating a data source                           |
| `MaxActiveWorkflowActions`     | Integer | 5         | Activating a workflow action                       |
| `MaxMonthlyMessages`           | Integer | 5000      | Each message (count from `AIUsageDaily__c`)        |
| `MaxMonthlyTokens`             | Integer | 5,000,000 | Each message (sum from `AIUsageDaily__c`)          |
| `MaxConversationRetentionDays` | Integer | 90        | Saving an agent's retention days                   |
| `WorkflowActionsAllowed`       | Boolean | false     | Activating or running any action                   |
| `ApexDataSourcesAllowed`       | Boolean | false     | Apex-type data sources and actions                 |
| `AIEvaluatedRulesAllowed`      | Boolean | false     | AI-evaluated violation rules                       |
| `MultipleProvidersAllowed`     | Boolean | false     | Activating a second provider's model configuration |

Considered and left out for now: limits on prompt templates, violation rules and model configurations, conversation export, agent assignments and usage reporting. They are easy to add later without renaming anything.

**Parked** (needs thought before any design): who is notified when a violation happens.

**Considered and not built**: per-agent record filters (build when a customer asks), full prompt versioning with restore (later; the version stamp above is the first step), and a Big Object archive for messages (decided against; export to external storage instead if storage becomes a problem).

## 6b. Phase 1 model changes (permanent at the first managed release)

Field and object API names cannot change once a managed package is released, so these were settled before it.

| Change                                                                                                                                                                                                                                                                         | Why                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `Active__c` is now `IsActive__c` on `AIViolationRule__c`, `AIPIIRegistry__c`, `AIPiiFieldType__mdt`, `AIPiiComplianceGroup__mdt` and `AIPiiDataMaskingRule__mdt`.                                                                                                              | Every other object already used `IsActive__c`.                                                                    |
| `AIViolationRule__c` is no longer Master-Detail to an agent. It has `PublicId__c`, `DeveloperName__c` and `AppliesToAllAgents__c`; OWD is Public Read Only internally and Private externally.                                                                                  | A rule such as "never disclose PII" is defined once.                                                              |
| New junction `AIAgentViolationRule__c` (agent, rule, `IsActive__c`, unique `AssignmentKey__c`).                                                                                                                                                                                | Assigns a rule to many agents. A rule with `AppliesToAllAgents__c` needs no junction row.                         |
| New child `AIAgentObject__c` (agent, `ObjectApiName__c`, `IsActive__c`, unique key). `AIAgent__c.ObjectType__c` stays as the primary object.                                                                                                                                   | One agent can serve several objects. The name is checked against the org on save and stored as the org spells it. |
| New `AIUsagePolicy__c` and `AIUsagePolicyAssignment__c` (user or permission set, same pattern as `AIAgentAssignment__c`). `AIUserSettings__c` becomes a per-user override. The three limit fields on `AIUserSettings__c` lost their defaults, so blank means "use the policy". | Limits are set once per group, not once per user.                                                                 |

How an agent is offered on an object: its own Object Type or any active `AIAgentObject__c` makes it an agent for that object; an agent with neither is general and is offered on every object; an agent added to other objects only is not general.

How a user's settings are worked out (`AIUsagePolicyResolver`, called from `AIMessagingSelector.getUserSettings`):

1. Policies apply when assigned to the user, or to a permission set the user holds. With none, the active default policies apply.
2. Limits are strictest-wins across policies (lowest number, behavior that blocks most), so adding a policy never loosens a limit.
3. Capabilities (channels, workflow actions, export, debug mode, visibility) are additive across policies.
4. The user's own `AIUserSettings__c` row overrides any value it sets. A ticked box on the row switches a capability on for that user; it cannot switch off one a policy grants.

`IAIDataSourceExecutor` and `IAIWorkflowActionExecutor` are `global` so a subscriber's Apex can implement them. Their method signatures are now permanent. The dispatchers look the class up with `Type.forName('', name)` so the subscriber's unprefixed classes resolve from managed code.

Access: all new objects are read-only for Super User and full for Admin, and none is granted to the User set. The package reads them in system mode.

## 7. History tracking

Before: `AIPromptTemplate__c` had history switched on with every field set to off (so it tracked nothing). No other object tracked anything.

Now (object limit is 20 fields, all are under):

| Object                  | Tracked                                                                                                                                                                                      | Count |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| AIAgent                 | Access Mode, Is Active, Test Mode, Persona, Model Configuration, Visibility, Retention Days, Max Tokens, Max Messages, Max Tool Iterations, No Match Behavior, Fallback Message, Object Type | 13    |
| AIDataSource            | Is Active, Source Type, SOQL Template, Apex Class, Target Object, Input Schema, Binding Type, Max Rows                                                                                       | 8     |
| AIWorkflowAction        | Is Active, Action Type, Execution Type, Apex Class, Flow API Name, Target Object, Requires Confirmation, Confirmation Message, Input Schema                                                  | 9     |
| AIModelConfiguration    | Is Active, Provider, Model Identifier, Named Credential, API Path, Temperature, Max Output Tokens, Retry Attempts, two token prices                                                          | 10    |
| AIPromptTemplate        | Is Active, Agent, Prompt, System Context, Tone, Exclusion Rules, Activation Criteria, Trigger Keywords, Max Response Length                                                                  | 9     |
| AIViolationRule         | Is Active, Applies To All Agents, Block Request, Detection Method, Detection Instruction, Violation Type, Signal Tag                                                                         | 6     |
| AIPIIRegistry           | Is Active, Object API Name, Max Fields To Query                                                                                                                                              | 3     |
| AIUserSettings          | Is Active, Debug Mode, Workflow Actions, Export, Visibility Scope, Allowed Channels, three limits, Limit Behavior                                                                            | 10    |
| AIDataDeletionRequest   | Scope, Received Date, Approval Decision, Status                                                                                                                                              | 4     |
| AIUsagePolicy           | Is Active, Is Default, three limits, Limit Behavior, Visibility Scope, Allowed Channels, Workflow Actions, Export, Debug Mode                                                                |
| AIUsagePolicyAssignment | Assignee Type, User, Permission Set Name, Is Active                                                                                                                                          |
| AIAgentAssignment       | Assignee Type, User, Permission Set Name, Is Active                                                                                                                                          | 4     |
| AIViolation             | Review Status                                                                                                                                                                                | 1     |

Rationale: these are the fields that change what the AI may see, say or do, or who may do it. Not tracked on purpose: conversations, messages, steps, masking records, logs, feedback and acknowledgments (they are the audit trail; they are write-once), and descriptions, names and setup wizard state (noise). Long text fields show only "changed", not old and new values. If you need the diff, that is Field Audit Trail or a copy of the prior value in a custom audit record.

## 8. Custom labels

139 labels in `CustomLabels.labels-meta.xml`, for user-facing text only: errors, chat copy, progress steps, terms, wizard help, and security guidance. Not for picklist values, API values, object or field names (those translate through Translation Workbench, and a label compared to an API value breaks translated users).

Convention, enforced by a label check that lives on the separate branch `feature/ci-label-check` (`npm run check:labels`, not yet in this branch or wired into CI):

- Name `AI_<Area>_<Title_Case_Words>`, Area one of Error, Chat, Step, Terms, Wizard, Guidance, Settings, Console, Common.
- Category `AI Assist,<Area>`; description 80 characters or fewer; language `en_US`; not protected (protected labels cannot be translated by subscribers).
- No API names in text. Any label referenced from code must exist.
- New user-facing string in Apex or LWC means a new label in the same change. Model-facing text (prompts, tool results) is not a label.

The validator currently reports all 139 as unused, which is expected until layer 2 uses them. Add it to CI once code references labels.

## 9. Existing scratch orgs

The phase 1 changes remove `AIViolationRule__c.Agent__c` (a Master-Detail) and the five `Active__c` fields, which cannot be deployed over an org that has them. Create a fresh scratch org, or delete those fields with a destructive change after the Apex that used them is gone.

Several changes cannot be deployed over the first layer-1 deploy in place: switching a picklist to a global value set, renaming a picklist value, changing a field's type, and removing fields. A scratch org that already has the first layer-1 deploy should be recreated from source rather than patched. CI always starts from a fresh scratch org, so it is unaffected. Nothing in this repo is needed to migrate an old org.
