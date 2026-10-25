/*
Component Name: aiPiiRegistryTest

=================================================================
=================================================================

Description: The settings of the Test masking tab: label text and the names of the controls.

Step 1: Hold the text shown to the admin
Step 2: Name the events and the empty values the controller uses

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  testOnBefore: "Test on a ",
  recordPlaceholder: "Search records",
  runMasking: "Run masking",
  running: "Running the masking test",
  columnField: "Field",
  columnReal: "Real value (you only)",
  columnSent: "Sent to the AI provider",
  columnRule: "Rule",
  noRows: "This record has no values in the PII fields of this object, so there is nothing to mask.",
  unmasked: "The reply is unmasked before the user sees it, using the pairs saved for this conversation (AIPIIMapping__c).",
  nothingSaved: "Nothing is saved and nothing is sent to the provider in a test.",
  fallbackError: "Something went wrong. Try again."
};

// The text of a value when it is empty.
export const NO_TEXT = "";
