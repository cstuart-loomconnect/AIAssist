/*
Component Name: aiToolsWaWizard

=================================================================
=================================================================

Description: The settings of the workflow action wizard: steps, starting values, schema keys, class names and label text.

Step 1: Name the steps and the values a draft can hold
Step 2: Name the keys written to the input schema
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The steps, in order. The number is the step number the admin sees.
export const STEP_TYPE = 1;
export const STEP_SOURCE = 2;
export const STEP_INPUTS = 3;
export const STEP_CONFIRMATION = 4;
export const STEP_TEST = 5;
export const STEP_DETAILS = 6;
export const STEP_NAMES = [
  { number: STEP_TYPE, label: "Type" },
  { number: STEP_SOURCE, label: "Flow or class" },
  { number: STEP_INPUTS, label: "Inputs" },
  { number: STEP_CONFIRMATION, label: "Confirmation" },
  { number: STEP_TEST, label: "Test" },
  { number: STEP_DETAILS, label: "Details" }
];

// Values that mirror AIWorkflowAction__c: ActionType__c and ExecutionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_FLOW = "Flow";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const EXECUTION_READ_ONLY = "Read Only";
export const EXECUTION_WRITE = "Write";

// The data types of an input, as the Apex controller names them.
export const DATA_TYPE_TEXT = "Text";
export const DATA_TYPE_NUMBER = "Number";
export const DATA_TYPE_BOOLEAN = "Boolean";
export const DATA_TYPE_DATE = "Date";
export const DATA_TYPE_DATE_TIME = "DateTime";

// Who fills an input. The first three are written to the schema as x-source; "left" and "unsupported" are not written.
export const SOURCE_PAGE = "page";
export const SOURCE_USER = "user";
export const SOURCE_FIXED = "fixed";
export const SOURCE_AGENT = "agent";
export const SOURCE_LEFT = "left";
export const SOURCE_UNSUPPORTED = "unsupported";

// The keys written to InputSchema__c. Mirror AIAssistApplicationConstants.WORKFLOW_SCHEMA_*.
export const SCHEMA_SOURCE_KEY = "x-source";
export const SCHEMA_VALUE_KEY = "x-value";
export const SCHEMA_CONFIRM_KEY = "x-confirm";

// The JSON Schema words for each data type.
export const JSON_TYPE_STRING = "string";
export const JSON_TYPE_NUMBER = "number";
export const JSON_TYPE_INTEGER = "integer";
export const JSON_TYPE_BOOLEAN = "boolean";
export const JSON_FORMAT_DATE = "date";
export const JSON_FORMAT_DATE_TIME = "date-time";

// The draft keys that change what the action does, so a change to one makes the last test out of date.
export const TEST_INVALIDATING_KEYS = ["actionType", "executionType", "sourceName", "inputs"];

// The last test status. Mirrors AIWorkflowAction__c.LastTestStatus__c.
export const TEST_STATUS_NONE = null;

// Where the draft of a new action is kept in the browser.

// The name of the API name that is made from the action name, and its limits.
export const ACTION_NAME_MAX_LENGTH = 50;
export const API_NAME_MAX_LENGTH = 75;
export const API_NAME_FALLBACK_PREFIX = "Action";

// The draft a new action starts from.
export const NEW_DRAFT = {
  actionId: null,
  actionType: ACTION_TYPE_FLOW,
  executionType: EXECUTION_WRITE,
  sourceName: "",
  sourceLabel: "",
  flowVersion: null,
  inputs: [],
  outputs: [],
  targetObject: "",
  requiresConfirmation: true,
  confirmationMessage: "",
  actionName: "",
  developerName: "",
  isDeveloperNameEdited: false,
  description: "",
  outputDescription: "",
  isActive: true,
  lastTestStatus: TEST_STATUS_NONE,
  agentCount: 0
};

// The classes of the steps in the stepper.
export const STEP_CLASS = "aitwa-step";
export const STEP_CURRENT_CLASS = "aitwa-step aitwa-step_current";
export const STEP_DONE_CLASS = "aitwa-step aitwa-step_done";
export const STEP_ERROR_CLASS = "aitwa-step aitwa-step_error";
export const MARKER_DONE = "✓";
export const MARKER_ERROR = "!";

// The pill beside the title, and the text on the right of the header.
export const PILL_DRAFT_CLASS = "aitwa-pill aitwa-pill_draft";
export const PILL_TYPE_CLASS = "aitwa-pill aitwa-pill_type";

// The toast variants and the confirm dialog style.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";
export const CONFIRM_VARIANT = "default";

// The text of a value that is empty.
export const NO_TEXT = "";

// The name an earlier version kept the draft under in the browser. It is only removed now.
export const OLD_DRAFT_STORAGE_KEY = "aiToolsWaDraft";

// Text shown to the user.
export const LABELS = {
  newTitle: "New workflow action",
  draftPill: "Draft",
  typePillApex: "Apex",
  typePillFlow: "Flow",
  typePillScreenFlow: "Screen flow",
  draftSaved: "Draft",
  editing: "Editing · saved only when you press Save",
  cancel: "Cancel",
  back: "Back",
  next: "Next",
  save: "Save workflow action",
  saved: "Workflow action saved.",
  loading: "Loading workflow action",
  discardTitle: "Discard this workflow action?",
  discardMessage: "What you have entered will be lost.",
  saveTitle: "Save changes?",
  saveMessagePrefix: "This action is used by ",
  saveMessageOne: " active agent. ",
  saveMessageMany: " active agents. ",
  saveMessageSuffix: "The change is live as soon as it is saved.",
  fallbackError: "Something went wrong. Please try again."
};
