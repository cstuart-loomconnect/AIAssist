/*
Component Name: aiAgentWizardStepAccess

=================================================================
=================================================================

Description: The settings of the Access step of the AI Agent Wizard: access modes, assignee types, search timings, class names and label text.

Step 1: Name the access modes and the assignee types
Step 2: Hold the search timings and the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIAgent__c.AccessMode__c.
export const ACCESS_ALL = "All AI Assist Users";
export const ACCESS_ASSIGNED = "Assigned Users Only";

// The two access cards.
export const ACCESS_CARDS = [
  { value: ACCESS_ALL, title: "All AI Assist users", detail: "Anyone with the AI Assist User permission set." },
  { value: ACCESS_ASSIGNED, title: "Assigned users only", detail: "Only the people and permission sets you add here." }
];

// Values that mirror AIAgentAssignment__c.AssigneeType__c.
export const ASSIGNEE_USER = "User";
export const ASSIGNEE_PERMISSION_SET = "Permission Set";

// The check of one user: letters needed before the search runs, and the wait after the last key press.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MILLISECONDS = 300;

// The classes of a card, of a type tag and of a result note.
export const CARD_CLASS = "aiawac-card";
export const CARD_SELECTED_CLASS = "aiawac-card aiawac-card_selected";
export const TAG_PERMISSION_SET_CLASS = "aiawac-pill aiawac-pill_accent";
export const TAG_USER_CLASS = "aiawac-pill";
export const NOTE_SUCCESS_CLASS = "aiawac-note aiawac-note_success";
export const NOTE_DANGER_CLASS = "aiawac-note aiawac-note_danger";

// The text between the parts of a list of objects.
export const LIST_SEPARATOR = ", ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  whoCanUse: "Who can use this agent?",
  assignments: "Assignments",
  add: "+ Add",
  permissionSet: "Permission set",
  user: "User",
  userOne: "1 user",
  userMany: " users",
  noAssignments: "No one is assigned yet.",
  checkUser: "Check a user",
  checkPlaceholder: "Type a name to see if they'll have access",
  searching: "Searching",
  noMatches: "No users match.",
  checking: "Checking",
  hasAccess: " will have access.",
  noAccess: " will not have access.",
  seeBefore: " users will see this agent on ",
  seeAllBefore: "All ",
  seeAllMiddle: " AI Assist users will see this agent on ",
  seeAfter: " pages.",
  and: " and ",
  pickerNote: "If another agent also appears on {object} for these users, they'll get an agent picker in the chat window.",
  pickerNoteFallback: "a record page",
  needLookOne: "1 thing needs a look.",
  needLookMany: " things need a look.",
  wontStopSaving: " They won't stop you saving.",
  activeToggle: "Active"
};
