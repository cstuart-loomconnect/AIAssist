/*
Component Name: aiChatMessage

=================================================================
=================================================================

Description: Settings for aiChatMessage: the label text, class names, icons, save targets, event and action names, and the clipboard values.

Step 1: Hold the label text the template shows
Step 2: Hold the class names and attribute values the getters return
Step 3: Hold the event and action names sent to aiAssistChat
Step 4: Hold the places a reply can be saved to
Step 5: Hold the values the clipboard fallback uses

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Feedback ratings sent to aiAssistChat. They mirror the AIMessage__c.FeedbackRating__c picklist values.
export const FEEDBACK_RATING = {
  HELPFUL: "Helpful",
  NOT_HELPFUL: "Not Helpful"
};

// Icons for the copy button
export const ICON = {
  COPIED: "utility:check",
  COPY: "utility:copy"
};

// Class names for the user bubble
export const CLASS_USER_BUBBLE = "user-bubble";
export const CLASS_USER_BUBBLE_SENDING = "user-bubble user-bubble_sending";

// Class names for the thumbs buttons
export const CLASS_TOOL = "aia-icon-btn aia-icon-btn_small tool";
export const CLASS_TOOL_HELPFUL = "aia-icon-btn aia-icon-btn_small tool tool_helpful";
export const CLASS_TOOL_NOT_HELPFUL = "aia-icon-btn aia-icon-btn_small tool tool_not-helpful";

// aria-pressed values for the thumbs buttons
export const ARIA_PRESSED_TRUE = "true";
export const ARIA_PRESSED_FALSE = "false";

// SVG fill values for the thumbs icons
export const FILL_SELECTED = "currentColor";
export const FILL_UNSELECTED = "none";

// The one event sent to aiAssistChat. detail: { action, messageId, ...extra }
export const EVENT_MESSAGE_ACTION = "messageaction";

// The values of detail.action that aiAssistChat reads
export const ACTION = {
  RATE: "rate",
  SUBMIT_FEEDBACK: "submitfeedback",
  CLOSE_FEEDBACK: "closefeedback",
  REGENERATE: "regenerate",
  RUN_ACTION: "runaction",
  DISMISS_ACTION: "dismissaction",
  DECLINE_ACTION: "declineaction",
  LOAD_TRACE: "loadtrace",
  CLOSE_TRACE: "closetrace",
  SAVE_TO_RECORD: "savetorecord"
};

// Where a reply can be saved, with the icon each menu row shows. The targets mirror the Apex constants SAVE_TARGET_NOTE and SAVE_TARGET_TASK.
export const SAVE_TARGET = {
  NOTE: "NOTE",
  TASK: "TASK"
};

export const SAVE_OPTIONS = [
  { target: SAVE_TARGET.NOTE, label: "Save to Notes", iconName: "utility:note" },
  { target: SAVE_TARGET.TASK, label: "Create Task", iconName: "utility:task" }
];

// The Save to record menu: the text a screen reader hears for open and closed, and the key that closes it
export const ARIA_EXPANDED_TRUE = "true";
export const ARIA_EXPANDED_FALSE = "false";
export const KEY_ESCAPE = "Escape";
export const SAVE_WRAP_SELECTOR = ".save-wrap";

// Values for the hidden text box used when the Clipboard API is blocked
export const CLIPBOARD_FALLBACK = {
  ELEMENT: "textarea",
  READONLY_ATTRIBUTE: "readonly",
  POSITION: "fixed",
  OPACITY: "0",
  COMMAND: "copy"
};

// Label text shown in the template
export const LABELS = {
  helpful: "Helpful",
  notHelpful: "Not helpful",
  copy: "Copy",
  copied: "Copied",
  regenerate: "Regenerate",
  saveToRecord: "Save to record",
  sources: "Sources",
  skill: "Skill",
  feedbackThanks: "Thanks — your feedback was sent.",
  showTrace: "Show request trace"
};
