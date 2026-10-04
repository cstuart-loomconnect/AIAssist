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
| `AIPlanLimitService`, `AIAssistApplicationConstants`, `AIMessagingException`                      | Plan limits from Feature Management, layer constants, the one exception type.                                                               |

## 2. How it meets the security model

- **Sharing.** One `without sharing` class (`AIMessagingSelector`) and the lock service, both with a written reason and `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE` on every statement. Everything else is `with sharing` or `inherited sharing`. The old messaging classes were all `without sharing`.
- **User data in user mode.** Conversations, messages and history are read `WITH USER_MODE`; a conversation is only ever found by its owner. Closing is a user-mode update, so only someone who can edit the conversation can close it (the old `closeConversation` closed anyone's).
- **Configuration in system mode.** Model connection, prompts, tools, user settings, assignments and terms are read by the package, as the model's section 4 requires; the User permission set cannot read them.
- **Who may use which agent.** `AIAgent__c.AccessMode__c` and `AIAgentAssignment__c`, by user or by permission set, checked on every message including retries.
- **Terms** are checked against `AITermsAcknowledgment__c` for `AIAssistSettings__c.CurrentTermsVersion__c`.
- **Related record.** The Id must be an object the user can read (`UserRecordAccess`), match the object name given, and match the agent's `ObjectType__c`.
- **Forged messages.** A user can create messages and edit `Sender__c`. A before-insert check refuses any sender but User unless the write came through the repository.
- **No leak of provider or configuration detail.** The user only ever sees a Custom Label chosen by the failure reason. The provider's own error goes to the platform log, never to a record the user can read.
- **Labels.** Every user-facing string is one of the existing `AI_Error_*` / `AI_Chat_*` labels. No new labels were needed except the gap in section 5.

## 3. Protecting the subscriber's org

- Triggers run only on the package's own objects.
- No DML before the callout (an uncommitted write blocks every later callout). The job checks the lock read-only and does not mark the message "Processing".
- Bounded work per turn: 8,000 characters per user message, 50 messages and 100,000 characters of history, 64 tools of each kind.
- The asynchronous queue is shared with the subscriber. New turns are refused when 200 of ours are already queued or running.
- Retries after the first wait one minute, so a rate-limited provider is not hit again at once.
- A job that cannot enqueue its successor (asynchronous limit, or the fixed chain depth of trial and developer orgs) fails the turn, frees the lock and tells the user, instead of leaving them waiting.
- A job that waited in the queue longer than the lock lasts stands down instead of running beside whatever took the conversation over.
- Usage limits read `AIUsageDaily__c` (a handful of rows) instead of summing conversations. The plan's monthly allowance sums one month of rows, filtered on the indexed `CreatedDate`; it is skipped when no limit is set.

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
- **Usage windows** are the UTC calendar day because limits read `AIUsageDaily__c`; the fields are still named "24 Hours".
- **Fields not used by this layer**: `IsTestModeEnabled__c`, `AllowConversationResume__c`, `NoMatchBehavior__c`, `AIFallbackMessage__c`, `GreetingMessage__c` belong to the chat window and the agent manager.

## 6. Not in this layer

The data deletion action and the retention and idle batches (they must skip `IsOnLegalHold__c`), AI-evaluated violation checks, workflow action execution, the chat controller and console (they must use `AIMessagingException.code`, not message text), Removing `AIAssistUserTrigger` and `User.AIAssistUserType__c` (security model section 5, item 3) is also outstanding.

## 7. Running the tests

The package's fields are visible to nobody until a permission set grants them, and DML that sets a field the running user cannot see fails. CI assigns every permission set to the scratch org's admin; tests that run as an end user give that user `AIAssistUser` through `AIAssistTestDataFactory.assignPermissionSet`; everything else runs as the deploying user, who holds every set in CI and in the scratch org. Test data is created only through `AIAssistTestDataFactory`.

## 8. Housekeeping, actions, violations, chat and schema (added later)

| Area             | Classes                                                                                                                                                                                               |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Housekeeping     | `AIConversationIdleBatch`, `AIConversationRetentionBatch` (skips legal holds), `AIRecordRetentionBatch` (logs, reviewed violations), `AIMaintenanceScheduler` (the one scheduled job; see section 10) |
| PII registry     | `AIPiiFieldTypeClassifier`, `AIPiiRegistrySyncDispatcher`, `AIPiiRegistrySyncWorker` (SOQL on FieldDefinition, no callout)                                                                            |
| Data deletion    | `AIDataDeletionBatch`, `AIDataDeletionRequestTriggerHandler` and trigger (approved requests only)                                                                                                     |
| Workflow actions | `AIWorkflowActionDispatcher`, `IAIWorkflowActionExecutor`: plan, user setting, assignment, confirmation, evidence on every outcome                                                                    |
| Violations       | `AIViolationService`, `AIViolationTriggerHandler`, `AIViolationRuleTriggerHandler` and triggers                                                                                                       |
| Usage            | `AITokenUsageService` on `AIUsageDaily__c`                                                                                                                                                            |
| Chat             | `AIChatController` and eight `AIChat*Service` classes plus `AIChatDataStructure`. Refusals reach the window as a status chosen from `AIMessagingException.code`, with a Custom Label                  |
| Schema           | `AISchemaHelper`: describe facts cached per transaction and, if the subscriber creates an org cache partition named `AIAssistSchema`, between transactions                                            |

Not ported: `AIAssistUserTrigger`, its handler and `User.AIAssistUserType__c` (removed by the security model); the console (the wizard must catch `AIMessagingException` and read `.code`). `runSuggestedAction` keeps its two arguments, with the window's own confirmation counted as confirmed; `declineSuggestedAction` is new.

## 9. Plan limits at activation, unique keys and masking of non-text values (added later)

| Area            | Classes                                                                                                                                                  | What it does                                                                                                                                                                                                                                                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan activation | `AIPlanActivationService`, called before insert and before update by the Agent, Data Source, Workflow Action and Model Configuration trigger handlers    | Enforces the five parameters that were defined but not read: `MaxActiveAgents`, `MaxActiveDataSources`, `MaxActiveWorkflowActions`, `MaxConversationRetentionDays`, `MultipleProvidersAllowed`. Also refuses activating an action when `WorkflowActionsAllowed` is off, or an Apex source or action when `ApexDataSourcesAllowed` is off. |
| Unique keys     | `AIAgentAssignmentTriggerHandler`, `AIAgentDataSourceTriggerHandler`, `AIAgentWorkflowActionTriggerHandler`, `AIUserSettingsTriggerHandler` and triggers | Fill in `AssignmentKey__c` and `UserKey__c`, which nothing populated, so the unique setting on those fields now rejects a duplicate assignment, link or settings record.                                                                                                                                                                  |
| Masking         | `AIDataSourceResultProcessor`, `AIPiiPseudonymizationService`                                                                                            | A value in a field registered as personal data is masked whatever its type (a date or number used to be passed on as it was). A missing masking rule is logged once per field type per transaction, not once per value.                                                                                                                   |

Rules of the plan check:

- Only what is being switched on is refused. A record that was already active can still be edited after a plan is reduced.
- Blank retention means keep indefinitely, so it is refused when the plan has a retention cap.
- It is not behind `IsEnabled__c`, and neither are the key triggers: switching the application off must not be a way round either.
- A scratch or developer org answers Feature Management with the package defaults (three agents, no Apex), so in a test the activation checks apply only when the test sets `AIPlanLimitService.isActivationCheckedInTest`.

## 10. Extension interfaces and the scheduled job (added later)

- `IAIDataSourceExecutor` and `IAIWorkflowActionExecutor` are `global`, so a class in the subscriber's org can implement them. Each takes one request class and returns one response class (`AIDataSourceRequest` and `AIDataSourceResponse`, `AIWorkflowActionRequest` and `AIWorkflowActionResponse`), also `global`. These six are the package's only global API; once a version is released their methods cannot be changed or removed, and a field can only be added.
- The post-install script schedules `AIMaintenanceScheduler` daily at 02:00 on a first install, under the name `AI Assist Maintenance`. An upgrade does not reschedule it, so an administrator who deletes or moves the job keeps their choice.

## 11. Pre-release review findings (done)

Each finding from the pre-release review, what was done, and where. The items marked permanent cannot be changed once a managed version is released, which is why they were done first.

### Permanent after release

| Item                                  | What was done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Global interface signature too narrow | `IAIDataSourceExecutor.execute(AIDataSourceRequest)` returns an `AIDataSourceResponse`, and `IAIWorkflowActionExecutor.execute(AIWorkflowActionRequest)` returns an `AIWorkflowActionResponse`. All four are `global` classes. The request carries the record, the inputs, the conversation, the agent, the user, the data source or action name, the row cap and whether the user confirmed; a field can be added to any of them after release without breaking a class a subscriber has written.                                                |
| Remaining underscores                 | Picklist values are now `DeterministicApex`, `AIEvaluated` and `UnauthorizedDataAccess`, `UnauthorizedWorkflowAction`, `UsageLimitExceeded`, `PIIMaskingFailure`, `ConfigurationViolation`, `AIFlaggedIntent` (`AIViolationType`). Relationship names are `AIPIIFieldMetadata`, `AIPlatformLogs`, `AITermsAcknowledgments`, `AIUserSettings`. No picklist label or relationship name has an underscore. A scratch org created before this change must be recreated: it still holds the old values, and the same labels are refused as duplicates. |

### Security and access

| Severity | Finding                                         | What was done                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| -------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | Flow actions run with more access than the user | `AIWorkflowActionDispatcher` passes on only the inputs the action declares as properties in `InputSchema__c`; any other key, and every key when the schema is blank or malformed, is dropped and logged by name. `AIFlowRunModeService` refuses a Flow whose run mode is "System context without sharing", or whose run mode cannot be read: on save (`AIWorkflowActionTriggerHandler`, when a Flow action is new, changes Flow, or is switched on) and again just before the Flow runs.                               |
| High     | PII mappings readable by debug mode             | `getPiiMappings` is removed from the controller and the debug service. The mapping is read only to restore real values in the user's own replies and export.                                                                                                                                                                                                                                                                                                                                                           |
| Medium   | Revoked users can still run actions             | The dispatcher makes the same access check as the message validator (`AIMessageValidator.isUserAllowedOnAgent`) and refuses an inactive agent. A user removed from an Assigned Users Only agent can no longer run what it suggested earlier.                                                                                                                                                                                                                                                                           |
| Medium   | Visibility settings do nothing                  | Enforced by `AIConversationVisibilityService`, not removed. A conversation someone else started is readable, read-only, when the agent is Global and the viewer's scope reaches the owner (My Subordinates follows the role hierarchy, All reaches everyone) and the viewer can read any record it is about. A blank or unknown setting is the narrowest one. The starter keeps every write, export and action. `getSharedConversationHistory` lists them; earlier messages, update and open use the visibility check. |
| Medium   | Permission set groups do not match              | `AIMessagingSelector.getHeldPermissionSetNames` includes each assigned group's name and the permission sets inside it. Agent assignments, usage policy assignments and the highest permission level all use it. Tested with a real permission set group.                                                                                                                                                                                                                                                               |
| Medium   | AI rules silently dropped                       | Rules are taken blocking first, then by name; a cut-short list is logged once per agent and says when a blocking rule was dropped. `AIViolationRuleCapService` logs a warning when a rule or assignment is saved that puts an agent over the limit (a trigger can only refuse a save, which would stop a rule that is harmless for most agents).                                                                                                                                                                       |
| Low      | Integrity triggers fail open                    | The seven handlers that stamp a unique key or check an object name now refuse the save (`AI_Error_Integrity_Check`) when the check itself fails, through `AIAssistGlobalUtility.refuseSave`.                                                                                                                                                                                                                                                                                                                           |
| Low      | Admins cannot co-edit                           | `AIUsagePolicy__c` and `AIViolationRule__c` are Read/Write.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Low      | Confirmation is a UI flag only                  | `ExecutionType__c` now defaults to Write, and `RequiresConfirmation__c` defaults to on to match the rule that a Write action needs confirmation.                                                                                                                                                                                                                                                                                                                                                                       |

## 12. Org limit protection (done)

Section 3 protects the subscriber's org with fixed ceilings. `AIOrgLimitMonitor` adds protection that follows the org's actual limit consumption.

- **Modes.** Each of three features (Chat, Events, Logging) is Normal, Degraded or Paused. Chat reads asynchronous Apex, API requests and data storage; Events reads the platform event allowances; Logging reads the event allowances and data storage, because every log entry is an event.
- **Thresholds** are in `AIAssistSettings__c`: Degraded at 70 and Paused at 85 percent, a resume margin of 5 points so a mode does not flip back at the line, a maximum share that replaces the Paused threshold when lower (the rest of every limit is the subscriber's buffer), and the minutes between readings (5). A blank, out of range or contradictory value falls back to a safe one.
- **Cheap.** `OrgLimits.getMap()` is read at most once every few minutes. The reading is kept in `AIAssistSettings__c.OrgLimitStateJson__c`, which the platform caches. A call that only asks for a mode never writes. The reading is refreshed where DML is already safe: in the message finalizer, after the callout, and in the maintenance job. A failure to read never stops chat; the last known state is used, or Normal.
- **Paused.** `AIMessageValidator` refuses a new message with code `ORG_LIMITS_PAUSED` and the label "AI Assist is paused to protect your org's daily limits and will resume automatically." Nothing fails silently, and it resumes without anyone doing anything.
- **Events are optional.** `AIAssistSettings__c.IsEventNotificationEnabled__c` is off by default, so the chat window polls and uses no event allowance. When it is on, events stop (and the window falls back to polling) as soon as the Events feature leaves Normal. `getNotificationMode` answers Events or Polling. The reply-ready and progress events are published only when events are allowed.
- **Administrators are told.** When a mode changes, users with the Admin permission set (directly or through a group) get one custom notification (`AIAssistLimitAlert`), or an email if the notification type is missing, and a Platform Log entry is written. A further change within 15 minutes is logged but not announced again, unless something pauses. The current reading is in `OrgLimitStateJson__c` for a health check page.
- **Logging backs off.** While Logging is not Normal only errors are published (`AIPlatformLogManager.logCustomMessage` takes a severity). Going to Paused is logged as an error so it always gets through.
- **Deferred to the chat window:** the polling schedule (1, 2 then 5 seconds, only while a reply is pending and the tab is visible) and the window's use of the notification mode.

## 13. Adoption and plan visibility

| Item                              | State                                                                                                                                                                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan usage the subscriber can see | Each cap has its own message. The monthly message and token caps now say how much the plan allows and when it renews. **Deferred (chat window):** the "X of Y used this month" display and the controller call that feeds it. |
| Reply in the user's language      | Done. The system prompt tells the model to reply in `UserInfo.getLanguage()`. Decision: the model translates the greeting and fallback message; there are no per-language versions.                                           |
| Starter prompts per agent         | **Deferred (chat window).**                                                                                                                                                                                                   |
| Create sample agent               | **Not yet possible**, so not built. A managed package cannot ship data records; the sample agent needs the console and install flow that do not exist yet.                                                                    |
