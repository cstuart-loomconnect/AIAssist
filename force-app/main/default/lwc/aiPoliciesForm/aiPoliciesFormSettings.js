/*
Component Name: aiPoliciesForm

=================================================================
=================================================================

Description: The settings of the policy form: the sections and rows it shows, field names, class names and label text.

Step 1: Describe every section and row of the form, with the field each one saves to
Step 2: Name the events, field keys and classes the controller uses
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The kinds of control a row can use.
export const ROW_TYPE_NUMBER = "number";
export const ROW_TYPE_SEGMENTS = "segments";
export const ROW_TYPE_TOGGLE = "toggle";
export const ROW_TYPE_SELECT = "select";
export const ROW_TYPE_MULTI = "multi";

// The fields the controller and Helper read by name. Mirror the fields on AIUsagePolicy__c.
export const FIELD_NAME = "Name";
export const FIELD_DESCRIPTION = "Description__c";
export const FIELD_IS_ACTIVE = "IsActive__c";
export const FIELD_IS_DEFAULT = "IsDefault__c";
export const FIELD_CHANNELS = "AllowedChannels__c";

// The fields that hold a whole number above zero, or blank for no limit.
export const LIMIT_FIELDS = [
  "MaxTokensPer24Hours__c",
  "MaxConversationsPer24Hours__c",
  "MaxConcurrentConversations__c"
];

// A multi-select picklist is stored as text split by this character. Mirrors AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR.
export const MULTI_SEPARATOR = ";";

// The longest text each box takes. Mirror the lengths of Name and Description__c on AIUsagePolicy__c.
export const NAME_MAX_LENGTH = 80;
export const DESCRIPTION_MAX_LENGTH = 255;

// The names of the events the form sends to the tab.
export const EVENT_SAVE = "save";
export const EVENT_CANCEL = "cancel";

// The classes of one choice in the segmented control; the chosen choice also gets the second class.
export const SEGMENT_CLASS = "aipf-segment";
export const SEGMENT_SELECTED_CLASS = "aipf-segment aipf-segment_selected";

// The text of a message or a value when it is empty, and the group separator for numbers.
export const NO_TEXT = "";
export const NUMBER_LOCALE = "en-GB";

// The sections and rows of the form. Each row saves to the field named by its key. Together they hold every editable field except the name, description, Active and Default, which sit above them.
export const SECTIONS = [
  {
    key: "limits",
    label: "Daily limits",
    rows: [
      {
        key: "MaxTokensPer24Hours__c",
        label: "Tokens per 24 hours",
        help: "Input and output tokens across all of a user's conversations.",
        type: ROW_TYPE_NUMBER
      },
      {
        key: "MaxConversationsPer24Hours__c",
        label: "Conversations per 24 hours",
        help: "New conversations a user can start.",
        type: ROW_TYPE_NUMBER
      },
      {
        key: "MaxConcurrentConversations__c",
        label: "Open conversations at once",
        help: "Across all records.",
        type: ROW_TYPE_NUMBER
      }
    ]
  },
  {
    key: "behavior",
    label: "When a limit is hit",
    rows: [
      {
        key: "UsageLimitReachedBehavior__c",
        label: "When a limit is hit",
        type: ROW_TYPE_SEGMENTS,
        options: [
          {
            label: "Block new messages",
            value: "Block New Messages",
            help: "Users are stopped straight away and can't send anything until the 24 hours roll over."
          },
          {
            label: "Block new conversations only",
            value: "Block New Conversations Only",
            help: "Users can finish what they're doing but can't start anything new until the 24 hours roll over."
          },
          {
            label: "Notify only",
            value: "Notify Only",
            help: "Users see a warning but can carry on."
          }
        ]
      }
    ]
  },
  {
    key: "abilities",
    label: "What users can do",
    rows: [
      {
        key: "IsUserInitiatedChatEnabled__c",
        label: "Start a chat themselves",
        help: "Off means only automated or suggested prompts.",
        type: ROW_TYPE_TOGGLE
      },
      {
        key: "ConversationExportEnabled__c",
        label: "Export conversations",
        help: "Download a transcript as PDF.",
        type: ROW_TYPE_TOGGLE
      },
      {
        key: "ConversationVisibilityScope__c",
        label: "See conversations",
        help: "Whose conversations appear in their history.",
        type: ROW_TYPE_SELECT,
        options: [
          { label: "My Conversations Only", value: "My Conversations Only" },
          {
            label: "My Subordinates Conversations",
            value: "My Subordinates Conversations"
          },
          { label: "All Conversations", value: "All Conversations" }
        ]
      },
      {
        key: "AllowedChannels__c",
        label: "Channels",
        help: "Where they can use AI Assist. Tick none to allow every channel.",
        type: ROW_TYPE_MULTI,
        options: [
          { label: "Record Page Chat", value: "Record Page Chat" },
          { label: "Utility Bar", value: "Utility Bar" },
          { label: "Mobile", value: "Mobile" }
        ]
      }
    ]
  },
  {
    key: "debugging",
    label: "Debugging",
    rows: [
      {
        key: "DebugModeEnabled__c",
        label: "Debug mode",
        help: "Shows the execution trace under replies.",
        type: ROW_TYPE_TOGGLE
      },
      {
        key: "ShouldCaptureExecutionSteps__c",
        label: "Capture execution steps",
        help: "Saves each tool call for QA review. Uses storage.",
        type: ROW_TYPE_TOGGLE
      }
    ]
  }
];

// Text shown to the user.
export const LABELS = {
  name: "Name",
  description: "Description",
  active: "Active",
  defaultLabel: "Default",
  required: "* ",
  cancel: "Cancel",
  save: "Save",
  saving: "Saving",
  on: "On",
  off: "Off",
  blankHelp: "Leave blank for no limit.",
  nameRequired: "Enter a name for the policy.",
  limitProblemPart1: " must be a whole number above zero. ",
  limitProblemPart2: "Leave it blank for no limit."
};
