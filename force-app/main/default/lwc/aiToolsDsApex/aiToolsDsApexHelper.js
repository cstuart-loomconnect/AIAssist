/*
Component Name: aiToolsDsApex

=================================================================
=================================================================

Description: The extended methods of the Apex class step: build one row for each class and turn an error into text.

Step 1: Build one row for each class, with the chosen class marked
Step 2: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { NO_VALUE, API_VERSION_DIGITS, ROW_CLASS, ROW_SELECTED_CLASS, NAME_CLASS, NAME_SELECTED_CLASS, LABELS } from "./aiToolsDsApexSettings";

// Builds one row for each class.
export function buildClassViews(classOptions, selectedClassName) {

  // [1] Write each value, and mark the chosen class
  const classViews = classOptions.map((option) => {

    const isSelected = option.className === selectedClassName;
    const apiVersion = option.apiVersion === null || option.apiVersion === undefined ? NO_VALUE : Number(option.apiVersion).toFixed(API_VERSION_DIGITS);

    return { key: option.className, className: option.className, namespacePrefix: option.namespacePrefix || NO_VALUE, apiVersion, declaredInputNames: option.declaredInputNames || LABELS.noInputs, hasDeclaredInputs: Boolean(option.declaredInputNames), isSelected, rowClass: isSelected ? ROW_SELECTED_CLASS : ROW_CLASS, nameClass: isSelected ? NAME_SELECTED_CLASS : NAME_CLASS };
  });

  return classViews;
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
