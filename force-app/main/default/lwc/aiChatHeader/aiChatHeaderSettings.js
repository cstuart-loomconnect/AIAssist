/*
Component Name: aiChatHeader

=================================================================
=================================================================

Description: The chat window's top bar: logo, title, agent picker and the New and More controls.

Step 1: The parent (aiAssistChat) passes in the title, the agents, the badge and the user's usage meters
Step 2: The header shows the logo, the title and, when there is more than one agent, a picker
Step 3: The New, End and More buttons follow; the More menu opens with the usage limits, then History and Export
Step 4: Every click is reported to the parent as an event; the header changes nothing itself

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Which badge sits beside the title. Mirrors the header badge values aiAssistChat passes in.
export const BADGE = { DEBUG: "debug", MAINTENANCE: "maintenance", OFF: "off" };

// The classes of each badge.
export const BADGE_CLASSES = { debug: "badge badge_debug aia-mono", maintenance: "badge badge_maintenance", off: "badge badge_off" };
export const BADGE_CLASS_DEFAULT = "badge";

// The colour of the logo mark: normal, and dimmed when the window is off.
export const LOGO_STROKE = { MUTED: "#6B6F7C", NORMAL: "#FFFFFF" };

// The classes of the logo and the title, normal and dimmed when the window is off.
export const LOGO_CLASS = "aia-logo";
export const LOGO_CLASS_MUTED = "aia-logo aia-logo_muted";
export const TITLE_CLASS = "title";
export const TITLE_CLASS_MUTED = "title title_muted";

// Text shown to the user.
export const LABELS = {
  appName: "AI Assist",
  newShort: "New",
  endShort: "End",
  historyShort: "History",
  usageShort: "Usage",
  usageHint: "See how much you have used today",
  usageHeading: "Your AI usage today",
  usageBack: "Back to menu",
  historyHint: "Browse your past conversations",
  exportHint: "Save the transcript as a text file",
  endConfirmHeading: "End this conversation?",
  endConfirmBody: "You will not be able to send more messages in it. Your history keeps it, and you can still export it.",
  endKeep: "Keep it open",
  endConfirm: "End conversation",
  endConversation: "End conversation",
  newConversation: "New conversation",
  newConversationDisabled: "New conversation (disabled by admin)",
  history: "Conversation history",
  moreOptions: "More options",
  switchAgent: "Switch AI agent",
  inactiveBadge: "Off",
  maintenanceBadge: "Maintenance",
  debugBadge: "DEBUG"
};


// The agent picker shows only when there are at least this many agents to switch between.
export const MIN_AGENTS_TO_SWITCH = 2;

// The agent menu: the value the template reads for an open or selected state, the key that closes it and the selector of the picker.
export const ARIA_TRUE = "true";
export const ARIA_FALSE = "false";
export const KEY_ESCAPE = "Escape";
export const PICKER_SELECTOR = ".agent-picker";
export const USAGE_BACK_SELECTOR = ".usage-back";
export const MENU_ROW_SELECTOR = ".menu-row";

// The values of the menu items aiAssistChat passes in. Mirrors MENU in aiAssistChatSettings.
export const MENU_VALUE_END = "end";
export const MENU_VALUE_EXPORT = "export";

// The keys of the rows in the More menu. History is added by the header; the others come from the parent's menu items.
export const ROW_KEY_HISTORY = "history";
export const ROW_KEY_USAGE = "usage";

// The classes of the square More button when its menu is closed and open.
export const BUTTON_CLASS_MORE = "aia-btn aia-btn_neutral aia-btn_square";
export const BUTTON_CLASS_MORE_OPEN = "aia-btn aia-btn_neutral aia-btn_square aia-btn_open";

// The names of the events sent to the parent.
export const EVENT_AGENT_SELECT = "agentselect";
export const EVENT_NEW_CONVERSATION = "newconversation";
export const EVENT_OPEN_HISTORY = "openhistory";
export const EVENT_MENU_SELECT = "menuselect";
