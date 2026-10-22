/*
Component Name: aiToolsDsTest

=================================================================
=================================================================

Description: The settings of the Test step: result statuses, input types, number formats, class names and label text.

Step 1: Name the three results of a test and the field types that are formatted
Step 2: Set how many characters start a user search
Step 3: Hold the class names and the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The results of a test. Mirror AIDataSource__c.LastTestStatus__c.
export const STATUS_PASSED = "Passed";
export const STATUS_PARTIAL = "Partial";
export const STATUS_FAILED = "Failed";

// The binding type of a data source that needs the open record. Mirrors AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND.
export const BINDING_BOUND = "Bound";

// Who fills an input. The page value is the x-source value the Apex binder drops from what the model sends.
export const INPUT_SOURCE_AGENT = "agent";

// The input types the Test step shows a control for.
export const INPUT_TYPE_DATE = "Date";
export const INPUT_TYPE_DATE_TIME = "DateTime";
export const INPUT_TYPE_NUMBER = "Number";
export const INPUT_TYPE_INTEGER = "Integer";
export const INPUT_TYPE_BOOLEAN = "Boolean";

// The kinds of control the Test step uses.
export const CONTROL_TEXT = "text";
export const CONTROL_DATE = "date";
export const CONTROL_DATE_TIME = "datetime";
export const CONTROL_NUMBER = "number";
export const CONTROL_CHECKBOX = "checkbox";

// The field types of the result table that are written in a special way.
export const FIELD_TYPE_CURRENCY = "currency";
export const FIELD_TYPE_DOUBLE = "double";
export const FIELD_TYPE_PERCENT = "percent";
export const FIELD_TYPE_INTEGER = "integer";
export const FIELD_TYPE_LONG = "long";
export const FIELD_TYPE_DATE = "date";
export const FIELD_TYPE_DATE_TIME = "datetime";
export const FIELD_TYPE_BOOLEAN = "boolean";

// The language the dates in the result are written in. The tab shows day, month, year.
export const DATE_LOCALE = "en-GB";

// How many characters start a search for a user, and how long to wait after typing.
export const USER_SEARCH_MIN_LENGTH = 2;
export const USER_SEARCH_DELAY_MS = 300;

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the result box, the column heads and the cells.
export const RESULT_PASSED_CLASS = "aiadte-result aiadte-result_success";
export const RESULT_PARTIAL_CLASS = "aiadte-result aiadte-result_warning";
export const RESULT_FAILED_CLASS = "aiadte-result aiadte-result_danger";
export const HEAD_CLASS = "aiadte-head";
export const HEAD_REMOVED_CLASS = "aiadte-head aiadte-head_removed";

// Text shown to the user.
export const LABELS = {
  record: "Record (:recordId)",
  recordPlaceholder: "Paste a record Id",
  recordSearch: "Search records",
  runAs: "Run as",
  runAsPlaceholder: "Yourself",
  runAsHelp: "Check what a real user would get",
  useMyself: "Use myself",
  runTest: "Run test",
  running: "Running the test",
  passed: "Passed. ",
  rowOne: " row in ",
  rowMany: " rows in ",
  ms: " ms · user mode · ",
  queriesMiddle: " of ",
  queriesEnd: " SOQL queries used",
  partialLead: "Ran, but this user can't see everything. ",
  partialRowsOne: " row, but ",
  partialRowsMany: " rows, but ",
  removedOne: " was removed: ",
  removedMany: " were removed: ",
  noReadAccess: " has no read access to it (field-level security).",
  noReadAccessMany: " has no read access to them (field-level security).",
  failedLead: "Failed. ",
  noAccess: "no access",
  noRows: "The data source ran and returned no rows.",
  receivesTitle: "What the agent receives",
  receivesMasked: "Rows are masked by the PII Registry first. These fields are replaced with stand-in values: ",
  receivesNoMask: "Rows are masked by the PII Registry first. Nothing in these columns is personal data, so nothing was masked.",
  safeNote: "That's the safe behaviour: the agent can never show a user data they couldn't see themselves. If they should see it, change their permission set, not this query.",
  otherFailures: "Other failures look like this: ",
  otherFailuresText: "\"Too many rows: 1,240 matched; only 20 returned. Add a filter.\" · \"Query timed out; add an indexed filter such as AccountId.\"",
  needsRecord: "This data source needs the record the user has open, so pick one to test with.",
  fallbackError: "Something went wrong. Please try again."
};
