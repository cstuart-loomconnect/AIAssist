# AI Assist messaging service

Status: layers 1 and 2 (Apex). Written against the object model on `feature/object-model` and the contracts in its `docs/SECURITY_MODEL.md`, section 5. Validated by a check-only deploy to a scratch org that holds that object model: 384 tests, 0 failures, every class above 75% line coverage. Nothing was deployed.

## 1. What it does

A user sends a message; the layer decides whether they may, records it, and hands the turn to an asynchronous job. The job calls the AI Agent Manager (layer 1), then records the reply or the failure and tells the chat window.

| Class                                                                                             | Role                                                                                                                                        |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `AIConversationMessageService`                                                                    | Entry point: send, retry latest, close. Runs `with sharing`, as the user.                                                                   |
| `AIMessageValidator`                                                                              | Every reason a user can be refused, in order. Refusals carry a stable `code` and a Custom Label.                                            |
| `AiMessageProcessingQueueable` / `Finalizer`                                                      | The turn, and what must always happen after it (retry, hand-off, release, report a killed job).                                             |
| `AIMessageOutcomeService`                                                                         | Reply or failure bookkeeping: messages, usage, evidence, the event to the chat window.                                                      |
| `AIConversationLockService`                                                                       | One turn per conversation at a time.                                                                                                        |
| `AIMessagingSelector`                                                                             | The only gateway to data the end user cannot read or write. `without sharing`, explicit system mode, authorises nothing.                    |
| `AIExecutionStepRecorder`                                                                         | Execution evidence: provider, model, what was sent, PII masking records. Every turn, not only debug.                                        |
| `AIConversation*TriggerHandler`, triggers                                                         | Public Id, retention expiry, close timestamp, token roll-up, last message time, sender integrity. No static run-once flags.                 |
| `AIUsageLimitService`                                                                             | The user's limits, the plan's limits, the daily budget and the shared queue ceiling. Half of the old guard.                                 |
| `AIMessagingDataService`                                                                          | Package writes in system mode, the marker that lets the message trigger tell them from a user's, and the daily usage row.                   |
| `AIAgentManager` and its providers, data sources, PII services                                    | Layer 1: the turn itself.                                                                                                                   |
| `AI*TriggerHandler` for Agent, Model Configuration, Data Source, Workflow Action, Prompt Template | Public Id, Developer Name, 64-character tool names, prompt versions. Each trigger is one line and does nothing while `IsEnabled__c` is off. |
| `AIAssistGlobalUtility`                                                                           | Stamps `PublicId__c` (Agent, Conversation only) and `DeveloperName__c` (the five configuration objects).                                    |
| `AIAssistInstallHandler`                                                                          | Post-install: creates the organisation settings rows, which are data and so are not installed.                                              |
| `AIAssistApplicationConstants`, `AIMessagingException`                                            | Layer constants, the one exception type.                                                                                                    |

## 2. How it meets the security model

- **Sharing.** One `without sharing` class (`AIMessagingSelector`) and the lock service, both with a written reason and `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE` on every statement. Everything else is `with sharing` or `inherited sharing`. The old messaging classes were all `without sharing`.
- **User data in user mode.** Conversations, messages and history are read `WITH USER_MODE`; a conversation is only ever found by its owner. Closing is a user-mode update, so only someone who can edit the conversation can close it (the old `closeConversation` closed anyone's).
- **Configuration in system mode.** Model connection, prompts, tools, user settings, assignments and terms are read by the package, as the model's section 4 requires; the User permission set cannot read them.
- **Who may use which agent.** `AIAgent__c.AccessMode__c` and `AIAgentAssignment__c`, by user or by permission set, checked on every message including retries.
- **Terms** are checked against `AITermsAcknowledgment__c` for `AIAssistSettings__c.CurrentTermsVersion__c`.
- **Related record.** The Id must be an object the user can read (`UserRecordAccess`), match the object name given, and be an object the agent is for (an active `AIAgentObject__c`; an agent with none is general).
- **Forged messages.** A user can create messages and edit `Sender__c`. A before-insert check refuses any sender but User unless the write came through the repository.
- **No leak of provider or configuration detail.** The user only ever sees a Custom Label chosen by the failure reason. The provider's own error goes to the platform log, never to a record the user can read.
- **Labels.** Every user-facing string is one of the existing `AI_Error_*` / `AI_Chat_*` labels. No new labels were needed except the gap in section 5.

## 3. Protecting the subscriber's org

- Triggers run only on the package's own objects.
- No DML before the callout (an uncommitted write blocks every later callout). The job checks the lock read-only and does not mark the message "Processing".
- Bounded work per turn: 8,000 characters per user message, 50 messages and 100,000 characters of history, 64 tools of each kind.
- The asynchronous queue is shared with the subscriber. New turns are refused, with "AI Assist is busy, try again shortly", when 200 of ours are already queued or running. Only this package's jobs are counted (`ApexClass.NamespacePrefix`).
- Retries after the first wait one minute, so a rate-limited provider is not hit again at once.
- A job that cannot enqueue its successor (asynchronous limit, or the fixed chain depth of trial and developer orgs) fails the turn, frees the lock and tells the user, instead of leaving them waiting.
- A job that waited in the queue longer than the lock lasts stands down instead of running beside whatever took the conversation over.
- When a reply is saved or a turn fails, every user message in the conversation still Queued and sent at or before the one answered is ended with it (Complete or Failed). The finalizer hands the lock to the newest waiting message only, so an older one would otherwise stay Queued.
- Regenerate replaces the answer: each reply records the message it answers (`InReplyTo__c`), and saving a new reply marks the earlier one `IsSuperseded__c`. A superseded reply is left out of the chat and of what the model is sent; it still counts in usage and is still exported and retained. A regenerate that fails leaves the earlier reply in place.
- The concurrent conversation limit counts Active conversations with activity inside their agent's idle timeout; an agent with no timeout counts all of them.
- Retention (conversations with their feedback, logs, violations), the org limit reading and the usage totals run from the maintenance job even while the application is off. Changing an agent's retention days or trigger recalculates the expiry date of its existing conversations in a batch.

## 4. What layer 2 needs from layer 1

Layer 1 is now in this branch. The surface below is what layer 2 calls; it is kept here as the contract.

`AIAssistApplicationConstants`: `SENDER_USER`, `SENDER_AI_AGENT`, `SENDER_SYSTEM`, `CONVERSATION_STATUS_ACTIVE`, `CONVERSATION_STATUS_CLOSED`, `CONVERSATION_CLOSE_REASON_USER_CLOSED`, `_MESSAGE_LIMIT_REACHED`, `_TOKEN_LIMIT_REACHED`, `_SYSTEM_OVERRIDE`, `CHANNEL_UTILITY_BAR`, `CHANNEL_MOBILE`, `USAGE_LIMIT_NOTIFY_ONLY`, `_BLOCK_NEW_MESSAGES`, `_BLOCK_NEW_CONVERSATIONS_ONLY`, `RETENTION_TRIGGER_CONVERSATION_CREATED_DATE`, `_CONVERSATION_CLOSED_DATE`, `_LAST_MESSAGE_DATE`, `EXECUTION_STEP_STATUS_SUCCESS`, `_FAILED`, `DELIMITER_MULTI_SELECT_SEPARATOR`, `PUBLIC_ID_FIELD_API_NAME`, `DEVELOPER_NAME_FIELD_API_NAME`. Values must match the model's picklists (for example `My Subordinates Conversations` and `OpenAI` changed).

`AIAssistSettingsService`: `getSettings()` (cached, field defaults when no row), `readUiSettings()` (uncached, hierarchy), `getProcessingLockMinutes()`. The kill switch is `IsEnabled__c`, not `IsApplicationActive__c`.

`AIPlatformLogManager`: `logException(Exception, String, String)`, `logExceptions(List<Database.SaveResult>, String, String)`, `logCustomMessage(String, String, String, String, Id)`.

`AIPiiMappingService`: `static Boolean isDeferringWrites`, `static void processCachedPIIMappings()`.

`AIAgentManager`:

- `executeAiMessage(AIAgent__c, AIModelConfiguration__c, AIPromptTemplate__c, AIConversation__c, List<AIConversationMessage__c>, List<AIDataSource__c>, List<AIWorkflowAction__c>, Integer attemptNumber, AIExecutionStepTracker)` returning `AgentResult`, never null.
- `AgentResult`: `isSuccessful`, `isRetryable`, `replyText`, `totalTokensUsed`, **`inputTokens`, `outputTokens`, `latencyMilliseconds`, `failureReason`** (a `FailureReason__c` value; blank means Other), `errorMessage` (log only), `suggestedWorkflowActionId` (String). The four in bold are new.
- `AIDataSourceWriteException` with `Decimal tokensUsed`.

`AIExecutionStepTracker(Id conversationId, Id userMessageId, Boolean showLiveProgress, Boolean captureFullDetail)`, with `steps`, `sentPreviewText`, `lastRequestJson`, `lastResponseJson`, `toolCallingIterationsUsed/Max`, `attemptNumber`, `captureFullDetail`, `showLiveProgress`. Each `StepEntry` now also needs `stepType`, `workflowActionId`, `status`, `provider`, `modelIdentifier`, `recordsSentCount`, `fieldsSentCount`, `objectsSent`, `fieldsSent`, `piiMaskingApplied`, `targetObject`, `targetRecordId`, `requiredConfirmation`, `confirmedBy`, `confirmedDate` and `maskingEntries` (a list of `MaskingEntry`: `sourceObject`, `sourceField`, `piiFieldType`, `complianceGroup`, `maskingStrategy`, `valuesMasked`, `outcome`). This is the evidence section 5 item 7 of the security model asks for.

The seam `AiMessageProcessingQueueable.ITurnExecutor` is how the tests replace layer 1; production uses `AIAgentManager`.

## 5. Follow-ups for the object model (not changed here)

- **Lock ownership.** The lock is an expiry time only, so a job cannot tell whether the lock it finds is still its own. A `ProcessingLockToken__c` on the conversation would let a finalizer release only a lock it holds.
- **Message order.** Same-second messages are ordered by Id. A numeric sequence on `AIConversationMessage__c` would make that exact.
- **Guard rails as settings.** The limits in `AIAssistApplicationConstants` (message length, history size, queue ceiling, retry delay) are constants; an enterprise will want them on `AIAssistSettings__c`.
- **A label for "channel not enabled".** A channel outside the user's allow-list is refused with `AI_Error_Not_Authorised` because no more specific label exists.
- **Fields not used by this layer**: `AllowConversationResume__c` and `GreetingMessage__c` belong to the chat window. `IsTestModeEnabled__c`, `NoMatchBehavior__c` and `AIFallbackMessage__c` were never read and have been deleted.

## 6. Not in this layer

The data deletion action and the retention and idle batches (they must skip `IsOnLegalHold__c`), AI-evaluated violation checks, workflow action execution, the chat controller and console (they must use `AIMessagingException.code`, not message text), Removing `AIAssistUserTrigger` and `User.AIAssistUserType__c` (security model section 5, item 3) is also outstanding.

## 7. Running the tests

The package's fields are visible to nobody until a permission set grants them, and DML that sets a field the running user cannot see fails. CI assigns every permission set to the scratch org's admin; tests that run as an end user give that user `AIAssistUser` through `AIAssistTestDataFactory.assignPermissionSet`; everything else runs as the deploying user, who holds every set in CI and in the scratch org. Test data is created only through `AIAssistTestDataFactory`.

## 8. Housekeeping, actions, violations, chat and schema (added later)

| Area             | Classes                                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Housekeeping     | `AIConversationIdleBatch`, `AIConversationRetentionBatch` (skips legal holds), `AIMaintenanceScheduler` (the one scheduled job; see section 10)                                      |
| PII registry     | `AIPiiFieldTypeClassifier`, `AIPiiRegistrySyncDispatcher`, `AIPiiRegistrySyncWorker` (SOQL on FieldDefinition, no callout)                                                           |
| Workflow actions | `AIWorkflowActionDispatcher`, `IAIWorkflowActionExecutor`: plan, user setting, assignment, confirmation, evidence on every outcome                                                   |
| Chat             | `AIChatController` and eight `AIChat*Service` classes plus `AIChatDataStructure`. Refusals reach the window as a status chosen from `AIMessagingException.code`, with a Custom Label |
| Schema           | `AISchemaHelper`: describe facts cached per transaction and, if the subscriber creates an org cache partition named `AIAssistSchema`, between transactions                           |

Not ported: `AIAssistUserTrigger`, its handler and `User.AIAssistUserType__c` (removed by the security model); the console (the wizard must catch `AIMessagingException` and read `.code`). `runSuggestedAction` keeps its two arguments, with the window's own confirmation counted as confirmed; `declineSuggestedAction` is new.

## 9. Unique keys and masking of non-text values (added later)

| Area        | Classes                                                       | What it does                                                                |
| ----------- | ------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Unique keys | `AIUserSettingsTriggerHandler` and trigger                    | Fills in `UserKey__c`, so a user has one settings row.                      |
| Masking     | `AIDataSourceResultProcessor`, `AIPiiPseudonymizationService` | A value in a field registered as personal data is masked whatever its type. |

## 10. Extension interfaces and the scheduled job (added later)

- `IAIDataSourceExecutor` and `IAIWorkflowActionExecutor` are `global`, so a class in the subscriber's org can implement them. Each takes one request class and returns one response class (`AIDataSourceRequest` and `AIDataSourceResponse`, `AIWorkflowActionRequest` and `AIWorkflowActionResponse`), also `global`. These six are the package's only global API; once a version is released their methods cannot be changed or removed, and a field can only be added.
- The post-install script schedules `AIMaintenanceScheduler` daily at 02:00 on a first install, under the name `AI Assist Maintenance`. An upgrade does not reschedule it, so an administrator who deletes or moves the job keeps their choice.

## 11. Pre-release review findings (done)

Each finding from the pre-release review, what was done, and where. The items marked permanent cannot be changed once a managed version is released, which is why they were done first.

### Permanent after release

| Item                                  | What was done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global interface signature too narrow | `IAIDataSourceExecutor.execute(AIDataSourceRequest)` returns an `AIDataSourceResponse`, and `IAIWorkflowActionExecutor.execute(AIWorkflowActionRequest)` returns an `AIWorkflowActionResponse`. All four are `global` classes. The request carries the record, the inputs, the conversation, the agent, the user, the data source or action name, the row cap and whether the user confirmed; a field can be added to any of them after release without breaking a class a subscriber has written. |
| Remaining underscores                 | Relationship names are `AIPIIFieldMetadata`, `AIPlatformLogs`, `AITermsAcknowledgments`, `AIUserSettings`. No picklist label or relationship name has an underscore. A scratch org created before this change must be recreated: it still holds the old values, and the same labels are refused as duplicates.                                                                                                                                                                                     |

### Security and access

| Severity | Finding                                         | What was done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| -------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | Flow actions run with more access than the user | `AIWorkflowActionDispatcher` passes on only the inputs the action declares as properties in `InputSchema__c`; any other key, and every key when the schema is blank or malformed, is dropped and logged by name. `AIFlowRunModeService` refuses a Flow whose run mode is "System context without sharing", or whose run mode cannot be read: on save (`AIWorkflowActionTriggerHandler`, when a Flow action is new, changes Flow, or is switched on) and again just before the Flow runs.                               |
| High     | PII mappings readable by debug mode             | `getPiiMappings` is removed from the controller and the debug service. The mapping is read only to restore real values in the user's own replies and export.                                                                                                                                                                                                                                                                                                                                                           |
| Medium   | Revoked users can still run actions             | The dispatcher makes the same access check as the message validator (`AIMessageValidator.isUserAllowedOnAgent`) and refuses an inactive agent. A user removed from an Assigned Users Only agent can no longer run what it suggested earlier.                                                                                                                                                                                                                                                                           |
| Medium   | Visibility settings do nothing                  | Enforced by `AIConversationVisibilityService`, not removed. A conversation someone else started is readable, read-only, when the agent is Global and the viewer's scope reaches the owner (My Subordinates follows the role hierarchy, All reaches everyone) and the viewer can read any record it is about. A blank or unknown setting is the narrowest one. The starter keeps every write, export and action. `getSharedConversationHistory` lists them; earlier messages, update and open use the visibility check. |
| Medium   | Permission set groups do not match              | `AIMessagingSelector.getHeldPermissionSetNames` includes each assigned group's name and the permission sets inside it. Agent assignments, usage policy assignments and the highest permission level all use it. Tested with a real permission set group.                                                                                                                                                                                                                                                               |
| Low      | Admins cannot co-edit                           | `AIUsagePolicy__c` is Read/Write.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Low      | Confirmation is a UI flag only                  | `ExecutionType__c` now defaults to Write, and `RequiresConfirmation__c` defaults to on to match the rule that a Write action needs confirmation.                                                                                                                                                                                                                                                                                                                                                                       |

## 12. Adoption

| Item                         | State                                                                                                                                                                               |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reply in the user's language | Done. The system prompt tells the model to reply in `UserInfo.getLanguage()`. Decision: the model translates the greeting and fallback message; there are no per-language versions. |
| Starter prompts per agent    | **Deferred (chat window).**                                                                                                                                                         |
| Create sample agent          | **Not yet possible**, so not built. A managed package cannot ship data records; the sample agent needs the console and install flow that do not exist yet.                          |
