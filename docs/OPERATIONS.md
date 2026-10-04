# Operating AI Assist

For the administrator who runs AI Assist after it is set up: capacity, retention, sandboxes and uninstalling.

## 1. Capacity

### How a message uses the org

Each message is one asynchronous Apex job (a queueable), plus one more for each retry. Replies are not streamed: the chat window polls, or listens for an event if events are switched on. Continuations are not used in this version.

| Limit AI Assist leans on                | What uses it                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------------- |
| Daily asynchronous Apex executions      | One per message, one per retry, plus batches.                                   |
| Platform event allowances               | One per log entry; one per reply if events are on.                              |
| Data storage                            | About 2 KB a record; about three records a message at the default capture mode. |
| Callout time, 120 seconds a transaction | One turn, including its tool calls.                                             |

### Ceilings

| Ceiling                          | Value                                                              | Where it comes from                                         |
| -------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------- |
| Messages being worked on at once | 200, or `MaxMessagesInFlight__c` if lower                          | Fixed cap on queued and running jobs.                       |
| Messages a day                   | The org's daily asynchronous limit × the share you allow AI Assist | 250,000 a day or 200 × user licences, whichever is greater. |
| Messages a month                 | Your plan's `MaxMonthlyMessages`                                   | Licence.                                                    |

Worked example: an org with the 250,000 daily asynchronous limit and `ChatAppSharePercent__c` at 20 allows AI Assist 50,000 jobs a day. At about three messages per user per hour over an eight-hour day, that is roughly 2,000 active users before Chat pauses. Set the share from what the org's own automation needs.

When a ceiling is reached: at the in-flight cap a message waits and starts when a place is free; at 200 jobs it is refused with "AI Assist is busy, try again shortly"; at a share or the 95 percent floor Chat pauses and resumes by itself.

### Load-test numbers

**No load test has been run against this version.** The figures above are derived from platform limits, not measured. Before a large rollout, measure in a full-copy sandbox:

| Measure                                              | Result       |
| ---------------------------------------------------- | ------------ |
| Median and 95th percentile time to a reply           | Not measured |
| Sustained messages a minute before queueing          | Not measured |
| Jobs and events used per 1,000 messages              | Not measured |
| Storage used per 1,000 messages at each capture mode | Not measured |
| Behaviour at the in-flight cap and at 200 jobs       | Not measured |

`AIPlanUsageController.getPlanUsage` reports AI Assist's actual jobs, events and storage, which is the figure to watch during a test.

## 2. The maintenance job

One scheduled job, daily at 02:00 in the time zone of the user who scheduled it. Find it under Setup > Scheduled Jobs as **AI Assist Maintenance**.

| Task                                            | Runs while AI Assist is off |
| ----------------------------------------------- | --------------------------- |
| Delete expired conversations and their feedback | Yes                         |
| Delete old logs, violations, steps and messages | Yes                         |
| Recount the organisation's usage totals         | Yes                         |
| Read the org's limits and AI Assist's footprint | Yes                         |
| Report the month's counts to the licence org    | Yes                         |
| Close idle conversations                        | No                          |
| Sync the PII registry                           | No                          |

If the job is deleted, none of this happens. The health check reports it, and `AISetupChecklistController.scheduleMaintenance` puts it back.

## 3. Retention

| Record       | Setting                                     | Default  | Blank means                |
| ------------ | ------------------------------------------- | -------- | -------------------------- |
| Conversation | `ConversationRetentionDays__c` on the agent | 90 days  | Kept indefinitely          |
| Message      | `MessageRetentionDays__c`                   | 30 days  | Kept with its conversation |
| Step         | `StepRetentionDays__c`                      | 7 days   | Kept with its conversation |
| Log          | `PlatformLogRetentionDays__c`               | 30 days  | Kept indefinitely          |
| Violation    | `ViolationRetentionDays__c`                 | 365 days | Kept indefinitely          |

- **Retention runs even while AI Assist is switched off**, and in a sandbox that has not been activated. Switching the application off does not keep data past its retention.
- A conversation on **legal hold** is never deleted, and neither are its messages or steps.
- A violation still marked New is kept whatever its age.
- Changing an agent's retention days or trigger recalculates the expiry date of its existing conversations, in a batch, within a few minutes. Setting retention to blank clears the dates.
- Steps are the evidence of what was sent to the provider and which actions ran. If your audit policy needs them longer than 7 days, raise `StepRetentionDays__c` before go-live.

**Step capture** (`StepCaptureMode__c`): Summary, the default, stores one small step per provider call and data source. Full also stores the request and response JSON for every turn and uses far more storage. Off stores no steps for a turn.

## 4. Days and time zones

Daily limits and the monthly plan allowance are counted in **the org's time zone** (Company Information), not UTC and not each user's. A day's limits reset at the org's midnight; the monthly allowance resets on the 1st there.

## 5. Sandboxes

- A sandbox created or refreshed from production copies the settings, including the Id of the org they were activated in. AI Assist sees the mismatch and stays **off**: no provider is called with production's configuration.
- A fresh install in a sandbox starts off for the same reason.
- To use AI Assist in a sandbox, activate it there (`AIAssistSettingsService.activate`, or clear Activated Org Id and tick Is Enabled) and create a Named Credential in that sandbox. Use a non-production key.
- Retention keeps running in an unactivated sandbox, so copied conversations still expire.
- The chat window reports this state as "not activated in this org", and the health check lists it.

## 6. Watching it

| Question                      | Where                                                       |
| ----------------------------- | ----------------------------------------------------------- |
| Is anything misconfigured?    | `AIHealthCheckController.getFindings`                       |
| How much of the plan is used? | `AIPlanUsageController.getPlanUsage`                        |
| Why is chat paused?           | The same call: each feature's mode and the limit behind it  |
| What failed?                  | AI Platform Log, 30 days                                    |
| Who changed a credential?     | AI Platform Log, entries from `AICredentialSetupController` |

Administrators are told when a feature changes mode, at most every 15 minutes unless something pauses.

## 7. Uninstalling

Uninstalling deletes the package's objects and every record in them. Before you do:

1. **Export what you must keep**: conversations under legal hold or a retention duty, violations, usage, terms acknowledgments.
2. **Resolve legal holds.** Uninstall does not honour them.
3. **Delete the scheduled job** AI Assist Maintenance (Setup > Scheduled Jobs). A package with a scheduled job cannot be uninstalled.
4. **Remove permission set assignments** for the three AI Assist permission sets.
5. **Remove what you built on it**: your own Apex classes that implement the package's interfaces, Flows that reference its objects, and page layouts or Lightning pages that use its components.
6. Uninstall from Setup > Installed Packages.

Left behind, because they are yours and not the package's: the Named Credential and External Credential (delete them and revoke the key with the provider), and the **AI Assist Credential Access** permission set if it was created.
