/*
Component Name: aiChatSuggestedAction

=================================================================
=================================================================

Description: Settings for aiChatSuggestedAction: display modes, statuses, label text, class names and event names.

Step 1: DISPLAY values decide card or inline look
Step 2: ACTION_STATUS and MODE hold the status and step names the controller compares against
Step 3: INPUT_TYPE, CONTAINER_CLASS and EVENTS hold the field types, class names and event names
Step 4: LABELS holds every piece of text the component shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// How the parent wants the action shown (mirrors the Actions Display picklist value on the chat settings)
export const ACTIONS_DISPLAY_INLINE_BUTTONS = "Inline Buttons";
export const DEFAULT_DISPLAY = "Cards";

// Status of the action, handed in by the parent through the state property
export const ACTION_STATUS = {
  IDLE: "idle",
  RUNNING: "running",
  DONE: "done",
  FAILED: "failed",
  DISMISSED: "dismissed"
};

// Which step of the component the user is on
export const MODE = {
  BUTTONS: "buttons",
  EDITING: "editing",
  CONFIRMING: "confirming"
};

// Input types an action can ask for (mirrors the input type on the action's input fields)
export const INPUT_TYPE = {
  TEXTAREA: "textarea",
  CHECKBOX: "checkbox"
};

// Class names for the outer container (defined in the CSS file)
export const CONTAINER_CLASS = {
  CARD: "card",
  INLINE: "inline"
};

// Names of the events sent to the parent
export const EVENTS = {
  RUN: "run",
  DECLINE: "decline",
  DISMISS: "dismiss"
};

// Selector for the inputs the user can edit before running
export const EDITABLE_INPUT_SELECTOR = "lightning-input, lightning-textarea";

// Text shown on the component
export const LABELS = {
  suggestedAction: "Suggested action",
  editFirst: "Edit first",
  dismiss: "Dismiss",
  confirm: "Confirm",
  cancel: "Cancel",
  actionDone: "Done"
};
