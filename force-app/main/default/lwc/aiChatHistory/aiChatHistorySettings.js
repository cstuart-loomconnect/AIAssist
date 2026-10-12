/*
Component Name: aiChatHistory

=================================================================
=================================================================

Description: Lists the user's past conversations, grouped by day, so they can search them, filter them and open one.

Step 1: The parent (aiAssistChat) loads the conversations and passes them in with the filter that is selected
Step 2: The component groups them under Today, Yesterday, Earlier this week and Older
Step 3: The user can search by title or agent here, and switch the filter, which the parent reloads
Step 4: Opening a conversation, going back and starting a new one are reported to the parent as events

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Which conversations the list shows. Mirrors the filters aiAssistChat loads (HISTORY_FILTER there).
export const HISTORY_FILTER_RECORD = "record";
export const HISTORY_FILTER_ALL = "all";
export const HISTORY_FILTER_SHARED = "shared";

// Conversation statuses the Apex summary carries (AIConversation__c.Status__c).
export const STATUS_ACTIVE = "Active";
export const STATUS_ARCHIVED = "Archived";

// Close reasons the Apex summary carries (AIConversation__c.CloseReason__c).
export const CLOSE_REASON_IDLE_TIMEOUT = "Idle Timeout";
export const CLOSE_REASON_MESSAGE_LIMIT = "Message Limit Reached";
export const CLOSE_REASON_TOKEN_LIMIT = "Token Limit Reached";

// The classes of a status badge: any status, and an Active conversation.
export const STATUS_CLASS = "aia-status";
export const STATUS_CLASS_ACTIVE = "aia-status aia-status_active";

// The classes of a conversation row and its title, normal and for the conversation that is open.
export const ROW_CLASS = "conversation";
export const ROW_CLASS_CURRENT = "conversation conversation_current";
export const TITLE_CLASS = "conversation-title slds-truncate";
export const TITLE_CLASS_CURRENT = "conversation-title conversation-title_current slds-truncate";

// Dates: a conversation this many days old or more drops out of "Earlier this week", and how long a day is.
export const DAYS_IN_WEEK = 7;
export const MS_PER_DAY = 86400000;

// How dates are written, in the user's own locale: the time today, the day this week and the day and month before that.
export const TIME_FORMAT_OPTIONS = { hour: "2-digit", minute: "2-digit" };
export const WEEKDAY_FORMAT_OPTIONS = { weekday: "short" };
export const DAY_MONTH_FORMAT_OPTIONS = { day: "numeric", month: "short" };

// How many days ago the day groups start.
export const DAYS_AGO_TODAY = 0;
export const DAYS_AGO_YESTERDAY = 1;

// The characters Salesforce Ids are compared on: an Id arrives as 15 or 18 characters.
export const ID_COMPARE_LENGTH = 15;

// The text in a conversation's small line, and what is replaced in it. {0} is replaced with the number of messages.
export const COUNT_PLACEHOLDER = "{0}";
export const META_SEPARATOR = " · ";

// Whether a filter button is pressed, as a screen reader expects it.
export const ARIA_TRUE = "true";
export const ARIA_FALSE = "false";

// Text shown to the user.
export const LABELS = {
  appName: "AI Assist",
  back: "Back to chat",
  conversations: "Conversations",
  newShort: "New",
  searchConversations: "Search conversations",
  filterConversations: "Filter conversations",
  loadingConversations: "Loading conversations",
  thisRecord: "This record",
  sharedWithMe: "Shared with me",
  noSharedConversations: "No shared conversations.",
  allRecords: "All records",
  retentionNote: "Conversations are deleted after the retention period your admin sets.",
  noConversations: "No conversations yet.",
  noSearchResults: "No conversations match your search.",
  earlierThisWeek: "Earlier this week",
  yesterday: "Yesterday",
  todayHeading: "Today",
  older: "Older",
  messagesCount: "{0} messages",
  statusActive: "Active",
  statusArchived: "Archived",
  statusTimedOut: "Timed out",
  statusLimitReached: "Limit reached",
  statusClosed: "Closed"
};

// The names of the events sent to the parent.
export const EVENT_FILTER_CHANGE = "filterchange";
export const EVENT_OPEN = "open";
export const EVENT_BACK = "back";
export const EVENT_NEW_CONVERSATION = "newconversation";
