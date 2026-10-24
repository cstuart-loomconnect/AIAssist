/*
Component Name: aiToolsDsDetails

=================================================================
=================================================================

Description: The extended methods of the Details step: write the API name from the name and write the summary.

Step 1: Turn a name into an API name
Step 2: Write each line of the summary

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SOURCE_TYPE_APEX, BINDING_BOUND, TEST_STATUS_PASSED, TEST_STATUS_PARTIAL, INPUT_SOURCE_PAGE, NO_TEXT, NO_VALUE, PILL_PASSED_CLASS, PILL_PARTIAL_CLASS, PILL_FAILED_CLASS, MAX_API_NAME_LENGTH, LABELS } from "./aiToolsDsDetailsSettings";

// Turns a name such as "Open opportunities for account" into OpenOpportunitiesForAccount.
export function buildApiName(name) {

  // [1] Split the name on everything that is not a letter or a number
  const words = (name || NO_TEXT).split(/[^A-Za-z0-9]+/).filter((word) => word.length > 0);

  // [2] Start each word with a capital letter and join them
  const capitalisedWords = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1));
  let apiName = capitalisedWords.join(NO_TEXT);

  // [3] An API name cannot start with a number
  if (/^[0-9]/.test(apiName)) apiName = "Source" + apiName;

  return apiName.slice(0, MAX_API_NAME_LENGTH);
}

// Writes the type line, such as "SOQL · Opportunity · bound to Account pages".
export function buildTypeText(draft) {

  // [1] Start with the type and the object
  let typeText = draft.sourceType;
  const objectName = draft.sourceType === SOURCE_TYPE_APEX ? draft.targetObject : draft.targetObject || draft.builder?.objectApiName;
  if (objectName) typeText = typeText + " · " + objectName;

  // [2] Say what it is bound to
  if (draft.bindingType === BINDING_BOUND) {

    const pageObject = draft.recordObjectApiName;
    typeText = pageObject ? typeText + LABELS.boundToPages + pageObject + LABELS.boundToPagesEnd : typeText + LABELS.boundToOpenRecord;
  }

  return typeText;
}

// Writes the inputs line, such as "recordId (page), closeBefore (agent)".
export function buildInputsText(inputs) {

  // [1] Write each input with who fills it
  const parts = inputs.map((input) => {

    const who = input.source === INPUT_SOURCE_PAGE ? LABELS.pageInput : LABELS.agentInput;

    return input.name + who;
  });

  return parts.length > 0 ? parts.join(", ") : NO_VALUE;
}

// Picks the class of a test result pill from the text that starts the result.
export function buildTestPills(testHistoryParts) {

  // [1] Build one pill for each result, such as "Passed as you"
  const pills = testHistoryParts.map((part, index) => {

    const status = part.split(" ")[0];
    let pillClass = PILL_FAILED_CLASS;
    if (status === TEST_STATUS_PASSED) pillClass = PILL_PASSED_CLASS;
    if (status === TEST_STATUS_PARTIAL) pillClass = PILL_PARTIAL_CLASS;

    const pillText = status;
    const restText = part.slice(status.length);

    return { key: index, pillClass, pillText, restText };
  });

  return pills;
}
