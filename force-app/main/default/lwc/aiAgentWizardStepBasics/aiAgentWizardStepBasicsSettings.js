/*
Component Name: aiAgentWizardStepBasics

=================================================================
=================================================================

Description: The settings of the Basics step of the AI Agent Wizard: field names, search timings, class names and label text.

Step 1: Name the fields this step reports and reads errors for
Step 2: Hold the search timings and the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The names of the draft fields this step changes, and the keys of the error messages it reads.
export const FIELD_AGENT_NAME = "agentName";
export const FIELD_DEVELOPER_NAME = "developerName";
export const FIELD_OBJECTS = "objectApiNames";

// The search for objects: letters needed before it runs, and the wait after the last key press.
export const SEARCH_MIN_LENGTH = 1;
export const SEARCH_DELAY_MILLISECONDS = 300;

// The longest API name the box accepts.
export const API_NAME_MAX_LENGTH = 60;

// The classes of a form element, with and without a problem.
export const FORM_ELEMENT_CLASS = "slds-form-element";
export const FORM_ELEMENT_ERROR_CLASS = "slds-form-element slds-has-error";
export const OPTION_CLASS = "aiawba-option";
export const OPTION_SELECTED_CLASS = "aiawba-option aiawba-option_selected";

// The text between the parts of a line of detail.
export const DETAIL_SEPARATOR = " · ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  agentName: "Agent name",
  apiName: "API name",
  apiNameHelp: "Filled in from the name. Letters, numbers and underscores only.",
  description: "Description",
  descriptionHelp: "For admins only. The agent never sees this.",
  objects: "Record pages it appears on",
  searchObjects: "Search objects...",
  searching: "Searching",
  noObjects: "No objects match.",
  objectsHelp: "Data sources and workflow actions bound to other objects won't be offered.",
  removeObject: "Remove",
  promptTemplate: "Prompt template",
  promptTemplateHelp: "Sets how the agent talks and what it must never do. Templates are written and versioned on the AI Prompt Templates tab; the agent always uses the live version.",
  live: "Live",
  defaultTag: "Default",
  noLiveVersion: "no live version",
  usedByOne: "used by 1 agent",
  usedByMany: "used by {count} agents",
  persona: "Persona and rules",
  personaHelp: "Optional, but agents without one answer in a generic tone.",
  greeting: "Greeting",
  greetingHelp: "First message in a new conversation.",
  fixOne: "1 thing to fix before you continue",
  fixMany: " things to fix before you continue"
};
