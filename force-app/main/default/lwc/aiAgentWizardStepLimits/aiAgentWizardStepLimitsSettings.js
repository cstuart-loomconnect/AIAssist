/*
Component Name: aiAgentWizardStepLimits

=================================================================
=================================================================

Description: The settings of the Limits step of the AI Agent Wizard: token counting choices, the numbers behind the estimate, finding codes, class names and label text.

Step 1: Name the token counting choices and the finding codes
Step 2: Hold the numbers the estimate is worked out from
Step 3: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The keys of the error messages this step reads. They match the tab's field names.
export const FIELD_MESSAGES = "maxMessagesPerConversation";
export const FIELD_TOKENS = "maxTokensPerConversation";
export const FIELD_ROUNDS = "maxToolCallingIterations";

// Values that mirror the finding codes AIAgentWizardController gives to checkDraft.
export const CODE_TOKENS_OVER_POLICY = "TokensOverPolicy";
export const CODE_ROUNDS_OVER_CAP = "ToolRoundsOverCap";

// The three ways tokens can be counted. The values mirror AIAgent__c.TokenTrackingMethod__c.
export const TRACKING_CARDS = [
  { value: "Estimate Token Usage", title: "Estimate", detail: "Counts characters before sending. Cheap, slightly rough." },
  { value: "Track Token Usage", title: "Track actual usage", detail: "Uses the token counts the provider returns. Accurate, counted after the reply." },
  { value: "Pre-Request Usage Check", title: "Check before each request", detail: "Blocks a message that would go over the limit. Strictest." }
];

// The numbers the estimate is worked out from.
export const TYPICAL_MESSAGES = 8;
export const TOKENS_PER_MESSAGE = 1500;
export const CONVERSATIONS_PER_USER_PER_DAY = 4;
export const WORDS_PER_TOKEN = 0.75;
export const MILLION = 1000000;

// The classes of a card, of a form element and of the pills.
export const CARD_CLASS = "aiawli-card";
export const CARD_SELECTED_CLASS = "aiawli-card aiawli-card_selected";
export const FORM_ELEMENT_CLASS = "slds-form-element aiawli-field";
export const FORM_ELEMENT_ERROR_CLASS = "slds-form-element slds-has-error aiawli-field";
export const PILL_FITS_CLASS = "aiawli-pill aiawli-pill_success";
export const PILL_OVER_CLASS = "aiawli-pill aiawli-pill_warning";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  intro: "Limits per conversation. Usage policies still apply on top of these, so the stricter one wins.",
  messages: "Max messages per conversation",
  messagesHelp: "The user starts a new conversation after this.",
  tokens: "Max tokens per conversation",
  tokensHelpBefore: "Roughly ",
  tokensHelpAfter: " words in and out.",
  rounds: "Max tool-calling rounds per message",
  roundsHelpBefore: "Org cap is ",
  roundsHelpAfter: " (AI Assist Settings).",
  counting: "How is token usage counted?",
  estimated: "Estimated use with these limits",
  typical: "Typical conversation",
  typicalMessages: " messages · ",
  typicalTokens: " tokens",
  users: "Users",
  usersFromAccess: " (from Access step)",
  usersUnknown: "Not counted yet",
  dailyTotalBefore: "Daily total at ",
  dailyTotalAfter: " conversations each",
  tokensUnit: " tokens",
  usagePolicy: "Usage policy",
  noPolicy: "No usage policy applies.",
  policyNoLimit: " · no daily token limit",
  policyLimitBefore: " · ",
  policyLimitAfter: " tokens per user per day",
  fits: "Fits",
  over: "Over",
  warningsNote: "These won't block saving, but the agent will stop sooner than these numbers suggest."
};
