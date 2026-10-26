/*
Component Name: aiToolsSkStepTest

=================================================================
=================================================================

Description: The settings of step 4 of the skill wizard: the test outcomes, class names and the text shown to the admin.

Step 1: Hold the values that mirror the test outcomes Apex returns
Step 2: Hold the class names of the result banner and the steps
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AISkill__c.LastTestStatus__c and the kind of tool that needs a record.
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_NOT_PICKED = "Not Picked";
export const TOOL_KIND_DATA_SOURCE = "dataSource";
export const BINDING_BOUND = "Bound";

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the result banner and of a step.
export const BANNER_PASSED_CLASS = "aitsk-banner aitsk-banner_passed";
export const BANNER_WARNING_CLASS = "aitsk-banner aitsk-banner_warning";
export const BANNER_FAILED_CLASS = "aitsk-banner aitsk-banner_failed";
export const STEP_OK_CLASS = "aitsk-step-mark aitsk-step-mark_ok";
export const STEP_FAILED_CLASS = "aitsk-step-mark aitsk-step-mark_failed";

// Text shown to the user.
export const LABELS = {
  intro: "The question is sent to the agent's model with only this skill offered. Nothing is saved but the result, and workflow actions are only suggested, never run.",
  agent: "Agent",
  agentPlaceholder: "Pick the agent whose model answers",
  agentHelp: "The agent lends its model, persona and prompt template. It does not need to have the skill.",
  record: "Record",
  recordId: "Record Id",
  recordHelp: "The record the chat is open on. A skill with a bound data source needs one.",
  question: "Question",
  questionPlaceholder: "Type what a user would ask",
  runTest: "Run test",
  running: "Asking the model",
  passed: "Passed: the model picked the skill and every step worked.",
  notPicked: "Not picked: ",
  failed: "Failed: ",
  reply: "Reply",
  suggested: "Suggested action: ",
  steps: "What happened",
  stepOk: "✓",
  stepFailed: "✗",
  meta: " ms · ",
  tokens: " tokens",
  loadingAgents: "Loading agents",
  fallbackError: "Something went wrong. Please try again."
};
