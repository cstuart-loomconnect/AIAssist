/*
Component Name: aiAgentWizardPicker

=================================================================
=================================================================

Description: The settings of the picker of the AI Agent Wizard: the lists it can show, the filters, class names and label text.

Step 1: Name the lists and the three filters
Step 2: Hold the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two lists the picker can show. The step passes one of these as the kind.
export const KIND_DATA_SOURCE = "dataSource";
export const KIND_ACTION = "action";

// The three filters above the list.
export const FILTER_FITS = "fits";
export const FILTER_ALL = "all";
export const FILTER_NOT_ADDED = "notAdded";
export const FILTERS = [
  { value: FILTER_FITS, label: "Fits this agent" },
  { value: FILTER_ALL, label: "All" },
  { value: FILTER_NOT_ADDED, label: "Not yet added" }
];

// Values that mirror AIDataSource__c.BindingType__c.
export const BINDING_BOUND = "Bound";

// Values that mirror AIWorkflowAction__c.ActionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";

// The classes of a row, of a filter button and of the tags.
export const OPTION_CLASS = "aiawpi-option";
export const OPTION_SELECTED_CLASS = "aiawpi-option aiawpi-option_selected";
export const OPTION_DISABLED_CLASS = "aiawpi-option aiawpi-option_disabled";
export const FILTER_BUTTON_CLASS = "aiawpi-seg-button";
export const FILTER_BUTTON_SELECTED_CLASS = "aiawpi-seg-button aiawpi-seg-button_selected";
export const TAG_CLASS = "aiawpi-pill";
export const TAG_SUCCESS_CLASS = "aiawpi-pill aiawpi-pill_success";
export const TAG_WARNING_CLASS = "aiawpi-pill aiawpi-pill_warning";

// The text between the parts of a line of detail.
export const DETAIL_SEPARATOR = " · ";
export const LIST_SEPARATOR = ", ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  titleDataSources: "Add data sources",
  titleActions: "Add workflow actions",
  showingDataSources: "Showing sources for ",
  showingActions: "Showing actions for ",
  andUnbound: " and unbound",
  searchDataSources: "Search data sources",
  searchActions: "Search workflow actions",
  active: "Active",
  inactive: "Inactive",
  alreadyAdded: "Already added",
  onlySuffix: " only",
  bound: "bound",
  unbound: "unbound",
  noMatches: "Nothing matches.",
  selectedSuffix: " selected",
  cancel: "Cancel",
  add: "Add",
  mismatchBefore: "Bound to ",
  mismatchMiddle: ", which this agent doesn't appear on. Add ",
  mismatchAfter: " on the Basics step to use it.",
  inactiveMessage: "Inactive. It will be linked but won't run until it's activated on the AI Tools tab.",
  noVersionMessage: "This flow has no active version. It will be linked but the agent won't offer it until a version is active.",
  apexType: "Apex",
  flowType: "Flow",
  screenFlowType: "Screen flow"
};
