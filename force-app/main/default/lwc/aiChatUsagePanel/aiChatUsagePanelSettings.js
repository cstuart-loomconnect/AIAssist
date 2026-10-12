/*
Component Name: aiChatUsagePanel

=================================================================
=================================================================

Description: Shows the user how much of each usage limit they have used today, in a panel that opens from the chat header.

Step 1: The parent (aiAssistChat) passes in a meter for each of the three usage limits
Step 2: The component shows a row for each, with the amount used and when it resets
Step 3: A limit the policy sets also gets a bar, amber when nearly used up and red when used up
Step 4: The close button, or the Escape key, tells the parent to close the panel

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Mirrors AIAssistApplicationConstants.USAGE_LIMIT_TYPE_*.
export const LIMIT_TYPE_TOKENS = "TOKENS";
export const LIMIT_TYPE_CONVERSATIONS = "CONVERSATIONS";
export const LIMIT_TYPE_OPEN = "OPEN";

// Text shown to the user for each limit. usedOnly is shown when the policy sets no limit, and the unit follows the amounts (blank for a count of conversations).
export const LIMIT_LABELS = {
  [LIMIT_TYPE_TOKENS]: { name: "Today’s allowance", unit: "tokens", usedOnly: "{0} tokens used", help: "Resets at midnight", done: "You have used it all until midnight" },
  [LIMIT_TYPE_CONVERSATIONS]: { name: "Conversations started today", unit: "", usedOnly: "{0} started", help: "Resets at midnight", done: "You cannot start another until midnight" },
  [LIMIT_TYPE_OPEN]: { name: "Conversations open now", unit: "", usedOnly: "{0} open", help: "End one to free a place", helpRecent: "Counts conversations used in the last {0} minutes. End one to free a place.", done: "End one to start another" }
};

// The text around the rows. {0}, {1} and {2} are replaced, in order, with the amount used, the limit and the unit.
export const LABELS = {
  heading: "Your AI usage today",
  close: "Close",
  footer: "Set by your usage policy",
  usageOf: "{0} of {1}",
  usageOfUnit: "{0} of {1} {2}",
  leftWithHelp: "{0} left. {1}",
  leftUnit: "{0} {1}",
  noLimit: "No limit set for you",
  reached: "Reached",
  nearlyThere: "Nearly there"
};

// How full a limit is, as a percentage, when its row turns amber and red.
export const WARN_PERCENT = 80;
export const FULL_PERCENT = 100;

// The colour of a row, from how full its limit is.
export const TONE_OK = "ok";
export const TONE_WARN = "warn";
export const TONE_BAD = "bad";

// The class on a row, and the style that sets the width of its bar.
export const ROW_CLASS_PREFIX = "row row_";
export const BAR_STYLE_PREFIX = "width:";

// The braces around a placeholder in a label, such as {0}.
export const PLACEHOLDER_START = "{";
export const PLACEHOLDER_END = "}";

// The number format for the amounts, in the user's own locale.
export const NUMBER_LOCALE = undefined;

// The key that closes the panel, the selector of the button that takes focus, and the name of the event sent to the parent.
export const KEY_ESCAPE = "Escape";
export const CLOSE_BUTTON_SELECTOR = ".close";
export const EVENT_CLOSE = "close";

// The classes of the panel: with its own box, or plain when it sits inside a menu.
export const PANEL_CLASS = "panel slds-grid slds-grid_vertical";
export const PANEL_CLASS_EMBEDDED = "panel panel_embedded slds-grid slds-grid_vertical";
