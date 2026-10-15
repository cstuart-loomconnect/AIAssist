/*
Component Name: aiAssistSettingsForm

=================================================================
=================================================================

Description: The form for one settings row: a list of groups on the left, the fields of the chosen group on the right, and Save and Cancel.

Step 1: Show the groups of the row as a side list and the fields of the chosen group beside it
Step 2: Keep every change in a draft until the admin saves
Step 3: Check the draft for blank required numbers and numbers out of range before sending it
Step 4: Tell the panel to save the draft, and show any error the panel hands back

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The events this component sends to the panel.
export const EVENT_SAVE = "save";

// Short text beside a field in the organisation row of AI Assist Settings, saying whether a profile or user row may override it.
export const BADGE_CAN_OVERRIDE = "Can be overridden";
export const BADGE_ORG_WIDE_ONLY = "Org-wide only";

// The classes of one item in the group list; the selected item also gets the second one.
export const GROUP_ITEM_CLASS = "aiasf-group";
export const GROUP_ITEM_SELECTED_CLASS = "aiasf-group aiasf-group_selected";

// The field component inside the form, found by name so each one can be asked to check itself.
export const FIELD_COMPONENT_SELECTOR = "c-ai-assist-settings-field";

// The text of a blank value, and of a message when there is nothing to say.
export const EMPTY_TEXT = "";
export const NO_MESSAGE = EMPTY_TEXT;

// The text that joins the object name and the field name, for example AIAssistSettings__c.MaxMessageLength__c.
export const API_NAME_SEPARATOR = ".";

// The full stop that ends a range message.
export const SENTENCE_END = ".";

// Text shown to the user.
export const LABELS = {
  groupsLabel: "Settings groups",
  fieldsSuffix: " fields",
  fieldSuffix: " field",
  save: "Save",
  saving: "Saving...",
  cancel: "Cancel",
  unsaved: "Unsaved changes",
  noChanges: "No changes",
  requiredMessage: " is required.",
  rangeMessagePart1: " must be a whole number from ",
  rangeMessagePart2: " to "
};
