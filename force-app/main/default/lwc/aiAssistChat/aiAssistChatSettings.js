/*
Component Name: aiAssistChat

=================================================================
=================================================================

Description: Every constant, label and name the AI Assist chat window uses, so the controller and the helper type none by hand.

Step 1: The values that mirror Apex (chat states, send statuses, channels, conversation status)
Step 2: The names the window uses between its parts (views, events, statuses, child methods, selectors)
Step 3: The numbers (sizes, timings, limits) and the patterns
Step 4: The label text the user reads

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Mirrors AIAssistApplicationConstants.CHAT_STATE_*.
export const CHAT_STATE = {
  READY: "READY",
  INACTIVE: "INACTIVE",
  MAINTENANCE: "MAINTENANCE",
  CHANNEL_DISABLED: "CHANNEL_DISABLED",
  NO_AGENT: "NO_AGENT",
  NO_ACCESS: "NO_ACCESS",
  TERMS: "TERMS"
};

// Mirrors AIAssistApplicationConstants.CHAT_BLOCKED_* (ChatContext.blockedState): why the user cannot send right now.
export const BLOCKED_STATE = {
  NO_POLICY: "NO_POLICY"
};

// Mirrors AIAssistApplicationConstants.USAGE_LIMIT_TYPE_* (ChatContext.usage.limitType): which usage limit the user has reached.
export const USAGE_LIMIT_TYPE = {
  OPEN: "OPEN"
};

// Mirrors AIAssistApplicationConstants.CHAT_SEND_STATUS_*. A refusal of any kind (a company rule, a limit, a paused chat) is ERROR with its Custom Label text in message.
export const SEND_STATUS = {
  SENT: "SENT",
  ERROR: "ERROR"
};

// Mirrors AIAssistApplicationConstants.CHANNEL_* (the AIChannel value set).
export const CHANNEL = {
  UTILITY_BAR: "Utility Bar",
  RECORD_PAGE: "Record Page Chat"
};

// Mirrors the AIFeedback__c rating values.
export const FEEDBACK_RATING = {
  HELPFUL: "Helpful",
  NOT_HELPFUL: "Not Helpful"
};

// Mirrors the AIConversation__c.Status__c values.
export const CONVERSATION_STATUS = {
  ACTIVE: "Active",
  CLOSED: "Closed"
};

// How aiChatScreenFlowModal reports a Screen Flow action ending (mirrors its FLOW_OUTCOME_* constants).
export const FLOW_OUTCOME = {
  FINISHED: "FINISHED",
  ERROR: "ERROR"
};

// The two views the window switches between.
export const VIEW = {
  CHAT: "chat",
  HISTORY: "history"
};

// The tabs of the history view.
export const HISTORY_FILTER = {
  RECORD: "record",
  ALL: "all",
  SHARED: "shared"
};

// How the message list is asked to scroll after the next render.
export const SCROLL_REQUEST = {
  BOTTOM: "bottom",
  SOFT: "soft",
  RESTORE: "restore"
};

// Who a message is from.
export const MESSAGE_SENDER = {
  USER: "user",
  AGENT: "agent"
};

// Whether a message is saved on the server yet.
export const MESSAGE_STATUS = {
  SENT: "sent",
  SENDING: "sending"
};

// The badge the header shows.
export const HEADER_BADGE = {
  OFF: "off",
  MAINTENANCE: "maintenance",
  DEBUG: "debug"
};

// The two ways of showing that a reply is being worked on.
export const WORKING_MODE = {
  STEPS: "steps",
  TYPING: "typing"
};

// The state of one step on the step card.
export const STEP_STATE = {
  ACTIVE: "active",
  PENDING: "pending"
};

// Status of a suggested action's card.
export const ACTION_STATUS = {
  IDLE: "idle",
  RUNNING: "running",
  DONE: "done",
  FAILED: "failed",
  DISMISSED: "dismissed"
};

// aiChatMessage's one bubbling "messageaction" event.
export const MESSAGE_ACTION = {
  RATE: "rate",
  SUBMIT_FEEDBACK: "submitfeedback",
  CLOSE_FEEDBACK: "closefeedback",
  REGENERATE: "regenerate",
  RUN_ACTION: "runaction",
  DECLINE_ACTION: "declineaction",
  DISMISS_ACTION: "dismissaction",
  LOAD_TRACE: "loadtrace",
  CLOSE_TRACE: "closetrace"
};

// The values of the header's menu.
export const MENU = {
  END: "end",
  EXPORT: "export"
};

// The icon shown beside each header menu item.
export const MENU_ICONS = {
  EXPORT: "utility:download",
  END: "utility:close"
};

// The public methods of the child components the window calls.
export const LIST_METHOD = {
  RESTORE_SCROLL: "restoreScrollPosition",
  SCROLL_TO_BOTTOM: "scrollToBottom",
  CAPTURE_SCROLL: "captureScrollPosition"
};

export const COMPOSER_METHOD = {
  CLEAR: "clear",
  SET_TEXT: "setText",
  FOCUS: "focus"
};

// How the window finds its children.
export const SELECTOR_MESSAGE_LIST = "c-ai-chat-message-list";
export const SELECTOR_COMPOSER = "c-ai-chat-composer";

// The page the utility bar follows: only a record page gives the window a record.
export const PAGE_TYPE_RECORD = "standard__recordPage";

// What the window listens for on the document.
export const EVENT_VISIBILITY_CHANGE = "visibilitychange";

// The start of the id given to a message or notice that only exists in the window until the server saves it.
export const ID_PREFIX_LOCAL = "local";
export const ID_PREFIX_NOTICE = "notice";

export const SCREEN_FLOW_MODAL_SIZE = "medium";
export const TOAST_VARIANT_ERROR = "error";

// The accent colour and height of the window.
export const DEFAULT_ACCENT = "#3040C4";
export const ACCENT_PATTERN = /^#[0-9a-fA-F]{3,8}$/;
export const DEFAULT_HEIGHT_PX = 680;
export const UTILITY_BAR_HEIGHT = "100%";

// The narrowest the chat window can render in - below this it asks for a wider region.
export const MIN_CHAT_WIDTH_PX = 320;

// A message that starts with a slash is a command.
export const COMMAND_PATTERN = /^\/[A-Za-z0-9_-]+/;
export const NEW_CONVERSATION_TITLE_LENGTH = 60;

// The window polls AIChatController.getConversationUpdate (no platform event) only while a reply is being worked on. The wait before each poll doubles from the first value up to the ceiling for that kind of wait.
export const POLL_FIRST_MS = 2000;
export const POLL_PROCESSING_CEILING_MS = 8000; // A reply is on its way, so keep looking often.
export const POLL_HELD_CEILING_MS = 60000; // The message is waiting for a free place, which can take a while, so ease off.
export const ELAPSED_TICK_MS = 1000;
export const PROCESSING_GRACE_SECONDS = 8; // Not being worked on and no reply for this long = the turn failed.

// Time maths and the way times and days are written.
export const MS_PER_SECOND = 1000;
export const MS_PER_DAY = 86400000;
export const SECONDS_PER_MINUTE = 60;
export const ELAPSED_SECONDS_LENGTH = 2;
export const ELAPSED_PAD_CHARACTER = "0";
export const DAY_SEPARATOR_JOIN = " · ";
export const TIME_FORMAT_OPTIONS = { hour: "2-digit", minute: "2-digit" };
export const DAY_FORMAT_OPTIONS = { weekday: "short", day: "numeric", month: "short" };

// Saving a transcript: a temporary link downloads it as a text file.
export const DOWNLOAD_LINK_TAG = "a";
export const DOWNLOAD_LINK_HIDDEN_DISPLAY = "none";
export const DOWNLOAD_DATA_PREFIX = "data:text/plain;charset=utf-8,";
export const TRANSCRIPT_DEFAULT_NAME = "AI-Conversation";
export const TRANSCRIPT_EXTENSION = ".txt";
export const TRANSCRIPT_NAME_UNSAFE_PATTERN = /[^A-Za-z0-9]+/g;
export const TRANSCRIPT_NAME_EDGE_PATTERN = /^-|-$/g;
export const TRANSCRIPT_NAME_SEPARATOR = "-";

// Turning an AI reply from markdown into safe HTML. The text is escaped first, then these rules add the tags, in this order.
export const LINE_BREAK_PATTERN = /\r\n/g;
export const NEW_LINE = "\n";
export const BULLET_PATTERN = /^\s*[-*•]\s+(.*)$/;
export const NUMBERED_PATTERN = /^\s*\d+[.)]\s+(.*)$/;
export const HEADING_PATTERN = /^\s*#{1,6}\s+(.*)$/;
export const LIST_TYPE = {
  BULLET: "ul",
  NUMBERED: "ol"
};

export const ESCAPE_RULES = [
  { pattern: /&/g, replacement: "&amp;" },
  { pattern: /</g, replacement: "&lt;" },
  { pattern: />/g, replacement: "&gt;" },
  { pattern: /"/g, replacement: "&quot;" },
  { pattern: /'/g, replacement: "&#39;" }
];

export const INLINE_MARKDOWN_RULES = [
  { pattern: /`([^`]+)`/g, replacement: "<code>$1</code>" },
  { pattern: /\*\*([^*]+)\*\*/g, replacement: "<strong>$1</strong>" },
  { pattern: /(^|[^*])\*([^*\s][^*]*)\*/g, replacement: "$1<em>$2</em>" },
  { pattern: /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, replacement: '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>' }
];

// The text the user reads. {0}, {1} are filled in by formatLabel.
export const LABELS = {
  appName: "AI Assist",
  disclaimer: "AI can make mistakes. Check before acting.",
  composerPlaceholder: "Ask about this record, or type / for commands",
  composerPlaceholderAllowanceUsed: "Your daily allowance is used up",
  composerPlaceholderNewPaused: "Starting a new conversation is paused",
  composerPlaceholderNoRecord: "Ask anything, or type / for commands",
  closeConversation: "End conversation",
  exportConversation: "Export conversation",
  actionFailed: "Didn’t work",
  workingLabel: "Working on it…",
  workingOnRecord: "Working on {0}…",
  heldLabel: "Waiting for a free place…",
  stepReading: "Reading records and thinking",
  stepReadingRecord: "Reading {0} and thinking",
  stepWriting: "Write the answer",
  stoppedWaiting: "Stopped waiting. The answer may still finish, and will be in this conversation when you open it again.",
  tryAgain: "Try again",
  someoneElse: "someone else",
  readOnlyLine: "You are viewing a conversation started by {0}. It is read-only.",
  backToMine: "Back to my chat",
  inactiveHeading: "AI Assist is turned off",
  inactiveBody: "Your organisation has paused AI Assist. Contact your Salesforce admin if you need it switched back on.",
  maintenanceHeading: "AI Assist is down for maintenance",
  maintenanceBody: "Your admin is making changes. Your conversations are saved and will be here when it’s back.",
  checkAgain: "Check again",
  contactAdmin: "Questions? Contact your Salesforce admin.",
  channelHeading: "AI Assist isn’t available here",
  channelBody: "Your admin hasn’t enabled AI Assist in this part of Salesforce for you.",
  noAccessHeading: "AI Assist isn’t set up for you",
  noAccessBody: "Your admin hasn’t given your account access to AI Assist yet. Ask them to switch it on for you.",
  noPolicyHeading: "You can read your conversations but not send messages",
  noPolicyBody: "Your admin hasn’t given you an AI Usage Policy yet. Ask them to assign you one.",
  noAgentHeading: "No AI agent is set up here",
  noAgentBody: "There’s no active AI agent for this page yet. Contact your Salesforce admin.",
  spaceHeading: "This chat needs more room",
  spaceBody: "Place AI Assist in a wider region of the page, or use it from the utility bar.",
  loadErrorHeading: "AI Assist couldn’t load",
  tokens: "tokens",
  debugFooter: "Debug mode is on for your user only.",
  endedHeading: "This conversation has ended.",
  resume: "Continue conversation",
  startNew: "Start a new conversation",
  newConversationStarted: "New conversation started",
  yesterday: "Yesterday",
  todayHeading: "Today",
  genericError: "Something went wrong."
};
