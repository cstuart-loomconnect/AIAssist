/*
Component Name: aiPoliciesAssignments

=================================================================
=================================================================

Description: The settings of the Assignments tab: assignee types, class names, event names and label text.

Step 1: Name the assignee types, classes and events the controller uses
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The assignee type of a user. Mirrors AIAssistApplicationConstants.ASSIGNEE_TYPE_USER.
export const ASSIGNEE_TYPE_USER = "User";

// The classes of the type pill: blue for a permission set, grey for a user.
export const TYPE_PILL_PERMISSION_SET_CLASS = "aipa-pill aipa-pill_permission-set";
export const TYPE_PILL_USER_CLASS = "aipa-pill aipa-pill_user";

// The names of the events the component sends to the tab.
export const EVENT_ADD_REQUEST = "addrequest";
export const EVENT_ACTIVE_CHANGE = "activechange";
export const EVENT_REMOVE = "remove";
export const EVENT_ASSIGN_USER = "assignuser";

// The selector of the Check a user box.
export const CHECK_USER_SELECTOR = "c-ai-policies-check-user";

// The text of a value when it is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  whoGets: "Who gets this policy",
  addAssignment: "+ Add assignment",
  columnType: "Type",
  columnAssignedTo: "Assigned to",
  columnUsersCovered: "Users covered",
  columnActive: "Active",
  typePermissionSet: "Permission set",
  typeUser: "User",
  userCaption: "Overrides their permission sets",
  remove: "Remove",
  none: "Nobody is assigned to this policy yet.",
  on: "On",
  off: "Off",
  howChosen: "How a user's policy is chosen",
  stepUser: "1 · User assignment",
  stepPermissionSet: "2 · Permission set assignment",
  stepDefault: "3 · Default policy",
  then: "then",
  stricterWins: "If two permission sets give a user different policies, the stricter one (lowest daily token limit) wins."
};
