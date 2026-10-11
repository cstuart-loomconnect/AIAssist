/*
Component Name: aiChatUsageBanner

=================================================================
=================================================================

Description: Tells the user they have reached a usage limit, how far they are, and what it stops, as soon as the window opens.

Step 1: The parent (aiAssistChat) passes in the usage limit the user has reached (AIChatDataStructure.UsageLimitState)
Step 2: The component shows the limit, what it stops and a meter of how much has been used
Step 3: For the open conversations limit it offers a button to open the history, so the user can end one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Mirrors AIAssistApplicationConstants.USAGE_LIMIT_TYPE_*.
export const LIMIT_TYPE = {
  TOKENS: "TOKENS",
  CONVERSATIONS: "CONVERSATIONS",
  OPEN: "OPEN"
};

// Text shown to the user, by limit.
export const LIMIT_LABELS = {
  [LIMIT_TYPE.TOKENS]: {
    title: "You have used today’s AI allowance",
    unit: "tokens",
    reset: "Resets at midnight"
  },
  [LIMIT_TYPE.CONVERSATIONS]: {
    title: "You have started all your conversations for today",
    unit: "conversations today",
    reset: "Resets at midnight"
  },
  [LIMIT_TYPE.OPEN]: {
    title: "You have the maximum number of conversations open",
    unit: "conversations open",
    reset: "End one to start another"
  }
};

// The line under the title, by what the limit stops.
export const LABELS = {
  subNotifyOnly:
    "You are over the limit set for you, but you can keep chatting.",
  subBlocksMessages:
    "You cannot send messages until your allowance resets. You can still read your conversations.",
  subBlocksNewConversations:
    "You can carry on in your current conversation. New conversations are paused.",
  usageOf: "{0} of {1} {2}",
  openHistory: "Open history"
};

// The text inside usageOf that is replaced, in order, with the amount used, the limit and the unit.
export const PLACEHOLDERS = ["{0}", "{1}", "{2}"];

// The most the meter can show.
export const MAX_PERCENT = 100;

// The number format for the amount used and the limit, in the user's own locale.
export const NUMBER_LOCALE = undefined;

// The name of the event sent to the parent.
export const EVENT_OPEN_HISTORY = "openhistory";
