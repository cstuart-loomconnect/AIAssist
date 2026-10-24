/*
Component Name: aiAssistSettings

=================================================================
=================================================================

Description: The AI Assist Settings tab: change AI Assist Settings and AI Assist UI Settings.

Step 1: Load every row of both settings from Apex
Step 2: Show one tab for AI Assist Settings and one for AI Assist UI Settings
Step 3: Hand each tab to a panel
Step 4: Load the rows again whenever a panel saves or deletes one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The kinds of control a field can use. Each one is a value the field component understands.
const FIELD_TYPE_TOGGLE = "toggle";
const FIELD_TYPE_NUMBER = "number";
const FIELD_TYPE_TEXT = "text";
const FIELD_TYPE_URL = "url";
const FIELD_TYPE_CODES = "codes";
const FIELD_TYPE_CHOICE = "choice";

// The settings objects. Mirror AIAssistApplicationConstants.SETTINGS_NAME_ASSIST and SETTINGS_NAME_UI.
export const SETTINGS_NAME_ASSIST = "AIAssistSettings__c";
export const SETTINGS_NAME_UI = "AIAssistUISettings__c";

// The value of each tab.
export const TAB_ASSIST = "assist";
export const TAB_UI = "ui";

// The error message when nothing has gone wrong.
export const NO_ERROR = "";

// Text shown to the user.
export const LABELS = {
  title: "AI Assist Settings",
  assistTab: "AI Assist Settings",
  uiTab: "AI Assist UI Settings",
  loading: "Loading settings",
  loadFailed: "The settings could not be loaded.",
  fallbackError: "Something went wrong. Please try again."
};

// The groups of AI Assist Settings. The five fields marked overridable can also be set on a profile or user row.
export const ASSIST_GROUPS = [
  {
    key: "availability", label: "Availability", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "IsEnabled__c", label: "AI Assist enabled", type: FIELD_TYPE_TOGGLE, help: "The master switch. Every trigger and entry point respects it. Off stops all of AI Assist." }
    ]
  },
  {
    key: "limits", label: "Message limits", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "MaxMessageLength__c", label: "Maximum message length", type: FIELD_TYPE_NUMBER, unit: "characters", min: 1, max: 99999, help: "Longest message a user can send.", blankHelp: "Blank uses the system maximum. A value above it is ignored.", overridable: true },
      { key: "MaxMessagesPerUserPerMinute__c", label: "Messages per user per minute", type: FIELD_TYPE_NUMBER, unit: "messages", min: 1, max: 999, help: "Stops one user flooding the queue.", blankHelp: "Blank means no limit.", overridable: true },
      { key: "MaxMessagesInFlight__c", label: "Messages in flight", type: FIELD_TYPE_NUMBER, unit: "messages", min: 1, max: 9999, help: "Messages being answered at one time across the org. Extra messages wait as Queued.", blankHelp: "Blank means no cap." },
      { key: "ProcessingLockSeconds__c", label: "Processing lock", type: FIELD_TYPE_NUMBER, unit: "seconds", min: 30, max: 3600, required: true, help: "How long a conversation stays locked while a reply is built. After this the next message takes over a stuck lock." }
    ]
  },
  {
    key: "provider", label: "AI provider calls", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "CalloutTimeoutMilliseconds__c", label: "Callout timeout", type: FIELD_TYPE_NUMBER, unit: "milliseconds", min: 2000, max: 120000, required: true, help: "Salesforce allows at most 120,000 ms for one callout." },
      { key: "RetryAttempts__c", label: "Retry attempts", type: FIELD_TYPE_NUMBER, unit: "retries", min: 0, max: 5, required: true, help: "Extra tries after the first call fails with a retryable status." },
      { key: "RetryableStatusCodes__c", label: "Retryable status codes", type: FIELD_TYPE_CODES, help: "Some codes are never retried, whatever is listed here." },
      { key: "AIProviderSuccessStatusCodes__c", label: "Success status codes", type: FIELD_TYPE_CODES, required: true, help: "A response with any other code is treated as a failure." }
    ]
  },
  {
    key: "tools", label: "Tool calling", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "DefaultMaxToolCallingIterations__c", label: "Default iterations", type: FIELD_TYPE_NUMBER, unit: "iterations", min: 1, max: 50, required: true, help: "Used by agents that do not set their own.", overridable: true },
      { key: "MaxToolCallingIterationsCap__c", label: "Iteration cap", type: FIELD_TYPE_NUMBER, unit: "iterations", min: 1, max: 50, required: true, help: "No agent can go above this. Must be at least the default.", overridable: true },
      { key: "MaxToolCallsPerIteration__c", label: "Tool calls per iteration", type: FIELD_TYPE_NUMBER, unit: "calls", min: 1, max: 20, required: true, help: "How many tools the model may ask for in one step.", overridable: true }
    ]
  },
  {
    key: "terms", label: "Terms and policy", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "CurrentTermsVersion__c", label: "Current terms version", type: FIELD_TYPE_TEXT, maxLength: 20, help: "Raise it, for example from 1.0 to 1.1, to make everyone accept again.", blankHelp: "Blank means users are not asked to accept terms." },
      { key: "AIUsagePolicyUrl__c", label: "AI usage policy URL", type: FIELD_TYPE_URL, help: "Link shown on the terms screen." }
    ]
  },
  {
    key: "pii", label: "PII", objectName: SETTINGS_NAME_ASSIST,
    fields: [
      { key: "MaxPIIRegistryObjects__c", label: "Registries per sync run", type: FIELD_TYPE_NUMBER, unit: "registries", min: 1, max: 20, help: "A lower number spreads the PII registry sync over more runs.", blankHelp: "Blank uses the built-in maximum per run." }
    ]
  }
];

// The groups of AI Assist UI Settings, which can be set at organisation, profile and user level.
export const UI_GROUPS = [
  {
    key: "availability", label: "Availability", objectName: SETTINGS_NAME_UI,
    fields: [
      { key: "IsEnabled__c", label: "Chat window enabled", type: FIELD_TYPE_TOGGLE, help: "Shows or hides the chat window." },
      { key: "IsMaintenanceMode__c", label: "Maintenance mode", type: FIELD_TYPE_TOGGLE, help: "Chat shows a maintenance message and accepts no new messages." }
    ]
  },
  {
    key: "chat", label: "Chat window", objectName: SETTINGS_NAME_UI,
    fields: [
      { key: "IsFeedbackEnabled__c", label: "Feedback buttons", type: FIELD_TYPE_TOGGLE, help: "Thumbs up and down on each reply." },
      { key: "TypingIndicatorEnabled__c", label: "Typing indicator", type: FIELD_TYPE_TOGGLE, help: "Animated dots while a reply is being written." },
      { key: "ShouldShowExecutionTrace__c", label: "Show execution trace", type: FIELD_TYPE_TOGGLE, help: "Replaces the typing dots with a step card that lists what the agent is doing." },
      { key: "ShowTimestampOnMessages__c", label: "Show timestamp on messages", type: FIELD_TYPE_TOGGLE },
      { key: "IsWorkflowActionsEnabled__c", label: "Workflow actions", type: FIELD_TYPE_TOGGLE, help: "Lets agents suggest workflow actions in chat." },
      { key: "IsInlineWorkflowActionsEnabled__c", label: "Show actions inline", type: FIELD_TYPE_TOGGLE, help: "Run actions from buttons in the message instead of a separate card.", dependencyHint: "Needs Workflow actions on." },
      { key: "SuggestedActionsDisplay__c", label: "Suggested actions display", type: FIELD_TYPE_CHOICE, help: "How a suggested action appears in a reply.", options: [{ label: "Cards", value: "Cards" }, { label: "Inline Buttons", value: "Inline Buttons" }] },
      { key: "MaxVisibleMessageHistory__c", label: "Messages shown per page", type: FIELD_TYPE_NUMBER, unit: "messages", min: 1, max: 200, help: "Older messages load as the user scrolls up.", blankHelp: "Blank uses the built-in page size." }
    ]
  }
];
