/*
Component Name: aiPoliciesAssignDialog

=================================================================
=================================================================

Description: The settings of the Add assignment dialog: assignee types, search timing, class names and label text.

Step 1: Name the assignee types, search timing, classes and events the controller uses
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The assignee types Apex understands. Mirror AIAssistApplicationConstants.ASSIGNEE_TYPE_USER and ASSIGNEE_TYPE_PERMISSION_SET.
export const ASSIGNEE_TYPE_USER = "User";
export const ASSIGNEE_TYPE_PERMISSION_SET = "Permission Set";

// How many characters the admin types before a search runs, and how long to wait after the last key press, in milliseconds.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MILLISECONDS = 300;

// The classes of one choice in the User or Permission set switch; the chosen choice also gets the second class.
export const TYPE_BUTTON_CLASS = "aipad-type";
export const TYPE_BUTTON_SELECTED_CLASS = "aipad-type aipad-type_selected";

// The classes of one assignee in the list; the chosen assignee also gets the second class, and one that cannot be picked gets the third.
export const OPTION_CLASS = "aipad-option";
export const OPTION_SELECTED_CLASS = "aipad-option aipad-option_selected";
export const OPTION_DISABLED_CLASS = "aipad-option aipad-option_disabled";

// The names of the events the dialog sends to the tab.
export const EVENT_CANCEL = "cancel";
export const EVENT_CONFIRM = "confirm";

// The text of a value when it is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  title: "Add assignment",
  assignTo: "Assign to",
  typeUser: "User",
  typePermissionSet: "Permission set",
  searchUsers: "Search users",
  searchPermissionSets: "Search permission sets",
  typeMore: "Type at least 2 characters to search.",
  searching: "Searching",
  noMatches: "Nothing matches.",
  userOne: " user",
  userMany: " users",
  currentlyGet: " · currently get ",
  defaultSuffix: " (default)",
  noCurrentPolicy: "no policy",
  alreadyHasPolicy: "Already has a policy",
  alreadyOnThisPolicy: "Already on this policy",
  cancel: "Cancel",
  assign: "Assign",
  saving: "Assigning",
  fallbackError: "Something went wrong. Please try again."
};
