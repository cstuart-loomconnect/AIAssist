/*
Component Name: aiToolsWaStepTest

=================================================================
=================================================================

Description: The extended methods of step 5 of the workflow action wizard: build the test fields, read their values and write the result.

Step 1: Build one field for each input the agent fills in
Step 2: Read what the admin typed into a field
Step 3: Write the sentence that says how the test ended
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { TEST_STATUS_PASSED, DATA_TYPE_NUMBER, DATA_TYPE_BOOLEAN, DATA_TYPE_DATE, DATA_TYPE_DATE_TIME, SOURCE_PAGE, SOURCE_AGENT, FIELD_TYPE_NUMBER, FIELD_TYPE_DATE, FIELD_TYPE_DATE_TIME, FIELD_TYPE_CHECKBOX, FIELD_TYPE_TEXT, BANNER_PASSED_CLASS, BANNER_FAILED_CLASS, NO_TEXT, LABELS } from "./aiToolsWaStepTestSettings";

// True when the action has an input the open record fills.
export function hasPageInput(inputs) {

  // [1] Look for an input whose source is the page
  const isPageInputFound = inputs.some((input) => input.source === SOURCE_PAGE);

  return isPageInputFound;
}

// Gets the kind of field a test value of this data type is typed into.
export function getFieldType(dataType) {

  // [1] One answer for each data type
  if (dataType === DATA_TYPE_NUMBER) return FIELD_TYPE_NUMBER;
  if (dataType === DATA_TYPE_BOOLEAN) return FIELD_TYPE_CHECKBOX;
  if (dataType === DATA_TYPE_DATE) return FIELD_TYPE_DATE;
  if (dataType === DATA_TYPE_DATE_TIME) return FIELD_TYPE_DATE_TIME;

  return FIELD_TYPE_TEXT;
}

// Builds one field for each input the agent fills in.
export function buildFieldViews(inputs) {

  // [1] Only the agent's inputs are typed in
  const agentInputs = inputs.filter((input) => input.source === SOURCE_AGENT);

  // [2] Build one field for each
  const fieldViews = agentInputs.map((input) => {

    const fieldType = getFieldType(input.dataType);

    return { key: input.name, name: input.name, fieldType, isCheckbox: fieldType === FIELD_TYPE_CHECKBOX, isInputBox: fieldType !== FIELD_TYPE_CHECKBOX };
  });

  return fieldViews;
}

// Reads the value of a field the admin typed into, in the type the schema expects.
export function readFieldValue(event, fieldType) {

  // [1] A checkbox holds true or false
  if (fieldType === FIELD_TYPE_CHECKBOX) return event.target.checked;

  // [2] A number is sent as a number, and blank as nothing
  if (fieldType === FIELD_TYPE_NUMBER) return event.target.value === NO_TEXT ? null : Number(event.target.value);

  return event.target.value;
}

// Writes the sentence that says how the test ended, such as "Passed, then rolled back. It ran in 210 ms and changed 1 record. Everything was undone, so nothing was saved."
export function buildResultText(result) {

  // [1] A failure says why
  if (result.status !== TEST_STATUS_PASSED) return LABELS.failed + (result.message || NO_TEXT);

  // [2] Say how long it took and how many records it changed
  const recordText = result.recordsChanged === 1 ? LABELS.recordOne : LABELS.recordMany;
  const ranText = LABELS.ranIn + result.elapsedMilliseconds + LABELS.milliseconds + result.recordsChanged + recordText;

  // [3] Say whether it was undone
  const startText = result.isRolledBack ? LABELS.passedRolledBack : LABELS.passedKept;
  const endText = result.isRolledBack ? LABELS.undone : LABELS.kept;

  return startText + ranText + endText;
}

// Gets the class of the result banner.
export function getBannerClass(result) {

  // [1] Green when it passed, red when it did not
  const bannerClass = result.status === TEST_STATUS_PASSED ? BANNER_PASSED_CLASS : BANNER_FAILED_CLASS;

  return bannerClass;
}

// Turns whatever an Apex call threw into text the admin can read.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return LABELS.fallbackError;
}
