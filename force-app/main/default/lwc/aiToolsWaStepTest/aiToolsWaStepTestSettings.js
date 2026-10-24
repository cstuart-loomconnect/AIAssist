/*
Component Name: aiToolsWaStepTest

=================================================================
=================================================================

Description: The settings of step 5 of the workflow action wizard: values, class names and label text.

Step 1: Name the values the step reads and sends
Step 2: Name the classes of the result banner
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c, and LastTestStatus__c.
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const TEST_STATUS_PASSED = "Passed";

// The data types of an input, as the Apex controller names them.
export const DATA_TYPE_NUMBER = "Number";
export const DATA_TYPE_BOOLEAN = "Boolean";
export const DATA_TYPE_DATE = "Date";
export const DATA_TYPE_DATE_TIME = "DateTime";

// Who fills an input.
export const SOURCE_PAGE = "page";
export const SOURCE_AGENT = "agent";

// The kinds of field a test value uses.
export const FIELD_TYPE_NUMBER = "number";
export const FIELD_TYPE_DATE = "date";
export const FIELD_TYPE_DATE_TIME = "datetime-local";
export const FIELD_TYPE_CHECKBOX = "checkbox";
export const FIELD_TYPE_TEXT = "text";

// The classes of the result banner.
export const BANNER_PASSED_CLASS = "aitwa-banner aitwa-banner_passed";
export const BANNER_FAILED_CLASS = "aitwa-banner aitwa-banner_failed";

// The toast variants.
export const TOAST_VARIANT_ERROR = "error";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  record: "Record",
  recordId: "Record Id",
  recordHelp: "The open record the action runs on. Choose one to test with.",
  rollBack: "Roll back",
  rollBackHelp: "Undoes what the test changed. Only a sandbox lets you turn this off.",
  runTest: "Run test",
  running: "Running the test",
  passedRolledBack: "Passed, then rolled back. ",
  passedKept: "Passed. ",
  failed: "Failed. ",
  ranIn: "It ran in ",
  milliseconds: " ms and changed ",
  recordOne: " record. ",
  recordMany: " records. ",
  undone: "Everything was undone, so nothing was saved.",
  kept: "The changes were kept.",
  columnOutput: "Output",
  columnValue: "Value",
  noOutputs: "The action returned nothing.",
  noInputsNote: "Nothing to fill in: no input of this action is filled by the agent or the open record, so the test runs it exactly as set up. To type test values, set an input to \"The agent\" on the Inputs step.",
  rollBackNote: "Roll back undoes the records the test changed. It cannot undo callouts, emails or platform events. If a class says it does something like that, it can only be tested in a sandbox, and after any run the test lists what it could not undo.",
  screenFlowTitle: "A screen flow cannot be tested here",
  screenFlowText: "A screen flow needs a person to finish it, so there is nothing to run on the server. Save it, give it to an agent, and open it from the chat.",
  fallbackError: "Something went wrong. Please try again."
};
