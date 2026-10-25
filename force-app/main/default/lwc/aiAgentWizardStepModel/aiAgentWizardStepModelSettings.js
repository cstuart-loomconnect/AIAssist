/*
Component Name: aiAgentWizardStepModel

=================================================================
=================================================================

Description: The settings of the Model step of the AI Agent Wizard: class names, event names and label text.

Step 1: Hold the class names and event names
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The classes of a model row and of its tags.
export const OPTION_CLASS = "aiawmo-option";
export const OPTION_SELECTED_CLASS = "aiawmo-option aiawmo-option_selected";
export const TAG_USED_CLASS = "aiawmo-pill aiawmo-pill_success";
export const TAG_MUTED_CLASS = "aiawmo-pill";
export const TAG_WARNING_CLASS = "aiawmo-pill aiawmo-pill_warning";

// The classes of the connection status pill.
export const STATUS_OK_CLASS = "aiawmo-pill aiawmo-pill_success";
export const STATUS_FAILED_CLASS = "aiawmo-pill aiawmo-pill_danger";
export const STATUS_WAITING_CLASS = "aiawmo-pill";

// The number of milliseconds in a second, for the time a test took.
export const MILLISECONDS_PER_SECOND = 1000;

// The text between the parts of a line of detail.
export const DETAIL_SEPARATOR = " · ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  intro: "Pick the model configuration this agent sends messages to. Only active configurations are listed.",
  usedByOne: "Used by 1 agent",
  usedByMany: "Used by {count} agents",
  notUsed: "Not used",
  lowerOutput: "Lower output limit",
  inactive: "Inactive",
  maxOutput: " max output",
  temperature: "temperature ",
  connectionNote: "The connection details (named credential, API path) live on the configuration, not the agent. Changing them there updates every agent using it.",
  connectionCheck: "Connection check",
  testing: "Testing",
  connected: "Connected",
  failed: "Failed",
  notTested: "Not tested",
  testAgain: "Test again",
  testReturnedBefore: "Test message returned in ",
  testReturnedAfter: "s.",
  testFailedBefore: "The test message failed",
  testFailedReason: ": ",
  testFailedHttp: " (HTTP ",
  testFailedEnd: ".",
  emptyTitle: "No active model configurations",
  emptyText: "An agent needs a model before it can be activated. Models are set up on the AI Agent Models tab. Save this agent as a draft and come back once one is active.",
  skip: "Skip for now",
  onlyExisting: "The wizard only uses what already exists. It never creates models, data sources or workflow actions."
};
