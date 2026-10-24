/*
Component Name: aiPromptTemplates

=================================================================
=================================================================

Description: The settings of the AI Prompt Templates tab: toast variants, the blank new template and label text.

Step 1: Name the toast variants the controller uses
Step 2: Hold the values of a template that is not saved yet
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The toast variants.
export const TOAST_VARIANT_ERROR = "error";
export const TOAST_VARIANT_SUCCESS = "success";

// The values of a template that is not saved yet. Mirrors AIPromptTemplatesDataStructure.TemplateDetail.
export const NEW_TEMPLATE = {
  templateId: null,
  templateName: "",
  developerName: "",
  maxResponseLength: null,
  systemContext: "",
  tone: "",
  prompt: "",
  exclusionRules: "",
  isActive: true,
  isDefault: false,
  version: null,
  agentCount: 0,
  lastModifiedDate: null,
  lastModifiedByName: null
};

// Text shown to the user.
export const LABELS = {
  title: "AI Prompt Templates",
  subtitle: "System prompts that agents use",
  loading: "Loading",
  noSelection: "Pick a template on the left, or start a new one.",
  fallbackError: "Something went wrong. Please try again.",
  activated: "Template activated.",
  madeDefault: "Template is now the default.",
  archived: "Template archived.",
  saved: "Template saved.",
  created: "Template created."
};
