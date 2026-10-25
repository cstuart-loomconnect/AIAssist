/*
Component Name: aiChatSaveDialog

=================================================================
=================================================================

Description: Settings for aiChatSaveDialog: the wording for each place a reply can be saved, the key that closes the dialog, the text box selector, event names and label text.

Step 1: Hold the wording for each save target
Step 2: Hold the key, selector and event names
Step 3: Hold the label text the template shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The wording for each place a reply can be saved. The keys mirror the Apex constants SAVE_TARGET_NOTE and SAVE_TARGET_TASK.
export const TARGET_NOTE = "NOTE";
export const TARGET_COPY = {
  NOTE: { heading: "Save to Notes", hint: "Adds this text as a note on the record this conversation is about.", saveLabel: "Save note" },
  TASK: { heading: "Create Task", hint: "Creates a task on the record this conversation is about, assigned to you.", saveLabel: "Create task" }
};

// The key that closes the dialog, and how it finds the text box
export const KEY_ESCAPE = "Escape";
export const TEXT_SELECTOR = "textarea";

// Events sent to the parent
export const EVENT_SAVE = "save"; // detail: { text }
export const EVENT_CANCEL = "cancel"; // No detail

// Label text shown in the template
export const LABELS = {
  textLabel: "Text to save",
  textHelp: "You can change the text before it is saved.",
  cancel: "Cancel",
  saving: "Saving"
};
