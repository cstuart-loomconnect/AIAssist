/*
Component Name: aiAgentWizard

=================================================================
=================================================================

Description: The settings of the AI Agent Wizard tab: screens, steps, picklist values, finding codes, starting values, class names and label text.

Step 1: Name the screens (the list of agents, the start screen, the steps and the done screen) and the steps
Step 2: Name the picklist values and finding codes that mirror Apex
Step 3: Hold the draft a blank agent starts from
Step 4: Hold the class names, timings and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The screens of the tab.
export const SCREEN_LIST = "list";
export const SCREEN_START = "start";
export const SCREEN_WIZARD = "wizard";
export const SCREEN_DONE = "done";

// The steps, in order. The number is the step number the admin sees, and the Finding.step the Apex checks use.
export const STEP_BASICS = 1;
export const STEP_MODEL = 2;
export const STEP_DATA_SOURCES = 3;
export const STEP_ACTIONS = 4;
export const STEP_CONVERSATIONS = 5;
export const STEP_LIMITS = 6;
export const STEP_ACCESS = 7;
export const STEP_REVIEW = 8;
export const FIRST_CHECKED_STEP = STEP_DATA_SOURCES;
export const STEP_NAMES = [
  { number: STEP_BASICS, label: "Basics", title: "Basics", detail: "Name and purpose" },
  { number: STEP_MODEL, label: "Model", title: "Model", detail: "Which AI model" },
  { number: STEP_DATA_SOURCES, label: "Data sources", title: "Data sources", detail: "What it can read" },
  { number: STEP_ACTIONS, label: "Workflow actions", title: "Workflow actions", detail: "What it can change" },
  { number: STEP_CONVERSATIONS, label: "Conversations", title: "Conversations", detail: "History and retention" },
  { number: STEP_LIMITS, label: "Limits", title: "Limits", detail: "Usage caps" },
  { number: STEP_ACCESS, label: "Access", title: "Access", detail: "Who can use it" },
  { number: STEP_REVIEW, label: "Review", title: "Review and activate", detail: "Test and activate" }
];

// The steps that have fields the admin must fix before going on.
export const STEPS_WITH_REQUIRED_FIELDS = [STEP_BASICS, STEP_CONVERSATIONS, STEP_LIMITS];

// Values that mirror Apex: AIAgentWizardDataStructure.Finding.severity.
export const SEVERITY_BLOCKER = "Blocker";

// Values that mirror AIAgent__c picklists.
export const LOAD_TRIGGER_CHAT_OPEN = "On Chat Window Open";
export const RETENTION_TRIGGER_CLOSED = "Conversation Closed Date";
export const VISIBILITY_PRIVATE = "Private";
export const TOKEN_TRACKING_TRACK = "Track Token Usage";
export const ACCESS_MODE_ASSIGNED = "Assigned Users Only";

// The draft a blank agent starts from. The numbers are the AIAgent__c field defaults.
export const BLANK_DRAFT = {
  agentId: null,
  agentName: "",
  developerName: "",
  description: "",
  persona: "",
  greeting: "",
  objectApiNames: [],
  promptTemplateId: null,
  modelConfigurationId: null,
  dataSourceIds: [],
  workflowActionIds: [],
  conversationLoadTrigger: LOAD_TRIGGER_CHAT_OPEN,
  allowConversationResume: true,
  singleActiveConversationPerRecord: true,
  conversationVisibility: VISIBILITY_PRIVATE,
  idleTimeoutMinutes: 30,
  conversationRetentionDays: 90,
  retentionTrigger: RETENTION_TRIGGER_CLOSED,
  maxMessagesPerConversation: 50,
  maxTokensPerConversation: 50000,
  maxToolCallingIterations: 5,
  tokenTrackingMethod: TOKEN_TRACKING_TRACK,
  accessMode: ACCESS_MODE_ASSIGNED,
  assignments: [],
  isActive: false,
  lastModifiedDate: null,
  userCount: null
};

// The names of the fields the local checks report on. They are the keys the steps look up.
export const FIELD_AGENT_NAME = "agentName";
export const FIELD_DEVELOPER_NAME = "developerName";
export const FIELD_OBJECTS = "objectApiNames";
export const FIELD_IDLE = "idleTimeoutMinutes";
export const FIELD_RETENTION = "conversationRetentionDays";
export const FIELD_MESSAGES = "maxMessagesPerConversation";
export const FIELD_TOKENS = "maxTokensPerConversation";
export const FIELD_ROUNDS = "maxToolCallingIterations";

// The API name must be letters, numbers and underscores only, starting with a letter. The same rule as WIZARD_DEVELOPER_NAME_PATTERN in Apex.
export const DEVELOPER_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;

// The classes of the steps in the stepper.
export const STEP_CLASS = "aiaw-step";
export const STEP_CURRENT_CLASS = "aiaw-step aiaw-step_current";
export const STEP_DONE_CLASS = "aiaw-step aiaw-step_done";
export const STEP_ERROR_CLASS = "aiaw-step aiaw-step_error";
export const STEP_CURRENT_ERROR_CLASS = "aiaw-step aiaw-step_current aiaw-step_error";
export const MARKER_DONE = "✓";
export const MARKER_ERROR = "!";

// The toast variants and the confirm dialog style.
export const TOAST_VARIANT_ERROR = "error";
export const CONFIRM_VARIANT = "default";

// The wait after the last change before the draft is checked again, in milliseconds.
export const CHECK_DELAY_MILLISECONDS = 600;

// The locale the last changed date is shown in.
export const DATE_LOCALE = "en-GB";

// The API name of the AI Settings tab, which the Open Settings button of a finding goes to.
export const SETTINGS_TAB_API_NAME = "AIAssistSettingsTab";

// The state key of the tab URL that names the agent to change.
export const AGENT_ID_STATE_KEY = "c__agentId";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  title: "AI Agent Wizard",
  subtitleNew: "Step-by-step setup for a new AI agent",
  subtitleEditing: "Editing ",
  statusNew: "Draft · not saved until you finish",
  statusActive: "Active · last changed ",
  statusDraft: "Draft · last changed ",
  loading: "Loading the wizard",
  cancel: "Cancel",
  backToList: "Back to all agents",
  back: "Back",
  next: "Next",
  nextNoModel: "Next (no model)",
  nextReadOnly: "Continue read-only",
  saveChanges: "Save changes",
  saveDraft: "Save as draft",
  activate: "Activate agent",
  stepsAria: "Steps",
  editingLiveBold: "Editing a live agent. ",
  editingLiveAfter: " users have it. Changes apply when you click Save changes on any step; conversations already open keep their old settings until they close.",
  discardTitle: "Discard this agent?",
  discardMessage: "What you have entered will be lost.",
  fallbackError: "Something went wrong. Please try again.",
  enterName: "Enter a name.",
  enterApiName: "Enter an API name.",
  apiNameFormat: "Use letters, numbers and underscores only, starting with a letter.",
  apiNameTakenBefore: "An agent called ",
  apiNameTakenAfter: " already exists. Choose another API name.",
  chooseObject: "Choose at least one object.",
  enterIdle: "Enter at least 1 minute.",
  enterRetention: "Enter at least 1 day. Use the policy setting to keep conversations for the org default.",
  enterWholeNumber: "Enter a whole number of at least 1."
};
