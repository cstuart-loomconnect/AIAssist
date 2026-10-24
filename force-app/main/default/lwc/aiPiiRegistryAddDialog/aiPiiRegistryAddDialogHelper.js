/*
Component Name: aiPiiRegistryAddDialog

=================================================================
=================================================================

Description: The extended methods of the Add object dialog: build the list of objects, the hint under the field limit, and an error message.

Step 1: Build one row for each object found, with its detail and where it is used
Step 2: Say how many fields the object has, and warn when the limit is too low
Step 3: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, OPTION_CLASS, OPTION_SELECTED_CLASS, MIN_FIELDS_LIMIT, MAX_FIELDS_LIMIT, NO_TEXT } from "./aiPiiRegistryAddDialogSettings";

// Builds the rows of the object list.
export function buildOptionViews(options, selectedName) {

  // [1] Build a row for each object
  const optionViews = options.map((option) => {

    const isSelected = option.objectApiName === selectedName;
    const optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    const detail = option.objectApiName + LABELS.detailSeparator + option.fieldCount + LABELS.fieldsWord;
    const usedByText = buildUsedByText(option.dataSourceCount);

    return { key: option.objectApiName, objectApiName: option.objectApiName, objectLabel: option.objectLabel, detail, isSelected, optionClass, usedByText, hasUsedBy: Boolean(usedByText) };
  });

  return optionViews;
}

// Writes where an object is used, such as "Used by 2 data sources". Blank when no data source reads it.
export function buildUsedByText(dataSourceCount) {

  // [1] Nothing to say when no data source reads it
  if (!dataSourceCount) return NO_TEXT;

  // [2] One is singular, any other number is plural
  if (dataSourceCount === 1) return LABELS.usedByOne;

  const usedByText = LABELS.usedByManyBefore + dataSourceCount + LABELS.usedByManyAfter;

  return usedByText;
}

// Writes the hint under the field limit: how many fields the object has, or a warning when the limit is lower than that.
export function buildFieldHint(selectedOption, maxFields) {

  // [1] Nothing to say before an object is picked
  if (!selectedOption) return { text: NO_TEXT, isWarning: false };

  // [2] Warn when the limit would cut the object short
  const fieldCount = selectedOption.fieldCount;
  const isTooLow = maxFields && maxFields < fieldCount;
  if (isTooLow) return { text: LABELS.limitTooLowBefore + maxFields + LABELS.limitTooLowMiddle + fieldCount + LABELS.limitTooLowAfter, isWarning: true };

  // [3] Otherwise say how many fields there are
  return { text: LABELS.fieldsOnObjectBefore + fieldCount + LABELS.fieldsOnObjectAfter, isWarning: false };
}

// True when the field limit is a whole number an object accepts.
export function isValidMaxFields(maxFields) {

  // [1] A whole number from the smallest to the largest limit
  const isWhole = Number.isInteger(maxFields);
  const isInRange = maxFields >= MIN_FIELDS_LIMIT && maxFields <= MAX_FIELDS_LIMIT;

  return isWhole && isInRange;
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
