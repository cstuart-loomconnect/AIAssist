/*
Component Name: aiPromptTemplatesTryIt

=================================================================
=================================================================

Description: The settings of the Try it tab: sides, verdicts, statuses, class names and label text.

Step 1: Name the two sides, the verdicts and the run statuses
Step 2: Name the classes of the pills and the verdict buttons
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two sides of a run. They mirror the side argument of AIPromptTemplatesController.setVerdict.
export const SIDE_SAVED = "saved";
export const SIDE_EDITED = "edited";

// The verdicts. They mirror the verdict argument of AIPromptTemplatesController.setVerdict and TestMessage.savedVerdict.
export const VERDICT_BETTER = "Better";
export const VERDICT_WORSE = "Worse";

// The last run statuses. They mirror TestMessage.lastRunStatus.
export const STATUS_PASSED = "Passed";
export const STATUS_FAILED = "Failed";

// The toast variant.
export const TOAST_VARIANT_ERROR = "error";

// The fields sent to Apex as the template. They mirror TemplateDetail.
export const PAYLOAD_FIELDS = ["templateId", "templateName", "developerName", "maxResponseLength", "systemContext", "tone", "prompt", "exclusionRules", "isActive", "isDefault", "version"];

// How numbers and times are shown, in the UK order.
export const LOCALE = "en-GB";
export const TIME_OPTIONS = { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false };

// The classes of the pills and the verdict buttons.
export const PILL_PASSED_CLASS = "aipt-pill aipt-pill_success";
export const PILL_FAILED_CLASS = "aipt-pill aipt-pill_danger";
export const PILL_NEVER_CLASS = "aipt-pill aipt-pill_neutral";
export const VERDICT_CHOSEN_VARIANT = "brand";
export const VERDICT_PLAIN_VARIANT = "neutral";
export const RESULT_CLASS = "aipt-result slds-p-around_small";
export const RESULT_ERROR_CLASS = "aipt-result aipt-result_error slds-p-around_small";

// Text shown to the user.
export const LABELS = {
  fallbackError: "Something went wrong. Please try again.",
  loading: "Running",
  message: "Message",
  messagePlaceholder: "Type a message to send to the agent",
  onRecord: "On record",
  agent: "Agent",
  agentPlaceholder: "Pick an agent",
  runBoth: "Run both",
  saveMessage: "Save this message",
  savedTitlePrefix: "Saved · v",
  savedTitleSuffix: " live",
  savedTitleInactive: "",
  editedTitle: "Edited · not saved",
  better: "Better",
  worse: "Worse",
  verdictHint: "Save this message to mark a result Better or Worse.",
  savedMessages: "Saved test messages",
  runAllPrefix: "Run all ",
  runAllSuffix: " on both",
  noMessages: "No saved messages yet. Type one above and choose Save this message. Use them as a quick check before publishing.",
  hintMessages: "The result of the last run is shown for each message. Use them as a quick check before publishing.",
  run: "Run",
  delete: "Delete",
  neverRun: "Not run",
  passed: "Passed",
  failed: "Failed",
  tokens: " tokens",
  noReply: "No reply."
};
