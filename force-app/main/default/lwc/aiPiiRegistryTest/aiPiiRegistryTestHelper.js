/*
Component Name: aiPiiRegistryTest

=================================================================
=================================================================

Description: The extended methods of the Test masking tab: build the rows of the result and write an error message.

Step 1: Build one row for each masked field, with a key the table needs
Step 2: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS } from "./aiPiiRegistryTestSettings";

// Builds the rows of the result table.
export function buildResultRows(result) {

  // [1] Nothing to show before a test has run
  if (!result) return [];

  // [2] Give each row a key
  const resultRows = result.rows.map((row, index) => ({ key: index, fieldLabel: row.fieldLabel, realValue: row.realValue, sentValue: row.sentValue, ruleText: row.ruleText }));

  return resultRows;
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
