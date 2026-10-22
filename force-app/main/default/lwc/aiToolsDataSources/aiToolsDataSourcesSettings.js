/*
Component Name: aiToolsDataSources

=================================================================
=================================================================

Description: The settings of the Data Sources tab: filter names, class names, status values and label text.

Step 1: Name the filters, the test results and the statuses the list shows
Step 2: Name the classes the Helper puts on the pills and filter buttons
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The filters above the list.
export const FILTER_ALL = "all";
export const FILTER_SOQL = "soql";
export const FILTER_APEX = "apex";
export const FILTER_INACTIVE = "inactive";

// The source types. Mirror AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL and DATA_SOURCE_TYPE_APEX.
export const SOURCE_TYPE_SOQL = "SOQL";
export const SOURCE_TYPE_APEX = "Apex";

// The last test results. Mirror AIDataSource__c.LastTestStatus__c.
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_PARTIAL = "Partial";
export const TEST_STATUS_FAILED = "Failed";

// The text of a value that is empty, and of a message that is empty.
export const NO_VALUE = "—";
export const NO_TEXT = "";

// The language the dates in the list are written in. The tab shows day then month.
export const DATE_LOCALE = "en-GB";
export const DATE_OPTIONS = { day: "2-digit", month: "2-digit" };

// The toast variant for an error.
export const TOAST_VARIANT_ERROR = "error";

// The classes of the filter buttons.
export const FILTER_BUTTON_CLASS = "aiads-filter";
export const FILTER_BUTTON_SELECTED_CLASS = "aiads-filter aiads-filter_selected";

// The classes of the pills in the list.
export const PILL_PASSED_CLASS = "aiads-pill aiads-pill_success";
export const PILL_PARTIAL_CLASS = "aiads-pill aiads-pill_warning";
export const PILL_FAILED_CLASS = "aiads-pill aiads-pill_danger";
export const PILL_NEVER_CLASS = "aiads-pill aiads-pill_neutral";
export const PILL_ACTIVE_CLASS = "aiads-pill aiads-pill_success";
export const PILL_INACTIVE_CLASS = "aiads-pill aiads-pill_neutral";

// Text shown to the user.
export const LABELS = {
  intro: "A data source is something an agent can read: a SOQL query or an Apex class. Queries run in user mode, so users only ever see what they could already see.",
  newDataSource: "+ New data source",
  searchPlaceholder: "Search",
  searchLabel: "Search data sources",
  filterAll: "All",
  filterSoql: "SOQL",
  filterApex: "Apex",
  filterInactive: "Inactive",
  columnName: "Data source",
  columnType: "Type",
  columnObject: "Object",
  columnBinding: "Binding",
  columnMaxRows: "Max rows",
  columnAgents: "In agents",
  columnLastTested: "Last tested",
  columnStatus: "Status",
  active: "Active",
  inactive: "Inactive",
  never: "Never",
  passed: "Passed",
  partial: "Partial",
  failed: "Failed",
  noDataSources: "No data sources match.",
  loading: "Loading data sources",
  fallbackError: "Something went wrong. Please try again."
};
