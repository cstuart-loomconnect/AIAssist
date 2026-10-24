/*
Component Name: aiToolsDsDetails

=================================================================
=================================================================

Description: The settings of the Details step: field names, limits, class names and label text.

Step 1: Name the draft fields the form changes
Step 2: Set the longest values the fields take
Step 3: Hold the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The source types and binding type. Mirror AIAssistApplicationConstants.
export const SOURCE_TYPE_APEX = "Apex";
export const BINDING_BOUND = "Bound";

// The results of a test, which start each part of the last test text. Mirror AIDataSource__c.LastTestStatus__c.
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_PARTIAL = "Partial";

// The input source for a value the page fills in.
export const INPUT_SOURCE_PAGE = "page";

// The longest values. Mirror the field lengths of AIDataSource__c.
export const MAX_NAME_LENGTH = 80;
export const MAX_API_NAME_LENGTH = 75;
export const MAX_DESCRIPTION_LENGTH = 255;

// The text of a value that is empty.
export const NO_TEXT = "";
export const NO_VALUE = "—";

// The classes of the pills in the summary.
export const PILL_PASSED_CLASS = "aiadd-pill aiadd-pill_success";
export const PILL_PARTIAL_CLASS = "aiadd-pill aiadd-pill_warning";
export const PILL_FAILED_CLASS = "aiadd-pill aiadd-pill_danger";

// Text shown to the user.
export const LABELS = {
  name: "Name",
  apiName: "API name",
  apiNameHelp: "The name the agent calls it by. Letters, numbers and underscores, starting with a letter.",
  description: "Description for the agent",
  descriptionHelp: "The agent reads this to decide when to call it.",
  outputDescription: "What comes back",
  targetObject: "Object it returns (optional)",
  summary: "Summary",
  summaryType: "Type",
  summaryInputs: "Inputs",
  summaryMaxRows: "Max rows",
  summaryLastTest: "Last test",
  summaryNever: "Not tested yet",
  testFailed: "Why the last test failed:",
  boundToPages: " · bound to ",
  boundToPagesEnd: " pages",
  boundToOpenRecord: " · bound to the open record",
  active: "Active",
  activeHelp: "Saved inactive sources can be tested but agents can't use them.",
  pageInput: " (page)",
  agentInput: " (agent)"
};
