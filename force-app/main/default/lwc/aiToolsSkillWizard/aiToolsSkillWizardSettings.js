/*
Component Name: aiToolsSkillWizard

=================================================================
=================================================================

Description: The settings of the skill wizard: the steps, the shape of a new draft, the rules a step must meet, class names and label text.

Step 1: Number and name the four steps
Step 2: Hold the draft of a new skill and the keys that make its last test out of date
Step 3: Hold the rules the steps check: the API name pattern, the When To Use It length and the @ name pattern
Step 4: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The four steps, in order.
export const STEP_BASICS = 1;
export const STEP_TOOLS = 2;
export const STEP_INSTRUCTIONS = 3;
export const STEP_TEST = 4;
export const STEP_NAMES = [
  { number: STEP_BASICS, label: "Basics" },
  { number: STEP_TOOLS, label: "Tools" },
  { number: STEP_INSTRUCTIONS, label: "Instructions" },
  { number: STEP_TEST, label: "Test" }
];

// Values that mirror AISkill__c and the two kinds of tool a skill holds.
export const OUTPUT_CHAT_ANSWER = "Chat Answer";
export const TOOL_KIND_DATA_SOURCE = "dataSource";
export const TOOL_KIND_ACTION = "action";
export const BINDING_BOUND = "Bound";
export const TEST_STATUS_NONE = "";

// A new skill before the admin has typed anything.
export const NEW_DRAFT = { skillId: null, skillName: "", developerName: "", description: "", instructions: "", outputType: OUTPUT_CHAT_ANSWER, isActive: false, lastTestStatus: TEST_STATUS_NONE, lastTestedOn: null, agentCount: 0 };

// The draft keys that change what the model sees, so a change to any of them makes the last test out of date.
export const TEST_INVALIDATING_KEYS = ["developerName", "description", "instructions", "tools"];

// The rules the steps check. They mirror the AI Skill trigger, which checks them again on save.
export const API_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;
export const MENTION_PATTERN = /@([A-Za-z][A-Za-z0-9_]*)/g;
export const DESCRIPTION_MIN_LENGTH = 40;
export const DESCRIPTION_MAX_LENGTH = 400;
export const MAX_TOOLS = 20;

// The toast and confirm variants.
export const TOAST_VARIANT_SUCCESS = "success";
export const TOAST_VARIANT_ERROR = "error";
export const CONFIRM_VARIANT = "header";

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the header pills and the steps.
export const PILL_DRAFT_CLASS = "aitsk-pill aitsk-pill_draft";
export const PILL_TYPE_CLASS = "aitsk-pill aitsk-pill_type";
export const STEP_CLASS = "aitsk-step";
export const STEP_CURRENT_CLASS = "aitsk-step aitsk-step_current";
export const STEP_DONE_CLASS = "aitsk-step aitsk-step_done";
export const STEP_ERROR_CLASS = "aitsk-step aitsk-step_error";
export const MARKER_DONE = "✓";
export const MARKER_ERROR = "!";

// Text shown to the user.
export const LABELS = {
  newTitle: "New skill",
  draftPill: "Draft",
  activePill: "Active",
  inactivePill: "Inactive",
  newStatus: "Not saved yet",
  editing: "Changes are saved on Save",
  cancel: "Cancel",
  back: "Back",
  next: "Next",
  save: "Save skill",
  saved: "Skill saved.",
  loading: "Loading the skill",
  discardTitle: "Discard changes?",
  discardMessage: "The changes to this skill have not been saved.",
  saveTitle: "Save a skill agents use?",
  saveMessagePrefix: "This skill is used by ",
  saveMessageOne: " agent",
  saveMessageMany: " agents",
  saveMessageSuffix: ". The change is live as soon as it is saved.",
  fallbackError: "Something went wrong. Please try again."
};
