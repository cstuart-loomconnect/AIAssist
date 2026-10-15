/*
Component Name: aiAssistUsagePolicies

=================================================================
=================================================================

Description: The settings of the AI Usage Policies tab: field groups, class names, starting values and label text.

Step 1: Describe the three groups that hold every field of an AI Usage Policy
Step 2: Name the classes, keys and starting values the controller uses
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The kinds of control a field can use. Each one is a value the field component understands.
const FIELD_TYPE_TOGGLE = "toggle";
const FIELD_TYPE_NUMBER = "number";
const FIELD_TYPE_TEXT = "text";
const FIELD_TYPE_SELECT = "select";
const FIELD_TYPE_MULTI = "multi";

// The object the fields belong to. Mirrors AIUsagePolicy__c.
const OBJECT_NAME_USAGE_POLICY = "AIUsagePolicy__c";

// The fields the controller and Helper read by name. Mirror the fields on AIUsagePolicy__c.
export const FIELD_NAME = "Name";
export const FIELD_IS_ACTIVE = "IsActive__c";
export const FIELD_IS_DEFAULT = "IsDefault__c";

// The key of a policy that is not saved yet.
export const NEW_POLICY_KEY = "new";

// The text that joins the parts of the form key, so the form is built again when any part changes.
export const FORM_KEY_SEPARATOR = "|";

// The style of the confirm dialog that asks before a policy is deleted.
export const CONFIRM_VARIANT = "default";

// The text of a message when it is empty.
export const NO_TEXT = "";

// The sort rank of a policy in the list: default policies come first.
export const RANK_DEFAULT_FIRST = 0;
export const RANK_DEFAULT_LAST = 1;

// The classes of one policy in the list and of the pills beside it; the chosen policy also gets the second class.
export const POLICY_ITEM_CLASS = "aiasp-item";
export const POLICY_ITEM_SELECTED_CLASS = "aiasp-item aiasp-item_selected";
export const PILL_ACTIVE_CLASS = "aiasp-pill aiasp-pill_active";
export const PILL_INACTIVE_CLASS = "aiasp-pill aiasp-pill_inactive";
export const PILL_DEFAULT_CLASS = "aiasp-pill aiasp-pill_default";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";

// The values a new policy starts with. They match the defaults on the AIUsagePolicy__c fields.
export const NEW_POLICY_VALUES = { Name: "", Description__c: "", IsActive__c: true, IsDefault__c: false, IsUserInitiatedChatEnabled__c: true, ConversationExportEnabled__c: false, DebugModeEnabled__c: false, ShouldCaptureExecutionSteps__c: false };

// Text shown to the user.
export const LABELS = {
  intro: "A policy sets the limits and features for the people it is assigned to. When a person has several policies the strictest limit wins and the widest features win. A person with no policy gets the active default policies. A person who needs different limits or features is assigned a policy of their own.",
  newPolicy: "New policy",
  newPolicyName: "New policy",
  noPolicies: "There are no policies yet. Create the first one.",
  chooseOne: "Choose a policy from the list, or create a new one.",
  newPolicyNote: "This policy is not saved yet. Save it first, then assign it to people.",
  active: "Active",
  inactive: "Inactive",
  defaultPill: "Default",
  deletePolicy: "Delete policy",
  deleteTitle: "Delete this policy?",
  deleteMessage: "The policy and all of its assignments are deleted. People who only had this policy fall back to the default policies.",
  deleted: "Policy deleted.",
  saved: "Policy saved.",
  loading: "Loading policies",
  assignmentCountOne: " assignment",
  assignmentCountMany: " assignments",
  fallbackError: "Something went wrong. Please try again."
};

// The three groups of an AI Usage Policy. Together they hold every editable field of AIUsagePolicy__c.
export const POLICY_GROUPS = [
  {
    key: "details", label: "Details", objectName: OBJECT_NAME_USAGE_POLICY,
    fields: [
      { key: "Name", label: "Name", type: FIELD_TYPE_TEXT, required: true, maxLength: 80, help: "What people will see in the list." },
      { key: "Description__c", label: "Description", type: FIELD_TYPE_TEXT, maxLength: 255, help: "What this policy is for and who it is meant for." },
      { key: "IsActive__c", label: "Active", type: FIELD_TYPE_TOGGLE, help: "An inactive policy applies to nobody." },
      { key: "IsDefault__c", label: "Default policy", type: FIELD_TYPE_TOGGLE, help: "Applies to everyone who has no assignment to another active policy. More than one policy can be a default." }
    ]
  },
  {
    key: "limits", label: "Usage limits", objectName: OBJECT_NAME_USAGE_POLICY,
    fields: [
      { key: "MaxTokensPer24Hours__c", label: "Tokens per day", type: FIELD_TYPE_NUMBER, unit: "tokens", min: 1, max: 999999999999999, help: "Tokens a person may use in one day. The count restarts each day in the org time zone.", blankHelp: "Blank means no limit." },
      { key: "MaxConversationsPer24Hours__c", label: "Conversations per day", type: FIELD_TYPE_NUMBER, unit: "conversations", min: 1, max: 99999, help: "New conversations a person may start in one day.", blankHelp: "Blank means no limit." },
      { key: "MaxConcurrentConversations__c", label: "Open conversations at once", type: FIELD_TYPE_NUMBER, unit: "conversations", min: 1, max: 99, help: "Conversations a person may have open at the same time.", blankHelp: "Blank means no limit." },
      { key: "UsageLimitReachedBehavior__c", label: "When a limit is reached", type: FIELD_TYPE_SELECT, help: "What happens once any limit above is hit.", options: [{ label: "Block New Messages", value: "Block New Messages" }, { label: "Block New Conversations Only", value: "Block New Conversations Only" }, { label: "Notify Only", value: "Notify Only" }] }
    ]
  },
  {
    key: "access", label: "Access and features", objectName: OBJECT_NAME_USAGE_POLICY,
    fields: [
      { key: "IsUserInitiatedChatEnabled__c", label: "Can start chats", type: FIELD_TYPE_TOGGLE, help: "Off lets people read replies but not start a conversation." },
      { key: "AllowedChannels__c", label: "Allowed channels", type: FIELD_TYPE_MULTI, help: "Where people on this policy can reach AI Assist from. Leave all unticked to allow every channel.", options: [{ label: "Record Page Chat", value: "Record Page Chat" }, { label: "Utility Bar", value: "Utility Bar" }, { label: "Mobile", value: "Mobile" }] },
      { key: "ConversationVisibilityScope__c", label: "Conversation visibility", type: FIELD_TYPE_SELECT, help: "Whose conversations people on this policy can open.", options: [{ label: "My Conversations Only", value: "My Conversations Only" }, { label: "My Subordinates Conversations", value: "My Subordinates Conversations" }, { label: "All Conversations", value: "All Conversations" }] },
      { key: "ConversationExportEnabled__c", label: "Can export conversations", type: FIELD_TYPE_TOGGLE, help: "Lets people download a conversation." },
      { key: "DebugModeEnabled__c", label: "Debug mode", type: FIELD_TYPE_TOGGLE, help: "Shows the debug trace on replies." },
      { key: "ShouldCaptureExecutionSteps__c", label: "Capture execution steps", type: FIELD_TYPE_TOGGLE, help: "Keeps each step of a reply on the conversation." }
    ]
  }
];
