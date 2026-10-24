/*
Component Name: aiPromptTemplatesList

=================================================================
=================================================================

Description: The settings of the template list: class names, status words and label text.

Step 1: Name the classes of the rows and pills
Step 2: Hold the status words
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The classes of a list row and its pills.
export const ROW_CLASS = "aipt-row slds-grid slds-grid_vertical slds-p-horizontal_small slds-p-vertical_small";
export const ROW_SELECTED_CLASS = "aipt-row aipt-row_selected slds-grid slds-grid_vertical slds-p-horizontal_small slds-p-vertical_small";
export const PILL_LIVE_CLASS = "aipt-pill aipt-pill_success";
export const PILL_INACTIVE_CLASS = "aipt-pill aipt-pill_neutral";

// Text shown to the user.
export const LABELS = {
  newTemplate: "+ New template",
  newRowName: "New template",
  newRowDetail: "Not saved yet",
  searchLabel: "Search templates",
  searchPlaceholder: "Search templates",
  noMatches: "No template matches your search.",
  statusLive: "Live",
  statusInactive: "Inactive",
  statusDefault: "Default",
  notUsed: "not used",
  agentOne: "agent",
  agentMany: "agents"
};
