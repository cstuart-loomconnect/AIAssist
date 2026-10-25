/*
Component Name: aiToolsDataSourceWizard

=================================================================
=================================================================

Description: The settings of the data source wizard: step numbers, source types, input types, starting values, class names and label text.

Step 1: Number the steps and name the source types, binding types and test results
Step 2: Describe how each kind of input is written in the input schema
Step 3: Hold the starting values of a new draft, the class names and the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The steps of the wizard, in order.
export const STEP_TYPE = 1;
export const STEP_QUERY = 2;
export const STEP_INPUTS = 3;
export const STEP_TEST = 4;
export const STEP_DETAILS = 5;
export const LAST_STEP = STEP_DETAILS;

// The source types. Mirror AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL and DATA_SOURCE_TYPE_APEX.
export const SOURCE_TYPE_SOQL = "SOQL";
export const SOURCE_TYPE_APEX = "Apex";

// The binding types. Mirror AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND and DATA_SOURCE_BINDING_UNBOUND.
export const BINDING_BOUND = "Bound";
export const BINDING_UNBOUND = "Unbound";

// The query modes of the Query step.
export const QUERY_MODE_VISUAL = "visual";
export const QUERY_MODE_WRITE = "write";

// Who fills an input in. The page value is the x-source value the Apex binder drops from what the model sends.
export const INPUT_SOURCE_PAGE = "page";
export const INPUT_SOURCE_AGENT = "agent";
export const INPUT_SOURCE_KEY = "x-source";

// The bind the open record fills. Mirrors AIAssistApplicationConstants.TOOLS_BIND_RECORD_ID.
export const BIND_RECORD_ID = "recordId";
export const INPUT_TYPE_ID = "Id";
export const INPUT_TYPE_STRING = "String";

// How each input type is written in the input schema, and read back from it.
export const INPUT_TYPE_SCHEMAS = [
  { type: "String", schemaType: "string", format: "" },
  { type: "Date", schemaType: "string", format: "date" },
  { type: "DateTime", schemaType: "string", format: "date-time" },
  { type: "Number", schemaType: "number", format: "" },
  { type: "Integer", schemaType: "integer", format: "" },
  { type: "Boolean", schemaType: "boolean", format: "" },
  { type: "Id", schemaType: "string", format: "" }
];

// The name of an input must be a plain identifier, because it is also a bind name in the query.
export const INPUT_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;

// The values a test result can have. Mirror AIDataSource__c.LastTestStatus__c.
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_PARTIAL = "Partial";
export const TEST_STATUS_FAILED = "Failed";

// The starting number of rows a data source may return.
export const DEFAULT_MAX_ROWS = 20;

// The name an earlier version kept the draft under in the browser. It is only removed now.
export const OLD_DRAFT_STORAGE_KEY = "aiToolsDataSourceDraft";

// The parts of the draft that make up the data source. A change to one of them makes an earlier test result out of date.
export const DEFINITION_KEYS = ["sourceType", "bindingType", "soqlTemplate", "apexClassName", "maxRows", "inputs"];

// The style of the confirm dialog that asks before a draft is thrown away.
export const CONFIRM_VARIANT = "default";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the step circles and names in the stepper.
export const STEP_CIRCLE_CLASS = "aiadw-circle";
export const STEP_CIRCLE_CURRENT_CLASS = "aiadw-circle aiadw-circle_current";
export const STEP_CIRCLE_DONE_CLASS = "aiadw-circle aiadw-circle_done";
export const STEP_CIRCLE_ERROR_CLASS = "aiadw-circle aiadw-circle_error";
export const STEP_NAME_CLASS = "aiadw-step-name";
export const STEP_NAME_CURRENT_CLASS = "aiadw-step-name aiadw-step-name_current";
export const STEP_STATE_DONE = "done";
export const STEP_STATE_ERROR = "error";
export const STEP_STATE_CURRENT = "current";
export const STEP_STATE_TODO = "todo";

// The classes of the pill beside the name in the header.
export const PILL_DRAFT_CLASS = "aiadw-pill aiadw-pill_draft";
export const PILL_TYPE_CLASS = "aiadw-pill aiadw-pill_type";

// Text shown to the user.
export const LABELS = {
  newDataSource: "New data source",
  draftPill: "Draft",
  draftSaved: "Draft",
  editing: "Editing a saved data source",
  stepType: "Type",
  stepQuery: "Query",
  stepApexClass: "Apex class",
  stepInputs: "Inputs",
  stepTest: "Test",
  stepDetails: "Details",
  cancel: "Cancel",
  back: "Back",
  next: "Next",
  save: "Save data source",
  saveChanges: "Save changes",
  loading: "Loading the data source",
  discardTitle: "Discard this draft?",
  discardMessage: "The draft and everything entered so far is thrown away.",
  discardEditMessage: "Changes that are not saved are thrown away.",
  saved: "Data source saved.",
  notSavedTest: "The change was not saved because its test failed. The current version keeps running. Fix it and test again.",
  lastTestYou: " as you",
  lastTestAs: " as ",
  fallbackError: "Something went wrong. Please try again."
};
