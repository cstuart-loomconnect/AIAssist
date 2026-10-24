/*
Component Name: aiToolsWorkflowActions

=================================================================
=================================================================

Description: The settings of the Workflow Actions panel: view and filter names, status values, class names and label text.

Step 1: Name the views, filters and status values the controller and Helper use
Step 2: Name the classes of the pills and rows
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two views of the panel.
export const VIEW_LIST = "list";
export const VIEW_WIZARD = "wizard";

// The list filters.
export const FILTER_ALL = "all";
export const FILTER_WRITE = "write";
export const FILTER_READ_ONLY = "readOnly";
export const FILTER_ATTENTION = "attention";

// Values that mirror AIWorkflowAction__c: ActionType__c, ExecutionType__c and LastTestStatus__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_FLOW = "Flow";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const EXECUTION_WRITE = "Write";
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_FAILED = "Failed";

// The toast variants.
export const TOAST_VARIANT_ERROR = "error";

// The text of a value that is empty.
export const NO_TEXT = "";

// How a test date is shown: day and month, in the UK order.
export const DATE_LOCALE = "en-GB";
export const DATE_OPTIONS = { day: "2-digit", month: "2-digit" };

// The classes of a filter button, a status pill and a row.
export const FILTER_CLASS = "aitwa-filter";
export const FILTER_SELECTED_CLASS = "aitwa-filter aitwa-filter_selected";
export const PILL_PASSED_CLASS = "aitwa-pill aitwa-pill_passed";
export const PILL_FAILED_CLASS = "aitwa-pill aitwa-pill_failed";
export const PILL_ATTENTION_CLASS = "aitwa-pill aitwa-pill_attention";
export const PILL_NEVER_CLASS = "aitwa-pill aitwa-pill_neutral";
export const PILL_ACTIVE_CLASS = "aitwa-pill aitwa-pill_passed";
export const PILL_INACTIVE_CLASS = "aitwa-pill aitwa-pill_neutral";

// Text shown to the user.
export const LABELS = {
  intro: "A workflow action is something an agent can do: run an Apex class, an autolaunched flow, or open a screen flow. Write actions always ask the user first.",
  newAction: "+ New workflow action",
  searchLabel: "Search workflow actions",
  searchPlaceholder: "Search",
  filterAll: "All",
  filterWrite: "Write",
  filterReadOnly: "Read only",
  filterAttention: "Needs attention",
  columnAction: "Workflow action",
  columnRuns: "Runs",
  columnChanges: "Changes data",
  columnTarget: "Target",
  columnAgents: "In agents",
  columnTested: "Last tested",
  columnStatus: "Status",
  runsApex: "Apex",
  runsFlow: "Autolaunched flow",
  runsScreenFlow: "Screen flow",
  writeAsksFirst: "Write · asks first",
  writeUserFinishes: "Write · user finishes it",
  readOnly: "Read only",
  never: "Never",
  passed: "Passed",
  failed: "Failed",
  active: "Active",
  inactive: "Inactive",
  noTarget: "—",
  noActions: "There are no workflow actions that match.",
  loading: "Loading workflow actions",
  fallbackError: "Something went wrong. Please try again."
};
