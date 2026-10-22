/*
Component Name: aiToolsDsTest

=================================================================
=================================================================

Description: The extended methods of the Test step: build the input controls and the result table, write the result messages and format the values.

Step 1: Build one control for each input the agent fills in
Step 2: Format each value of the result in the way the user reads it
Step 3: Write the result message and build the table, with hidden columns marked

=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STATUS_PASSED, STATUS_PARTIAL, INPUT_SOURCE_AGENT, INPUT_TYPE_DATE, INPUT_TYPE_DATE_TIME, INPUT_TYPE_NUMBER, INPUT_TYPE_INTEGER, INPUT_TYPE_BOOLEAN, CONTROL_TEXT, CONTROL_DATE, CONTROL_DATE_TIME, CONTROL_NUMBER, CONTROL_CHECKBOX, FIELD_TYPE_CURRENCY, FIELD_TYPE_DOUBLE, FIELD_TYPE_PERCENT, FIELD_TYPE_INTEGER, FIELD_TYPE_LONG, FIELD_TYPE_DATE, FIELD_TYPE_DATE_TIME, FIELD_TYPE_BOOLEAN, DATE_LOCALE, NO_TEXT, RESULT_PASSED_CLASS, RESULT_PARTIAL_CLASS, RESULT_FAILED_CLASS, HEAD_CLASS, HEAD_REMOVED_CLASS, LABELS } from "./aiToolsDsTestSettings";

// Picks the kind of control for an input type.
export function getControlType(inputType) {

  // [1] Match the input type to a control
  if (inputType === INPUT_TYPE_DATE) return CONTROL_DATE;
  if (inputType === INPUT_TYPE_DATE_TIME) return CONTROL_DATE_TIME;
  if (inputType === INPUT_TYPE_NUMBER || inputType === INPUT_TYPE_INTEGER) return CONTROL_NUMBER;
  if (inputType === INPUT_TYPE_BOOLEAN) return CONTROL_CHECKBOX;

  return CONTROL_TEXT;
}

// Builds one control for each input the agent fills in, holding the value typed so far.
export function buildInputControls(inputs, values) {

  // [1] Only the inputs the agent fills in are tested by hand
  const agentInputs = inputs.filter((input) => input.source === INPUT_SOURCE_AGENT);

  // [2] Build a control for each, with its value
  const controls = agentInputs.map((input) => {

    const controlType = getControlType(input.type);
    const isCheckbox = controlType === CONTROL_CHECKBOX;
    const storedValue = values[input.name];

    return { name: input.name, controlType, isCheckbox, isInput: !isCheckbox, value: storedValue === undefined ? NO_TEXT : storedValue, isChecked: storedValue === true };
  });

  return controls;
}

// Writes one value of the result in the way the user reads it.
export function formatValue(value, dataType, currencyCode) {

  // [1] An empty value is blank
  if (value === null || value === undefined) return NO_TEXT;

  // [2] Money, numbers and percentages follow the user's number style
  if (dataType === FIELD_TYPE_CURRENCY) return new Intl.NumberFormat(undefined, { style: "currency", currency: currencyCode || "GBP", maximumFractionDigits: 2 }).format(value);
  if ([FIELD_TYPE_DOUBLE, FIELD_TYPE_INTEGER, FIELD_TYPE_LONG].includes(dataType)) return Number(value).toLocaleString();
  if (dataType === FIELD_TYPE_PERCENT) return Number(value).toLocaleString() + "%";

  // [3] Dates are written day, month, year
  if (dataType === FIELD_TYPE_DATE) return new Date(value + "T00:00:00").toLocaleDateString(DATE_LOCALE);
  if (dataType === FIELD_TYPE_DATE_TIME) return new Date(value).toLocaleString(DATE_LOCALE);
  if (dataType === FIELD_TYPE_BOOLEAN) return value ? "true" : "false";

  return String(value);
}

// Writes the list of removed fields, such as "Amount" or "Amount, Stage".
function joinNames(names) {

  // [1] Join the names with commas
  const joinedNames = names.join(", ");

  return joinedNames;
}

// Builds everything the template shows about a result: the box, the message, the table and the notes.
export function buildResultView(result) {

  // [1] Nothing to show before a test has run
  if (!result) return null;

  const isPassed = result.status === STATUS_PASSED;
  const isPartial = result.status === STATUS_PARTIAL;
  const rowText = result.rowCount === 1 ? LABELS.rowOne : LABELS.rowMany;
  const removedCount = result.removedFields.length;

  // [2] Write the bold lead and the rest of the message
  let boxClass = RESULT_FAILED_CLASS;
  let lead = LABELS.failedLead;
  let rest = result.message || LABELS.fallbackError;

  if (isPassed) {

    boxClass = RESULT_PASSED_CLASS;
    lead = LABELS.passed.trim();
    rest = " " + result.rowCount + rowText + result.elapsedMilliseconds + LABELS.ms + result.queriesUsed + LABELS.queriesMiddle + result.queryLimit + LABELS.queriesEnd;
  }

  if (isPartial) {

    boxClass = RESULT_PARTIAL_CLASS;
    lead = LABELS.partialLead.trim();
    const rowsText = result.rowCount === 1 ? LABELS.partialRowsOne : LABELS.partialRowsMany;
    const removedText = removedCount === 1 ? LABELS.removedOne : LABELS.removedMany;
    const accessText = removedCount === 1 ? LABELS.noReadAccess : LABELS.noReadAccessMany;
    rest = " " + result.rowCount + rowsText + joinNames(result.removedFields) + removedText + (result.runAsName || NO_TEXT) + accessText;
  }

  // [3] Build the head of each column
  const columns = result.columns.map((column) => ({ key: column.apiName, apiName: column.apiName, dataType: column.dataType, isRemoved: column.isRemoved, headClass: column.isRemoved ? HEAD_REMOVED_CLASS : HEAD_CLASS }));

  // [4] Build each row, a cell for each column
  const rows = result.rows.map((row, rowIndex) => {

    const cells = columns.map((column) => ({ key: column.key, text: column.isRemoved ? LABELS.noAccess : formatValue(row[column.apiName], column.dataType, result.currencyCode), isNoAccess: column.isRemoved }));

    return { key: "row" + rowIndex, cells };
  });

  // [5] Say what the agent receives
  const hasMasked = result.maskedFields.length > 0;
  const receivesText = hasMasked ? LABELS.receivesMasked + joinNames(result.maskedFields) : LABELS.receivesNoMask;
  const hasRows = rows.length > 0;

  return { boxClass, lead, rest, columns, rows, hasRows, isPartial, isRan: isPassed || isPartial, receivesText, warnings: result.warnings, hasWarnings: result.warnings.length > 0 };
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
