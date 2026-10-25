/*
Component Name: aiChatFeedbackPanel

=================================================================
=================================================================

Description: Settings for aiChatFeedbackPanel: the reason choices, the label text and the event and attribute values.

Step 1: Hold the reasons the user can pick from
Step 2: Hold the event names sent to the parent
Step 3: Hold the aria-pressed values and the label text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Reasons the user can pick after a thumbs down. The first one is selected by default.
export const FEEDBACK_REASONS = ["Not accurate", "Missing info", "Wrong record", "Too long", "Other"];

// Events sent to the parent
export const EVENT_SKIP = "skip"; // No detail
export const EVENT_SUBMIT = "submit"; // detail: { reason, comment }

// aria-pressed values for the reason buttons
export const ARIA_PRESSED_TRUE = "true";
export const ARIA_PRESSED_FALSE = "false";

// Label text shown in the template
export const LABELS = {
  feedbackHeading: "What went wrong?",
  feedbackMore: "Tell us more (optional)",
  feedbackSkip: "Skip",
  feedbackSend: "Send feedback",
  close: "Close"
};
