/*
Component Name: aiToolsSkills

=================================================================
=================================================================

Description: The settings of the Skills panel: view and filter names, status values, class names and label text.

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
export const FILTER_ACTIVE = "active";
export const FILTER_BOUND = "bound";
export const FILTER_ATTENTION = "attention";

// Values that mirror AISkill__c: OutputType__c and LastTestStatus__c.
export const OUTPUT_RECORD_CHANGE = "Record Change";
export const OUTPUT_REPORT = "Report";
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_FAILED = "Failed";
export const TEST_STATUS_NOT_PICKED = "Not Picked";

// The toast variants.
export const TOAST_VARIANT_ERROR = "error";

// The text of a value that is empty.
export const NO_TEXT = "";

// How a test date is shown: day and month, in the UK order.
export const DATE_LOCALE = "en-GB";
export const DATE_OPTIONS = { day: "2-digit", month: "2-digit" };

// The classes of a filter button, a status pill and a row.
export const FILTER_CLASS = "aitsk-filter";
export const FILTER_SELECTED_CLASS = "aitsk-filter aitsk-filter_selected";
export const PILL_PASSED_CLASS = "aitsk-pill aitsk-pill_passed";
export const PILL_FAILED_CLASS = "aitsk-pill aitsk-pill_failed";
export const PILL_WARNING_CLASS = "aitsk-pill aitsk-pill_warning";
export const PILL_NEVER_CLASS = "aitsk-pill aitsk-pill_neutral";
export const PILL_ACTIVE_CLASS = "aitsk-pill aitsk-pill_passed";
export const PILL_INACTIVE_CLASS = "aitsk-pill aitsk-pill_neutral";

// Text shown to the user.
export const LABELS = {
  intro: "A skill bundles existing data sources and workflow actions with instructions for one job. The model only sees a skill's name and When To Use It until it picks it, then gets its instructions and tools.",
  newSkill: "+ New skill",
  searchLabel: "Search skills",
  searchPlaceholder: "Search",
  filterAll: "All",
  filterActive: "Active",
  filterBound: "Needs a record",
  filterAttention: "Needs attention",
  columnSkill: "Skill",
  columnTools: "Tools",
  columnOutput: "Output",
  columnRecord: "Runs on",
  columnAgents: "In agents",
  columnTested: "Last tested",
  columnStatus: "Status",
  toolsSeparator: " · ",
  dataSourcesSuffix: " data",
  actionsSuffix: " actions",
  outputChat: "Chat answer",
  outputRecordChange: "Record change",
  outputReport: "Report",
  anyRecord: "Any page",
  never: "Never",
  passed: "Passed",
  failed: "Failed",
  notPicked: "Not picked",
  active: "Active",
  inactive: "Inactive",
  noSkills: "There are no skills that match.",
  loading: "Loading skills",
  fallbackError: "Something went wrong. Please try again."
};
