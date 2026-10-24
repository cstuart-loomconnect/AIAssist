/*
Component Name: aiToolsWaStepDetails

=================================================================
=================================================================

Description: The extended methods of step 6 of the workflow action wizard: build the summary table.

Step 1: Write what the action runs and whether it changes data
Step 2: Write the inputs and who fills each
Step 3: Write the confirmation and the last test

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ACTION_TYPE_APEX, ACTION_TYPE_SCREEN_FLOW, EXECUTION_WRITE, TEST_STATUS_PASSED, TEST_STATUS_FAILED, SOURCE_PAGE, SOURCE_AGENT, SOURCE_USER, SOURCE_FIXED, NO_TEXT, LABELS } from "./aiToolsWaStepDetailsSettings";

// Writes what the action runs, with its name, such as "Autolaunched flow · Create_Follow_Up_Task".
export function buildRunsText(draft) {

  // [1] Choose the words for the type
  let typeText = LABELS.runsFlow;
  if (draft.actionType === ACTION_TYPE_APEX) typeText = LABELS.runsApex;
  if (draft.actionType === ACTION_TYPE_SCREEN_FLOW) typeText = LABELS.runsScreenFlow;

  return typeText + " · " + draft.sourceName;
}

// Writes the inputs and who fills each, such as "recordId (page), subject (agent)".
export function buildInputsText(inputs) {

  // [1] Name each input that is passed, with who fills it
  const suffixBySource = { [SOURCE_PAGE]: LABELS.pageInput, [SOURCE_AGENT]: LABELS.agentInput, [SOURCE_USER]: LABELS.userInput, [SOURCE_FIXED]: LABELS.fixedInput };
  const passedInputs = inputs.filter((input) => suffixBySource[input.source]);
  const inputTexts = passedInputs.map((input) => input.name + " " + suffixBySource[input.source]);

  // [2] Say so when nothing is passed
  return inputTexts.length > 0 ? inputTexts.join(", ") : LABELS.noInputs;
}

// Writes whether the action changes data.
export function buildChangesText(executionType) {

  // [1] Write or read only
  return executionType === EXECUTION_WRITE ? LABELS.write : LABELS.readOnly;
}

// Writes whether the user confirms.
export function buildConfirmationText(draft) {

  // [1] A screen flow has no separate confirmation, and any other action confirms when it writes or the admin asked
  const isScreenFlow = draft.actionType === ACTION_TYPE_SCREEN_FLOW;
  const confirms = !isScreenFlow && (draft.executionType === EXECUTION_WRITE || draft.requiresConfirmation === true);

  return confirms ? LABELS.confirms : LABELS.noConfirmation;
}

// Writes how the last test went.
export function buildLastTestText(lastTestStatus) {

  // [1] One answer for each status
  if (lastTestStatus === TEST_STATUS_PASSED) return LABELS.tested;
  if (lastTestStatus === TEST_STATUS_FAILED) return LABELS.testedFailed;

  return LABELS.notTested;
}

// Builds the rows of the summary table.
export function buildSummaryRows(draft) {

  // [1] One row for each fact
  const summaryRows = [ { key: "runs", label: LABELS.summaryRuns, value: buildRunsText(draft) }, { key: "changes", label: LABELS.summaryChanges, value: buildChangesText(draft.executionType) }, { key: "inputs", label: LABELS.summaryInputs, value: buildInputsText(draft.inputs) }, { key: "confirmation", label: LABELS.summaryConfirmation, value: buildConfirmationText(draft) }, { key: "lastTest", label: LABELS.summaryLastTest, value: buildLastTestText(draft.lastTestStatus) } ];

  return summaryRows;
}

// Makes an API name from the action name: each word starts with a capital and nothing but letters, numbers and underscores is kept.
export function buildDeveloperName(actionName) {

  // [1] Split the name into words and capitalise each
  const words = (actionName || NO_TEXT).split(/[^A-Za-z0-9]+/).filter((word) => word.length > 0);
  const joinedName = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(NO_TEXT);

  // [2] A name must start with a letter
  const safeName = /^[A-Za-z]/.test(joinedName) || joinedName.length === 0 ? joinedName : "Action" + joinedName;

  return safeName;
}
