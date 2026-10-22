/*
Component Name: aiPolicies

=================================================================
=================================================================

Description: The settings of the AI Policies tab: keys, class names, starting values and label text.

Step 1: Name the keys, tab values and classes the controller uses
Step 2: Hold the values a new policy starts with
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The key of a policy that is not saved yet.
export const NEW_POLICY_KEY = "new";

// The text that joins the parts of a form key, so the form is built again when any part changes.
export const FORM_KEY_SEPARATOR = "|";

// The text of a message when it is empty.
export const NO_TEXT = "";

// The value of each tab inside the chosen policy.
export const TAB_SETTINGS = "settings";
export const TAB_ASSIGNMENTS = "assignments";

// The fields the controller and Helper read by name. Mirror the fields on AIUsagePolicy__c.
export const FIELD_NAME = "Name";
export const FIELD_IS_DEFAULT = "IsDefault__c";

// The assignee types Apex understands. Mirror AIAssistApplicationConstants.ASSIGNEE_TYPE_USER and ASSIGNEE_TYPE_PERMISSION_SET.
export const ASSIGNEE_TYPE_USER = "User";
export const ASSIGNEE_TYPE_PERMISSION_SET = "Permission Set";

// The sort rank of a policy in the list: the default policy comes first.
export const RANK_DEFAULT_FIRST = 0;
export const RANK_DEFAULT_LAST = 1;

// The classes of one policy in the list; the chosen policy also gets the second class.
export const POLICY_ITEM_CLASS = "aip-item";
export const POLICY_ITEM_SELECTED_CLASS = "aip-item aip-item_selected";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";

// The values a new policy starts with. They match the defaults on the AIUsagePolicy__c fields.
export const NEW_POLICY_VALUES = { Name: "", Description__c: "", IsActive__c: true, IsDefault__c: false, UsageLimitReachedBehavior__c: "Block New Conversations Only", IsUserInitiatedChatEnabled__c: true, ConversationExportEnabled__c: false, ConversationVisibilityScope__c: "My Conversations Only", DebugModeEnabled__c: false, ShouldCaptureExecutionSteps__c: false };

// Text shown to the user.
export const LABELS = {
  title: "AI Policies",
  subtitle: "Usage limits and who they apply to",
  intro: "Usage policies cap how much each user can use AI Assist. Assign them to permission sets for teams, or to a single user for an exception.",
  newPolicy: "+ New policy",
  newPolicyName: "New policy",
  newPolicyNote: "Not saved yet",
  noPolicies: "There are no policies yet. Create the first one.",
  chooseOne: "Choose a policy from the list, or create a new one.",
  defaultPill: "Default",
  deletePolicy: "Delete policy",
  settingsTab: "Settings",
  assignmentsTab: "Assignments",
  noAssignments: "No assignments",
  defaultPrefix: "Default",
  summarySeparator: " · ",
  permissionSetOne: " permission set",
  permissionSetMany: " permission sets",
  userOne: " user",
  userMany: " users",
  saved: "Policy saved.",
  deleted: "Policy deleted.",
  assigned: "Assignment added.",
  removed: "Assignment removed.",
  loading: "Loading policies",
  fallbackError: "Something went wrong. Please try again."
};
