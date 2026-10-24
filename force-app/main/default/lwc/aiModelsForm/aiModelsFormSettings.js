/*
Component Name: aiModelsForm

=================================================================
=================================================================

Description: The settings of the model form: label text, provider cards, connection fields and the wording of a failed test.

Step 1: Hold the text shown to the admin
Step 2: Describe the provider cards and the fields that decide how the provider is called
Step 3: Hold the wording of each way a connection test can fail

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  newModelName: "New model",
  active: "Active",
  provider: "Provider",
  name: "Name",
  model: "Model",
  modelHelp: "The provider's model ID.",
  modelPlaceholder: "claude-sonnet-5-5",
  namedCredential: "Named credential",
  namedCredentialHelp:
    "Picked from named credentials in Setup. The API key never sits on this record.",
  namedCredentialPlaceholder: "Pick a named credential",
  apiPath: "API path",
  environmentId: "Environment ID",
  environmentIdHelp: "The Anthropic environment the agent session runs in.",
  versionHeader: "Version header",
  versionValue: "Version value",
  maxOutputTokens: "Max output tokens",
  temperature: "Temperature",
  temperatureHelpStart: "0 to ",
  temperatureHelpEnd: ". Lower is more predictable.",
  testTitle: "Connection test",
  testButton: "Test connection",
  testAgain: "Test again",
  testing: "Testing the connection",
  testNote:
    'Sends one short message ("Reply with OK") through the named credential. Uses a few tokens.',
  testStillSave:
    "You can still save. The model stays inactive until a test passes.",
  usedByStart: "Used by ",
  usedByEnd: " active agents",
  usedByOne: "Used by 1 active agent",
  notUsed: "Not used by any agent",
  cancel: "Cancel",
  save: "Save",
  saving: "Saving"
};

// The cards for the providers Apex offers. The keys are AIModelConfiguration__c.AIProvider__c values (AIAssistApplicationConstants.AI_PROVIDER_*).
export const PROVIDER_CARDS = {
  Anthropic: {
    title: "Anthropic",
    description: "Messages API. Claude models."
  },
  AnthropicAgent: {
    title: "AnthropicAgent",
    description: "Managed agents. Needs an environment ID."
  },
  OpenAI: { title: "OpenAI", description: "Chat Completions API." }
};

// The classes of a provider card; the chosen card also gets the second class.
export const CARD_CLASS = "aiamf-card";
export const CARD_SELECTED_CLASS = "aiamf-card aiamf-card_selected";

// The names of the fields the form reads and writes. They mirror AIModelsDataStructure.ModelView.
export const FIELD_PROVIDER = "provider";
export const FIELD_IS_ACTIVE = "isActive";
export const FIELD_API_PATH = "apiPath";
export const FIELD_VERSION_HEADER_NAME = "versionHeaderName";
export const FIELD_VERSION_HEADER_VALUE = "versionHeaderValue";
export const FIELD_TEMPERATURE = "temperature";

// The fields that decide how the provider is called. Changing one makes an old test result untrue.
export const CONNECTION_FIELDS = [
  "provider",
  "modelIdentifier",
  "namedCredential",
  "apiPath",
  "versionHeaderName",
  "versionHeaderValue",
  "environmentId"
];

// The fields that hold a number. Everything else holds text.
export const NUMBER_FIELDS = ["maxOutputTokens", "temperature"];

// The text of a value when it is empty.
export const NO_TEXT = "";

// The names of the events the form sends to the tab.
export const EVENT_CONNECTION_EDIT = "connectionedit";
export const EVENT_TEST = "test";
export const EVENT_SAVE = "save";
export const EVENT_CANCEL = "cancel";
export const EVENT_SWITCH_OFF = "switchoff";

// The classes of the test result box.
export const RESULT_SUCCESS_CLASS = "aiamf-result aiamf-result_success";
export const RESULT_FAILURE_CLASS = "aiamf-result aiamf-result_failure";

// The words of a connection test that passed. The pieces are joined with the separator.
export const TEST_CONNECTED = "Connected.";
export const TEST_REPLIED_IN = "Replied in ";
export const TEST_INPUT_TOKENS = " input, ";
export const TEST_OUTPUT_TOKENS = " output tokens";
export const TEST_HTTP = "HTTP ";
export const TEST_SEPARATOR = " · ";

// The words of a connection test that failed. {credential} and {model} are filled in with the model's own values.
export const TEST_COULDNT_CONNECT = "Couldn't connect.";
export const TEST_STATUS_SEPARATOR = ": ";

// The wording of each failure. The keys are AIConversationMessage__c.FailureReason__c values (AIAssistApplicationConstants.FAILURE_REASON_*); Provider Error is used for any other.
export const TEST_FAILURES = {
  "Authentication Failed": {
    reason: "authentication error",
    detail:
      "The provider rejected the API key in the named credential {credential}.",
    hints: [
      "Check the key in Setup › Named Credentials › {credential} › External Credential.",
      "Make sure the AI Assist Admin permission set has access to that external credential's principal."
    ]
  },
  "Model Retired": {
    reason: "model not available",
    detail: "The provider has no model called {model}, or it has been retired.",
    hints: ["Check the model ID against the provider's list of models."]
  },
  "Rate Limited": {
    reason: "too many requests",
    detail: "The provider is limiting calls made with the key in {credential}.",
    hints: [
      "Wait a minute and test again.",
      "Check the quota and billing on the provider account."
    ]
  },
  Timeout: {
    reason: "timed out",
    detail: "The provider did not answer in time.",
    hints: [
      "Test again.",
      "If it keeps happening, check the callout timeout in AI Assist Settings."
    ]
  },
  "Configuration Error": {
    reason: "setup problem",
    detail: "The named credential {credential} could not be called.",
    hints: [
      "Check the named credential exists in Setup and that its URL is allowed.",
      "Check the API path matches the provider."
    ]
  },
  "Provider Error": {
    reason: "provider error",
    detail: "The provider could not answer the test message.",
    hints: [
      "Check the model ID, the API path and the version header.",
      "Check the provider's status page."
    ]
  }
};
export const TEST_FAILURE_DEFAULT = "Provider Error";
