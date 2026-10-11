/*
Component Name: aiChatWorkingIndicator

=================================================================
=================================================================

Description: Shows the user that a reply is being worked on, as a step card or a lighter typing indicator.

Step 1: The parent (aiAssistChat) decides the mode and passes in the label, the clock and the steps
Step 2: The step card lists each step with an icon and styling for its state
Step 3: The typing indicator shows animated dots with a short label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Which look the component shows. The parent passes one of these in the mode property.
export const MODE_STEPS = "steps";
export const MODE_TYPING = "typing";
export const DEFAULT_MODE = MODE_TYPING;

// The state a step can be in. The parent passes one of these on each step.
export const STEP_STATE_DONE = "done";
export const STEP_STATE_ACTIVE = "active";
export const STEP_STATE_PENDING = "pending";

// SLDS classes that style a step's label for each state.
export const STEP_LABEL_CLASSES = {
  done: "slds-text-color_default",
  active: "slds-text-title_bold",
  pending: "slds-text-color_weak"
};

// Text shown to the user.
export const LABELS = {
  workingHeading: "Working on it"
};
