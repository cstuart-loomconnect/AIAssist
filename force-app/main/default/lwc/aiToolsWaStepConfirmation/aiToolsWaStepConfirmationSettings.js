/*
Component Name: aiToolsWaStepConfirmation

=================================================================
=================================================================

Description: The settings of step 4 of the workflow action wizard: values, sample text, class names and label text.

Step 1: Name the values the step reads
Step 2: Hold the sample values the preview shows
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c and ExecutionType__c.
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const EXECUTION_WRITE = "Write";

// The data types of an input, as the Apex controller names them.
export const DATA_TYPE_NUMBER = "Number";
export const DATA_TYPE_BOOLEAN = "Boolean";
export const DATA_TYPE_DATE = "Date";
export const DATA_TYPE_DATE_TIME = "DateTime";

// Who fills an input.
export const SOURCE_USER = "user";
export const SOURCE_AGENT = "agent";

// The sample values the preview shows, by data type.
export const SAMPLE_TEXT = "Example text";
export const SAMPLE_NUMBER = "100";
export const SAMPLE_BOOLEAN = "Yes";
export const SAMPLE_DATE_OFFSET_DAYS = 7;
export const SAMPLE_USER = "The person chatting";

// How a sample date is shown.
export const DATE_LOCALE = "en-GB";

// The classes of an input chip: chosen, not chosen, and fixed by the server.
export const CHIP_CLASS = "aitwa-chip";
export const CHIP_SELECTED_CLASS = "aitwa-chip aitwa-chip_selected";
export const CHIP_LOCKED_CLASS = "aitwa-chip aitwa-chip_locked";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  requiresConfirmation: "Requires confirmation",
  lockedOn: "Locked on for write",
  message: "Confirmation message",
  messageHelp: "Shown above the values the agent filled in, so the user sees exactly what will be saved.",
  showInputs: "Show these inputs to the user",
  noInputs: "This action has no inputs the agent or the server fills in.",
  previewTitle: "Preview in chat",
  needsYourOk: " · needs your OK",
  previewCancel: "Cancel",
  previewConfirm: "Confirm",
  screenFlowNote: "No separate confirmation: the user pressing Finish in the window is the confirmation.",
  tick: "✓"
};
