/*
Component Name: aiChatSuggestedAction

=================================================================
=================================================================

Description: Helper functions for aiChatSuggestedAction. No component state.

Step 1: getStatus works out the status to show for the action
Step 2: hasInputFields says whether the action has fields to edit
Step 3: buildFieldViews turns the input fields into what the template needs
Step 4: isEveryInputValid checks all the edit inputs and shows any errors

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ACTION_STATUS, INPUT_TYPE } from "./aiChatSuggestedActionSettings";

// Gets the status to show. A reply whose action already ran reads as done until this session has a state of its own for it.
export function getStatus(action, state) {

  // [1] An action that already ran is done when there is no state yet, or the state is still idle
  const hasRun = Boolean(action && action.hasRun);
  const isStateIdle = !state || state.status === ACTION_STATUS.IDLE;

  if (hasRun && isStateIdle) {
    return ACTION_STATUS.DONE;
  }

  // [2] Otherwise use the state's status, or idle when there is none
  const stateStatus = state && state.status;

  return stateStatus || ACTION_STATUS.IDLE;
}

// Says whether the action has at least one input field the user can edit.
export function hasInputFields(action) {

  // [1] Read the input fields, which may be missing
  const inputFields = action && action.inputFields;

  // [2] There are fields when the list exists and is not empty
  return Boolean(inputFields && inputFields.length > 0);
}

// Builds one view per input field with its current value and its type flags.
export function buildFieldViews(inputFields, values) {

  // [1] The action may have no input fields
  const fieldList = inputFields || [];
  const fieldViews = [];

  // [2] Build one view per field
  fieldList.forEach((field) => {
    const value = values[field.name];
    const isTextarea = field.inputType === INPUT_TYPE.TEXTAREA;
    const isCheckbox = field.inputType === INPUT_TYPE.CHECKBOX;
    fieldViews.push({ ...field, value, isTextarea, isCheckbox });
  });

  return fieldViews;
}

// Checks every input and shows its error message. Every input is checked, even after one fails.
export function isEveryInputValid(inputs) {

  // [1] Start by assuming all inputs are valid
  let isValid = true;

  // [2] Check each input and remember if any failed
  inputs.forEach((input) => {
    const isInputValid = input.reportValidity();
    isValid = isInputValid && isValid;
  });

  return isValid;
}
