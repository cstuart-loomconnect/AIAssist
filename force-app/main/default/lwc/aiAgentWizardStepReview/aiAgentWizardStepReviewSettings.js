/*
Component Name: aiAgentWizardStepReview

=================================================================
=================================================================

Description: The settings of the Review step of the AI Agent Wizard: step numbers, picklist values, class names and label text.

Step 1: Name the steps the Edit links jump to, and the picklist values the summary writes out
Step 2: Hold the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The steps the Edit links and the Go to buttons jump to. The numbers match the tab's steps.
export const STEP_BASICS = 1;
export const STEP_MODEL = 2;
export const STEP_SKILLS = 3;
export const STEP_DATA_SOURCES = 4;
export const STEP_ACTIONS = 5;
export const STEP_CONVERSATIONS = 6;
export const STEP_LIMITS = 7;
export const STEP_ACCESS = 8;

// The names of the steps, for the Go to buttons.
export const STEP_LABELS = {
  1: "Basics",
  2: "Model",
  3: "Skills",
  4: "Data sources",
  5: "Workflow actions",
  6: "Conversations",
  7: "Limits",
  8: "Access"
};

// Values that mirror AIAgentWizardDataStructure.Finding.severity.
export const SEVERITY_BLOCKER = "Blocker";

// Values that mirror the AIAgent__c picklists, with the words the summary uses.
export const LOAD_LABELS = { "On Chat Window Open": "On chat window open", "On Page Load": "On page load", "Manual Only": "Manual only" };
export const VISIBILITY_LABELS = { Private: "Private", Global: "Global" };
export const RETENTION_LABELS = { "Conversation Created Date": "creation", "Conversation Closed Date": "close", "Last Message Date": "last message" };
export const TRACKING_LABELS = { "Estimate Token Usage": "Estimate", "Track Token Usage": "Track actual usage", "Pre-Request Usage Check": "Check before each request" };
export const ACCESS_ALL = "All AI Assist Users";
export const ACCESS_LABELS = { "All AI Assist Users": "All AI Assist users", "Assigned Users Only": "Assigned users only" };
export const ASSIGNEE_PERMISSION_SET = "Permission Set";

// The most names a summary row lists before it stops.
export const MAX_NAMES = 3;

// Values that mirror AIWorkflowAction__c.ActionType__c.
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";

// The classes of the pills, the severity pills and the try it result.
export const PILL_CLASS = "aiawre-pill";
export const PILL_SUCCESS_CLASS = "aiawre-pill aiawre-pill_success";
export const PILL_DANGER_CLASS = "aiawre-pill aiawre-pill_danger";
export const PILL_WARNING_CLASS = "aiawre-pill aiawre-pill_warning";

// The text between the parts of a list.
export const LIST_SEPARATOR = ", ";

// The number of milliseconds in a second, for the time a trial took.
export const MILLISECONDS_PER_SECOND = 1000;

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  readyBold: "Ready to activate. ",
  readyAllPassed: "All checks passed.",
  readyWarningsOne: "1 warning below.",
  readyWarningsMany: " warnings below.",
  blockedBold: "Can't activate yet. ",
  blockedOne: "1 thing to fix.",
  blockedMany: " things to fix.",
  blockedSaveDraft: "You can still save as a draft.",
  blocker: "Blocker",
  warning: "Warning",
  goTo: "Go to ",
  edit: "Edit",
  basics: "Basics",
  model: "Model",
  skills: "Skills",
  dataSources: "Data sources",
  actions: "Workflow actions",
  conversations: "Conversations",
  limits: "Limits",
  access: "Access",
  name: "Name",
  pages: "Pages",
  promptTemplate: "Prompt template",
  defaultTemplate: "Default",
  noneChosen: "None chosen",
  configuration: "Configuration",
  connection: "Connection",
  connected: "Connected",
  failed: "Failed",
  notTested: "Not tested",
  selected: "Selected",
  none: "None",
  readOnly: "Read-only agent",
  writeActions: "Write actions",
  allAskFirst: ", all ask first",
  someAskFirst: " ask first",
  more: " more",
  load: "Load",
  visibility: "Visibility",
  retention: "Retention",
  retentionDays: " days from ",
  perConversation: "Per conversation",
  messages: " messages",
  tokens: " tokens",
  toolRounds: "Tool rounds",
  counting: "Counting",
  mode: "Mode",
  users: "Users",
  usersViaBefore: " via ",
  usersViaPermissionSet: " permission set",
  usersViaPermissionSets: " permission sets",
  usersAllBefore: "All ",
  usersAllAfter: " AI Assist users",
  tryTitle: "Try it before activating",
  tryNeedsModel: "Testing needs a model configuration.",
  tryNote: "The trial uses the model, prompt template and persona only. Data sources and workflow actions are not used.",
  message: "Message",
  messagePlaceholder: "Ask the agent something",
  onRecord: "On record (optional)",
  send: "Send",
  sending: "Sending",
  trialFailed: "The trial message failed. ",
  seconds: "s",
  tokensUnit: " tokens"
};
