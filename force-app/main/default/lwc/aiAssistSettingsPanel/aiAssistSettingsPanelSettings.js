/*
Component Name: aiAssistSettingsPanel

=================================================================
=================================================================

Description: One settings object on the Settings tab, with Org-wide, Profiles and Users sub-tabs.

Step 1: Show the organisation row, or the profiles or users that have a row, as a list beside the form
Step 2: Let the admin find a profile or user and start a new row that begins as a copy of the organisation values
Step 3: Save, or delete, one row through Apex and tell the Settings tab to reload

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The three levels a row can be at. Mirrors AIAssistApplicationConstants.SETTINGS_SCOPE_*.
export const SCOPE_ORGANISATION = "Organisation";
export const SCOPE_PROFILE = "Profile";
export const SCOPE_USER = "User";

// The settings object that has only a few fields a profile or user may override. Mirrors AIAssistApplicationConstants.SETTINGS_NAME_ASSIST.
export const SETTINGS_NAME_ASSIST = "AIAssistSettings__c";

// The events this component sends to the Settings tab.
export const EVENT_REFRESH = "refresh";

// How the owner search behaves.
export const SEARCH_MIN_LENGTH = 2;
export const SEARCH_DELAY_MILLISECONDS = 300;

// Toast settings.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";

// The message shown when an error has no readable text.
export const FALLBACK_ERROR_MESSAGE = "Something went wrong. Please try again.";

// The style of the confirm dialog that asks before a row is deleted.
export const CONFIRM_VARIANT = "default";

// The text that joins the parts of the form key, so the form is built again when any part changes.
export const FORM_KEY_SEPARATOR = "|";

// The text of a message or a search box when it is empty.
export const NO_TEXT = "";

// The text around the row count on a sub-tab, for example "Profiles (2)".
export const TAB_COUNT_OPEN = " (";
export const TAB_COUNT_CLOSE = ")";

// The classes of one sub-tab; the open tab also gets the second one.
export const SUB_TAB_CLASS = "aiasp-tab";
export const SUB_TAB_ACTIVE_CLASS = "aiasp-tab aiasp-tab_active";

// Text shown to the user.
export const LABELS = {
  organisationTab: "Org-wide",
  profileTab: "Profiles",
  userTab: "Users",
  organisationIntroOnly: "Applies to everyone.",
  organisationIntroAssist: "Applies to everyone. Five limits can also be set for a profile or a user, and the rest stay here.",
  organisationIntroUi: "Applies to everyone who has no profile or user row. This is the starting point for every other row.",
  profileIntroAssist: "A profile row replaces the five limits for everyone on that profile, unless they also have a user row.",
  profileIntroUi: "A profile row replaces the organisation row for everyone on that profile, unless they also have a user row.",
  userIntroAssist: "A user row replaces the five limits for that user.",
  userIntroUi: "A user row wins over the profile row and the organisation row. Pick a user to change their chat window.",
  profileListLabel: "Profiles with a row",
  userListLabel: "Users with a row",
  findProfile: "Find a profile to add",
  findUser: "Find a user to add",
  newRowSuffix: " (new)",
  chooseOne: "Choose a row from the list, or find one to add.",
  newRowNote: "This row is not saved yet. It starts as a copy of the organisation values.",
  deleteRow: "Delete row",
  removeRow: "Remove",
  deleteTitle: "Delete this row?",
  deleteMessage: "The profile or user goes back to the organisation values.",
  saved: "Settings saved",
  deleted: "Row deleted",
  noResults: "No matching profile or user without a row.",
  working: "Working"
};
