/*
Component Name: aiToolsWaStepInputs

=================================================================
=================================================================

Description: The settings of step 3 of the workflow action wizard: who can fill an input, data types, class names and label text.

Step 1: Name the values the step reads and reports
Step 2: List who can fill an input, for each kind of action
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";

// The data types of an input, as the Apex controller names them.
export const DATA_TYPE_TEXT = "Text";
export const DATA_TYPE_NUMBER = "Number";
export const DATA_TYPE_BOOLEAN = "Boolean";
export const DATA_TYPE_DATE = "Date";
export const DATA_TYPE_DATE_TIME = "DateTime";
export const DATA_TYPE_OPTIONS = [
  { label: "Text", value: DATA_TYPE_TEXT },
  { label: "Number", value: DATA_TYPE_NUMBER },
  { label: "Boolean", value: DATA_TYPE_BOOLEAN },
  { label: "Date", value: DATA_TYPE_DATE },
  { label: "Date and time", value: DATA_TYPE_DATE_TIME }
];

// Who fills an input.
export const SOURCE_PAGE = "page";
export const SOURCE_USER = "user";
export const SOURCE_FIXED = "fixed";
export const SOURCE_AGENT = "agent";
export const SOURCE_LEFT = "left";
export const SOURCE_UNSUPPORTED = "unsupported";

// The input that the open record fills.
export const PAGE_INPUT_NAME = "recordId";

// The choices in the Filled by list: for an Apex class or an autolaunched flow, and for a screen flow.
export const SOURCE_OPTIONS_SERVER = [
  { label: "The agent", value: SOURCE_AGENT },
  { label: "Current user", value: SOURCE_USER },
  { label: "Fixed value", value: SOURCE_FIXED },
  { label: "Not passed", value: SOURCE_LEFT }
];
export const SOURCE_OPTIONS_SCREEN = [
  { label: "The agent", value: SOURCE_AGENT },
  { label: "Left for the user", value: SOURCE_LEFT }
];
export const SOURCE_OPTION_PAGE = { label: "The page", value: SOURCE_PAGE };

// The choices for a fixed true or false value.
export const BOOLEAN_OPTIONS = [
  { label: "true", value: "true" },
  { label: "false", value: "false" }
];

// The kinds of field a fixed value uses.
export const FIELD_TYPE_NUMBER = "number";
export const FIELD_TYPE_DATE = "date";
export const FIELD_TYPE_DATE_TIME = "datetime-local";
export const FIELD_TYPE_TEXT = "text";

// The classes of a pill, by what fills the input.
export const PILL_PAGE_CLASS = "aitwa-pill aitwa-pill_neutral";
export const PILL_UNSUPPORTED_CLASS = "aitwa-pill aitwa-pill_danger";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  introFlow: "Read from the flow's input variables. Choose who fills each one in.",
  introApex: "Inputs the class describes are listed. Add any others the class reads from the agent.",
  introScreenFlow: "Screen flows open in a modal inside the chat. The agent can pre-fill inputs; the user completes the screens and presses Finish.",
  columnVariable: "Flow variable",
  columnInput: "Input",
  columnType: "Type",
  columnFilledBy: "Filled by",
  columnValue: "Value or description for the agent",
  addInput: "Add input",
  removeInput: "Remove input",
  namePlaceholder: "Input name",
  descriptionPlaceholder: "Tell the agent what to put here",
  fixedPlaceholder: "Enter a value",
  needsValue: "Enter a value or choose another way to fill it.",
  pageValue: "The open record's Id",
  userValue: "Always the person chatting. The agent can't assign to someone else.",
  leftFlowValue: "Not passed: the flow uses its own default.",
  leftApexValue: "Not passed to the class.",
  leftScreenValue: "Left for the user",
  notSupported: "Not supported",
  unsupportedValue: "Agents can only pass text, numbers, dates and booleans. Make the flow look these up from recordId.",
  unsupportedOne: "1 input can't be filled in by the agent. ",
  unsupportedMany: " inputs can't be filled in by the agent. ",
  unsupportedAdvice: "Fix them or the flow may fail when it runs.",
  outputsTitle: "Outputs the agent gets back",
  noOutputs: "This flow has no output variables.",
  outputsNote: "Only the variable named output is returned to the chat.",
  flowChangeNote: " · if the flow changes later, the action is flagged on the overview until it's re-tested.",
  targetObject: "Works on object (optional)",
  targetObjectHelp: "The API name of the object the open record belongs to, such as Opportunity. It is shown in the list and used to pick a record when you test.",
  previewTitle: "Preview in chat",
  previewCancel: "Cancel",
  previewFinish: "Finish",
  previewSelect: "Select an option",
  previewNote: "No separate confirmation: pressing Finish is the confirmation.",
  summaryLabel: "Summary"
};
