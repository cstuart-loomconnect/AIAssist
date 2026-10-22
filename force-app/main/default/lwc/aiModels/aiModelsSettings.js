/*
Component Name: aiModels

=================================================================
=================================================================

Description: The settings of the AI Agent Models tab: label text, class names, keys and starting values.

Step 1: Hold the text shown to the admin
Step 2: Name the classes, keys and toast variants the controller and the helper use
Step 3: Hold the starting values of a new model

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  title: "AI Agent Models",
  subtitle: "Connections to AI providers that agents use",
  intro: "Each model configuration is one connection to an AI provider. Agents pick one in the wizard.",
  loading: "Loading models",
  newModel: "+ New model",
  newModelName: "New model",
  newModelNote: "Not saved",
  noModels: "No models yet. Add one to connect to a provider.",
  chooseOne: "Pick a model on the left, or add a new one.",
  active: "Active",
  inactive: "Inactive",
  draft: "Draft",
  agentOne: " agent",
  agentMany: " agents",
  notUsed: "not used",
  saved: "Model saved",
  savedStillOff: "Model saved, but it is still switched off because the connection test failed.",
  notSaved: "Not saved. The live model keeps its saved connection because the test failed.",
  switchedOff: "Model switched off",
  fallbackError: "Something went wrong. Try again."
};

// The key of a model that is not saved yet.
export const NEW_MODEL_KEY = "new";

// The text that joins the parts of the form key, so the form is built again when any part changes.
export const FORM_KEY_SEPARATOR = "|";

// The text of a message when it is empty.
export const NO_TEXT = "";

// The classes of one model in the list and of the pills beside it; the chosen model also gets the second class.
export const MODEL_ITEM_CLASS = "aiam-item";
export const MODEL_ITEM_SELECTED_CLASS = "aiam-item aiam-item_selected";
export const PILL_ACTIVE_CLASS = "aiam-pill aiam-pill_active";
export const PILL_INACTIVE_CLASS = "aiam-pill aiam-pill_inactive";
export const PILL_DRAFT_CLASS = "aiam-pill aiam-pill_draft";

// The text between the provider and the agent count in a list item.
export const DETAIL_SEPARATOR = " · ";

// The toast variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_WARNING = "warning";
export const TOAST_VARIANT_ERROR = "error";

// The values a new model starts from. The provider and its connection settings come from the first provider Apex offers. Mirrors AIModelsDataStructure.ModelView.
export const NEW_MODEL_DEFAULTS = {
  modelName: "",
  modelIdentifier: "",
  namedCredential: "",
  environmentId: "",
  maxOutputTokens: 4096,
  temperature: 0.2,
  isActive: false,
  agentCount: 0
};
