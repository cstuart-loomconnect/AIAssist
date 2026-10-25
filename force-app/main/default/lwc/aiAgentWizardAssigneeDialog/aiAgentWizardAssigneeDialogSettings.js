/*
Component Name: aiAgentWizardAssigneeDialog

=================================================================
=================================================================

Description: The settings of the Add assignment dialog of the AI Agent Wizard: assignee types, search timings, class names and label text.

Step 1: Name the assignee types
Step 2: Hold the search timings and the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIAgentAssignment__c.AssigneeType__c.
export const ASSIGNEE_USER = "User";
export const ASSIGNEE_PERMISSION_SET = "Permission Set";

// The two types the dialog offers.
export const TYPE_CHOICES = [
  { value: ASSIGNEE_PERMISSION_SET, label: "Permission set" },
  { value: ASSIGNEE_USER, label: "User" }
];

// The search: letters needed before it runs, and the wait after the last key press.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MILLISECONDS = 300;

// The classes of a type button and of a row.
export const SEG_CLASS = "aiawdi-seg-button";
export const SEG_SELECTED_CLASS = "aiawdi-seg-button aiawdi-seg-button_selected";
export const OPTION_CLASS = "aiawdi-option";
export const OPTION_SELECTED_CLASS = "aiawdi-option aiawdi-option_selected";
export const OPTION_DISABLED_CLASS = "aiawdi-option aiawdi-option_disabled";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  title: "Add assignment",
  searchUsers: "Search users by name",
  searchPermissionSets: "Search permission sets by name",
  typeMore: "Type at least 2 letters to search.",
  searching: "Searching",
  noMatches: "Nothing matches that search.",
  userOne: "1 user",
  userMany: " users",
  alreadyAdded: "Already added",
  cancel: "Cancel",
  add: "Add"
};
