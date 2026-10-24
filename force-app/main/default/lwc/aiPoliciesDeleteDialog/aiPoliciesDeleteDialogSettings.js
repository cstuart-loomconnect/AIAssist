/*
Component Name: aiPoliciesDeleteDialog

=================================================================
=================================================================

Description: The settings of the delete dialog: the two ways to move people, event names and label text.

Step 1: Name the ways to move people and the events the controller uses
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two ways to move the people of a policy that is deleted.
export const MOVE_TO_DEFAULT = "default";
export const MOVE_TO_OTHER = "other";

// The names of the events the dialog sends to the tab.
export const EVENT_CANCEL = "cancel";
export const EVENT_CONFIRM = "confirm";

// The text of a value when it is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  titlePrefix: 'Delete "',
  titleSuffix: '"?',
  loading: "Loading",
  isAssignedTo: " is assigned to ",
  userOne: " user",
  userMany: " users",
  chooseWhat: ". Choose what happens to them before deleting.",
  noAssignments: " has no assignments, so nobody is affected.",
  moveToDefaultPrefix: "Move them to the default policy (",
  moveToDefaultSuffix: ")",
  moveToOther: "Move them to another policy",
  chooseAPolicy: "Choose a policy",
  openUsage:
    "Their usage so far today still counts. The new limits apply from their next message.",
  defaultCannotBeDeleted:
    "The default policy can't be deleted. To delete it, make another policy the default first.",
  noOtherPolicy: "There is no other policy to move them to. Create one first.",
  cancel: "Cancel",
  moveAndDelete: "Move users and delete",
  delete: "Delete policy",
  saving: "Deleting",
  fallbackError: "Something went wrong. Please try again."
};
