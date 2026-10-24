/*
Component Name: aiPromptTemplatesEditor

=================================================================
=================================================================

Description: The settings of the Edit tab: field names, the four sections, checks, timings and label text.

Step 1: Name the template fields the editor changes
Step 2: Name the four sections and the checks the editor makes itself
Step 3: Hold the timings, class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The field names. They mirror AIPromptTemplatesDataStructure.TemplateDetail and FieldProblem.fieldName.
export const FIELD_TEMPLATE_NAME = "templateName";
export const FIELD_DEVELOPER_NAME = "developerName";
export const FIELD_MAX_LENGTH = "maxResponseLength";
export const FIELD_CONTEXT = "systemContext";
export const FIELD_TONE = "tone";
export const FIELD_PROMPT = "prompt";
export const FIELD_NEVER = "exclusionRules";

// The four sections in the order the editor shows them.
export const SECTION_DEFS = [
  {
    key: FIELD_CONTEXT,
    title: "Context",
    hint: "Who the agent is and where it is",
    help: "Tell the model who it is, who it is helping and what the user is looking at. This comes first in every message, so put the facts that stay the same here. Merge fields such as the agent name or the open record are filled in for each conversation.",
    placeholder: "You are {!Agent.Name}, an assistant for advisers at {!Org.Name}. You help with the {!Record.ObjectLabel} the user has open. Today is {!Today}."
  },
  {
    key: FIELD_TONE,
    title: "Tone",
    hint: "How it writes",
    help: "Describe how replies should sound: how formal, how long, which spelling and how to address the user. Leave this empty if the instructions already cover it.",
    placeholder: "Concise and factual. British English. Short paragraphs or up to 5 bullets. Address the user as {!User.FirstName}."
  },
  {
    key: FIELD_PROMPT,
    title: "Instructions",
    hint: "Required to activate",
    help: "The main guidance the model follows: what to base answers on, when to use a data source or action, and when to ask the user to confirm. A template cannot be saved without these.",
    placeholder: "Answer from the data your tools return. If something isn't there, say so. Before any action that changes a record, say what will change and wait for the user to confirm."
  },
  {
    key: FIELD_NEVER,
    title: "Never",
    hint: "Hard rules, checked every reply",
    help: "Things the model must never do, one rule per line. Keep each rule short and specific. Rules that matter for compliance belong here rather than in the instructions.",
    placeholder: "Never give regulated advice; say what the data shows and let the adviser decide."
  }
];

// The fields that make up the wording the agent sees. A change to one of these means a new version.
export const WORDING_FIELDS = [FIELD_CONTEXT, FIELD_TONE, FIELD_PROMPT, FIELD_NEVER, FIELD_MAX_LENGTH];

// The fields that are compared to find out whether the admin changed anything.
export const COMPARE_FIELDS = [FIELD_TEMPLATE_NAME, FIELD_DEVELOPER_NAME, FIELD_MAX_LENGTH, FIELD_CONTEXT, FIELD_TONE, FIELD_PROMPT, FIELD_NEVER];

// The fields sent to Apex when the editor asks for a preview, an impact, a try-it run or a save.
export const PAYLOAD_FIELDS = ["templateId", FIELD_TEMPLATE_NAME, FIELD_DEVELOPER_NAME, FIELD_MAX_LENGTH, FIELD_CONTEXT, FIELD_TONE, FIELD_PROMPT, FIELD_NEVER, "isActive", "isDefault", "version"];

// The API name must start with a letter and hold only letters, numbers and underscores. Mirrors the Apex rule.
export const DEVELOPER_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;

// The toast variant.
export const TOAST_VARIANT_ERROR = "error";

// How long to wait after the last edit before asking Apex for a preview, in milliseconds.
export const PREVIEW_DELAY_MS = 400;

// How a time is shown: day, month and 24-hour clock, in the UK order.
export const DATE_LOCALE = "en-GB";
export const DATE_OPTIONS = { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hour12: false };

// The classes of a field with and without a problem.
export const FIELD_CLASS = "slds-form-element";
export const FIELD_PROBLEM_CLASS = "slds-form-element slds-has-error";
export const DEVELOPER_INPUT_CLASS = "slds-input aipt-code-input";
export const DEVELOPER_INPUT_LOCKED_CLASS = "slds-input aipt-code-input aipt-code-input_locked";

// Text shown to the user.
export const LABELS = {
  fallbackError: "Something went wrong. Please try again.",
  fieldName: "Name",
  fieldDeveloperName: "API name",
  fieldMaxLength: "Max response length (words)",
  helpName: "The name admins see in lists and pickers, such as the name shown when choosing a template for an agent.",
  helpDeveloperName: "A short name with no spaces, such as MortgageAdviser. Slash commands use it to ask for this template. It cannot be changed once the template is saved.",
  helpMaxLength: "Most words in a reply. Empty means no limit.",
  developerNameLocked: "The API name cannot change once the template is saved.",
  insert: "Insert:",
  newTemplate: "New template",
  discard: "Discard changes",
  createTemplate: "Create template",
  saveChanges: "Save changes",
  publishPrefix: "Publish v",
  nameRequired: "Name is required.",
  developerNameRequired: "API name is required.",
  developerNameInvalid: "API name must start with a letter and use only letters, numbers and underscores.",
  maxLengthPositive: "Must be more than 0.",
  promptRequired: "Instructions are required.",
  bannerPublish: "Can't publish v",
  bannerPublishEnd: " yet.",
  bannerCreate: "Can't create the template yet.",
  bannerSave: "Can't save the changes yet.",
  thingOne: "1 thing to fix.",
  thingsMany: " things to fix.",
  liveSuffix: " live",
  inactiveSuffix: " inactive",
  lastEdited: " · last edited ",
  by: " by "
};
