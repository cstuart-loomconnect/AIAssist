/*
Component Name: aiToolsWaStepDetails

=================================================================
=================================================================

Description: The settings of step 6 of the workflow action wizard: limits, class names and label text.

Step 1: Name the values the step reads
Step 2: Name the limits of the name and the API name
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c, ExecutionType__c and LastTestStatus__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const EXECUTION_WRITE = "Write";
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_FAILED = "Failed";

// Who fills an input.
export const SOURCE_PAGE = "page";
export const SOURCE_AGENT = "agent";
export const SOURCE_USER = "user";
export const SOURCE_FIXED = "fixed";

// The limits of the fields. Mirror AIWorkflowAction__c.ActionName__c and DeveloperName__c.
export const ACTION_NAME_MAX_LENGTH = 50;
export const API_NAME_MAX_LENGTH = 75;

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  name: "Name",
  apiName: "API name",
  description: "Description for the agent",
  descriptionHelp: "The agent reads this to decide when to suggest it.",
  outputDescription: "What comes back",
  summary: "Summary",
  summaryRuns: "Runs",
  summaryChanges: "Changes data",
  summaryInputs: "Inputs",
  summaryConfirmation: "Confirmation",
  summaryLastTest: "Last test",
  runsApex: "Apex class",
  runsFlow: "Autolaunched flow",
  runsScreenFlow: "Screen flow",
  readOnly: "Read only",
  write: "Write",
  confirms: "The user confirms first",
  noConfirmation: "No separate confirmation",
  pageInput: "(page)",
  agentInput: "(agent)",
  userInput: "(current user)",
  fixedInput: "(fixed)",
  noInputs: "none",
  tested: "Passed",
  testedFailed: "Failed",
  notTested: "Not tested since the last change",
  active: "Active",
  activeHelp: "Saved inactive actions can be tested but agents cannot use them."
};
