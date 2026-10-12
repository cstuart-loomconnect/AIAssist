/*
Component Name: aiChatComposer

=================================================================
=================================================================

Description: The message box at the bottom of the chat: typing, the slash-command menu, Send and Stop, and the footnote with today's token usage.

Step 1: The parent (aiAssistChat) passes in the commands, the usage meters and whether the box is disabled or working
Step 2: The user types; a command being typed opens the slash-command menu
Step 3: Enter sends the message (Shift+Enter adds a line); while the menu is open the arrow keys move and Enter or Tab picks
Step 4: The footnote shows how much of today's token allowance is used, and the parent hears about every send, stop and menu change

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The longest message the box accepts, in characters.
export const DEFAULT_MAX_LENGTH = 32000;

// The keys the box reacts to.
export const KEY = { ARROW_DOWN: "ArrowDown", ARROW_UP: "ArrowUp", ENTER: "Enter", TAB: "Tab", ESCAPE: "Escape" };

// The direction a key moves the highlighted command.
export const STEP_DOWN = 1;
export const STEP_UP = -1;

// What the template reads for an open or selected state.
export const ARIA_TRUE = "true";
export const ARIA_FALSE = "false";

// The classes the template needs, which change with the state of the box.
export const BOX_CLASS = "box";
export const BOX_CLASS_DISABLED = "box box_disabled";
export const BOX_CLASS_FOCUSED = "box box_focused";
export const SLASH_CLASS = "slash aia-mono";
export const SLASH_CLASS_ACTIVE = "slash slash_active aia-mono";
export const SEND_CLASS = "send";
export const SEND_CLASS_DISABLED = "send send_disabled";
export const OPTION_CLASS = "option";
export const OPTION_CLASS_ACTIVE = "option option_active";
export const SCOPE_CLASS = "scope";
export const SCOPE_CLASS_ACTIVE = "scope scope_active";

// The text box the component finds in its own template.
export const INPUT_SELECTOR = "textarea";

// The slash that starts a command, and the pattern for a command still being typed, such as "/ri".
export const COMMAND_PREFIX = "/";
export const TYPING_COMMAND_PATTERN = /^\/[A-Za-z0-9_-]*$/;

// The patterns that pick the command word out of what was typed.
export const LEADING_SLASH_PATTERN = /^\//;
export const WHITESPACE_PATTERN = /\s/;

// How a command in the menu ranks: a match at the start of the name first.
export const RANK_PREFIX = 0;
export const RANK_INSIDE = 1;

// The start of the id of each row in the command menu.
export const COMMAND_OPTION_ID_PREFIX = "command-option-";

// Mirrors AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS.
export const LIMIT_TYPE_TOKENS = "TOKENS";

// The token readout: when it turns amber and red, how long its ring is and how many decimals its dash has.
export const TOKEN_WARN_PERCENT = 80;
export const TOKEN_FULL_PERCENT = 100;
export const TOKEN_RING_LENGTH = 56.5;
export const TOKEN_RING_DECIMALS = 1;

// The colour of the token readout, from how full the allowance is, and the class that carries it.
export const TOKEN_TONE_OK = "ok";
export const TOKEN_TONE_WARN = "warn";
export const TOKEN_TONE_BAD = "bad";
export const TOKEN_CLASS_PREFIX = "token token_";

// The names of the events sent to the parent.
export const EVENT_SEND = "send";
export const EVENT_STOP = "stop";
export const EVENT_MENU_TOGGLE = "menutoggle";

// Text shown to the user. tokenUsed follows the percentage, such as "50% of today's allowance used".
export const LABELS = {
  tokenUsed: "% of today’s allowance used",
  tokenTitle: "Your token usage today. Open the ... menu for all your limits.",
  disclaimer: "AI can make mistakes. Check before acting.",
  composerPlaceholder: "Ask about this record, or type / for commands",
  composerPlaceholderWorking: "Wait for the answer, or stop it",
  messageLabel: "Message",
  send: "Send",
  stop: "Stop",
  commands: "Commands",
  commandsHint: "↑↓ to move · Enter to use",
  noCommands: "No commands match"
};
