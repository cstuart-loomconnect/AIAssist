/*
Component Name: aiAgentWizardStepConversations

=================================================================
=================================================================

Description: The settings of the Conversations step of the AI Agent Wizard: picklist values, the choices, class names and label text.

Step 1: Name the picklist values this step writes
Step 2: List the choices the cards and the select offer
Step 3: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIAgent__c.ConversationLoadTrigger__c.
export const LOAD_CHAT_OPEN = "On Chat Window Open";
export const LOAD_PAGE_LOAD = "On Page Load";
export const LOAD_MANUAL = "Manual Only";

// Values that mirror AIAgent__c.ConversationVisibility__c.
export const VISIBILITY_PRIVATE = "Private";
export const VISIBILITY_GLOBAL = "Global";

// The keys of the error messages this step reads. They match the tab's field names.
export const FIELD_IDLE = "idleTimeoutMinutes";
export const FIELD_RETENTION = "conversationRetentionDays";

// The three ways a conversation can be loaded.
export const LOAD_CARDS = [
  { value: LOAD_CHAT_OPEN, title: "On chat window open", detail: "Loads the last conversation when the user opens the chat." },
  { value: LOAD_PAGE_LOAD, title: "On page load", detail: "Loads as soon as the record page opens. Faster, but costs a query on every page view." },
  { value: LOAD_MANUAL, title: "Manual only", detail: "Always starts fresh. Users pick old conversations from history." }
];

// The two choices of who can see conversations.
export const VISIBILITY_CHOICES = [
  { value: VISIBILITY_PRIVATE, label: "Private: only the user who started it" },
  { value: VISIBILITY_GLOBAL, label: "Global: anyone with the agent" }
];

// Values that mirror AIAgent__c.RetentionTrigger__c.
export const RETENTION_CHOICES = [
  { value: "Conversation Created Date", label: "Conversation created date" },
  { value: "Conversation Closed Date", label: "Conversation closed date" },
  { value: "Last Message Date", label: "Last message date" }
];

// The classes of a card, of a segment and of a form element, with and without a problem.
export const CARD_CLASS = "aiawco-card";
export const CARD_SELECTED_CLASS = "aiawco-card aiawco-card_selected";
export const SEG_CLASS = "aiawco-seg-button";
export const SEG_SELECTED_CLASS = "aiawco-seg-button aiawco-seg-button_selected";
export const FORM_ELEMENT_CLASS = "slds-form-element aiawco-field";
export const FORM_ELEMENT_ERROR_CLASS = "slds-form-element slds-has-error aiawco-field";
export const TOGGLE_ROW_CLASS = "aiawco-toggle-row";
export const TOGGLE_ROW_DISABLED_CLASS = "aiawco-toggle-row aiawco-toggle-row_disabled";

// The text of a value that is empty, and the word used when the agent has no object.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  whenLoaded: "When is a conversation loaded?",
  resumeTitle: "Let users resume a conversation",
  resumeOn: "Carry on where they left off instead of starting again.",
  resumeDisabled: "Not used with Manual only: nothing loads automatically.",
  singleTitle: "One active conversation per record",
  singleOnBefore: "Keeps each ",
  singleOnAfter: "'s history in one thread.",
  singleOnFallback: "record",
  singleOff: "Off: each question can start its own thread.",
  whoSees: "Who can see conversations?",
  visibilityPrivateHelp: "Private suits client conversations. Global suits shared queues where colleagues pick up each other's work.",
  globalWarning: "Global conversations can show one user's chat, including record data they could see, to another user with this agent. Only choose Global for agents whose users share the same access.",
  idle: "Close after idle (minutes)",
  idleHelp: "Closed by AIConversationIdleTimeoutBatch.",
  retention: "Keep conversations for (days)",
  retentionHelp: "Then deleted with their PII mappings.",
  retentionFrom: "Count retention from",
  retentionFromHelp: "Created, closed or last message date."
};
