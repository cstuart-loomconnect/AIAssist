/*
Component Name: aiPromptTemplatesEditor

=================================================================
=================================================================

Description: The extended methods of the Edit tab: the checks, the changes, the labels and the data sent to Apex.

Step 1: Check the fields the editor can check itself and merge in the checks Apex returns
Step 2: Find out what changed and name the buttons and the footer
Step 3: Build the views and the payload for Apex

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FIELD_TEMPLATE_NAME, FIELD_DEVELOPER_NAME, FIELD_MAX_LENGTH, FIELD_PROMPT, SECTION_DEFS, WORDING_FIELDS, COMPARE_FIELDS, PAYLOAD_FIELDS, DEVELOPER_NAME_PATTERN, DATE_LOCALE, DATE_OPTIONS, FIELD_CLASS, FIELD_PROBLEM_CLASS, LABELS } from "./aiPromptTemplatesEditorSettings";

// Returns the text of a field, and "" when it is empty, so two empty values compare as equal.
export function getFieldText(value) {

  // [1] Nothing becomes empty text
  const hasValue = value !== null && value !== undefined;
  const fieldText = hasValue ? String(value).trim() : "";

  return fieldText;
}

// Builds the problems the editor can find without asking Apex.
export function buildLocalProblems(draft) {

  // [1] Start with no problems
  const problems = [];
  if (!draft) return problems;

  // [2] The name is required
  const nameText = getFieldText(draft[FIELD_TEMPLATE_NAME]);
  if (nameText === "") problems.push({ fieldName: FIELD_TEMPLATE_NAME, message: LABELS.nameRequired });

  // [3] The API name is required and has a fixed shape
  const developerText = getFieldText(draft[FIELD_DEVELOPER_NAME]);
  if (developerText === "") problems.push({ fieldName: FIELD_DEVELOPER_NAME, message: LABELS.developerNameRequired });
  if (developerText !== "" && !DEVELOPER_NAME_PATTERN.test(developerText)) problems.push({ fieldName: FIELD_DEVELOPER_NAME, message: LABELS.developerNameInvalid });

  // [4] The max length, when given, must be more than 0
  const lengthText = getFieldText(draft[FIELD_MAX_LENGTH]);
  const lengthNumber = Number(lengthText);
  const isLengthBad = lengthText !== "" && !(lengthNumber > 0);
  if (isLengthBad) problems.push({ fieldName: FIELD_MAX_LENGTH, message: LABELS.maxLengthPositive });

  // [5] The Instructions are required
  const promptText = getFieldText(draft[FIELD_PROMPT]);
  if (promptText === "") problems.push({ fieldName: FIELD_PROMPT, message: LABELS.promptRequired });

  return problems;
}

// Joins the problems found here with the problems Apex returned, once each.
export function mergeProblems(localProblems, serverProblems) {

  // [1] Start with the local problems
  const merged = [...(localProblems || [])];
  const seen = new Set(merged.map((problem) => problem.fieldName + "|" + problem.message));

  // [2] Add the problems Apex found that are not there yet
  (serverProblems || []).forEach((problem) => {
    const problemKey = problem.fieldName + "|" + problem.message;
    if (seen.has(problemKey)) return;
    seen.add(problemKey);
    merged.push(problem);
  });

  return merged;
}

// Builds a map from field name to the message to show under it. A field with two problems shows the first.
export function buildProblemMap(problems) {

  // [1] Keep the first message of each field
  const problemMap = {};
  (problems || []).forEach((problem) => {
    if (!problemMap[problem.fieldName]) problemMap[problem.fieldName] = problem.message;
  });

  return problemMap;
}

// Builds the four section views: key, title, hint, text and the problem to show.
export function buildSectionViews(draft, problemMap) {

  // [1] One view for each section
  const sectionViews = SECTION_DEFS.map((section) => {
    const value = draft ? draft[section.key] || "" : "";
    const message = problemMap[section.key] || "";

    return { key: section.key, title: section.title, hint: section.hint, help: section.help, placeholder: section.placeholder, value, message };
  });

  return sectionViews;
}

// Builds the class of a field: red when it has a problem.
export function buildFieldClass(message) {

  // [1] A message means a problem
  const fieldClass = message ? FIELD_PROBLEM_CLASS : FIELD_CLASS;

  return fieldClass;
}

// Answers true when the admin changed the wording the agent sees.
export function hasWordingChanged(savedTemplate, draft) {

  // [1] Compare each wording field with the saved one
  const isChanged = WORDING_FIELDS.some((field) => getFieldText(savedTemplate && savedTemplate[field]) !== getFieldText(draft && draft[field]));

  return isChanged;
}

// Answers true when any field differs from the saved template.
export function isDraftChanged(savedTemplate, draft) {

  // [1] Compare each field with the saved one
  const isChanged = COMPARE_FIELDS.some((field) => getFieldText(savedTemplate && savedTemplate[field]) !== getFieldText(draft && draft[field]));

  return isChanged;
}

// Answers true when the save must ask first: the template is saved and agents use it, or its wording changed.
export function isPublishDialogNeeded(savedTemplate, draft) {

  // [1] A template that is not saved yet never asks
  const isSaved = Boolean(savedTemplate && savedTemplate.templateId);
  if (!isSaved) return false;

  // [2] Ask when agents use it or the wording changed
  const hasAgents = savedTemplate.agentCount > 0;
  const isDialogNeeded = hasAgents || hasWordingChanged(savedTemplate, draft);

  return isDialogNeeded;
}

// Builds the label of the main button.
export function buildPrimaryLabel(savedTemplate, draft) {

  // [1] A template that is not saved yet is created
  const isSaved = Boolean(savedTemplate && savedTemplate.templateId);
  if (!isSaved) return LABELS.createTemplate;

  // [2] A changed wording is a new version
  const isWordingChanged = hasWordingChanged(savedTemplate, draft);
  if (isWordingChanged) return LABELS.publishPrefix + (Number(savedTemplate.version) + 1);

  return LABELS.saveChanges;
}

// Builds the sentence at the left of the footer.
export function buildFooterText(savedTemplate) {

  // [1] A template that is not saved yet has no history
  const isSaved = Boolean(savedTemplate && savedTemplate.templateId);
  if (!isSaved) return LABELS.newTemplate;

  // [2] The version and whether it is live
  const suffix = savedTemplate.isActive ? LABELS.liveSuffix : LABELS.inactiveSuffix;
  let footerText = "v" + savedTemplate.version + suffix;

  // [3] When and who last edited it
  const editedTime = formatEditedTime(savedTemplate.lastModifiedDate);
  if (editedTime) footerText += LABELS.lastEdited + editedTime;
  if (savedTemplate.lastModifiedByName) footerText += LABELS.by + savedTemplate.lastModifiedByName;

  return footerText;
}

// Turns a date and time into text such as "17 Oct, 21:05".
export function formatEditedTime(dateValue) {

  // [1] No date means no text
  if (!dateValue) return "";

  // [2] Format it in the UK order
  const date = new Date(dateValue);
  const formatter = new Intl.DateTimeFormat(DATE_LOCALE, DATE_OPTIONS);

  return formatter.format(date);
}

// Builds the sentence of the red banner, such as "Can't publish v4 yet. 3 things to fix."
export function buildBannerParts(savedTemplate, draft, problemCount) {

  // [1] Say what cannot happen yet
  const isSaved = Boolean(savedTemplate && savedTemplate.templateId);
  let lead = LABELS.bannerCreate;
  if (isSaved && hasWordingChanged(savedTemplate, draft)) lead = LABELS.bannerPublish + (Number(savedTemplate.version) + 1) + LABELS.bannerPublishEnd;
  if (isSaved && !hasWordingChanged(savedTemplate, draft)) lead = LABELS.bannerSave;

  // [2] Say how many things to fix
  const tail = problemCount === 1 ? LABELS.thingOne : problemCount + LABELS.thingsMany;

  return { lead, tail };
}

// Builds a PascalCase API name from a template name, such as "Mortgage adviser" to "MortgageAdviser".
export function buildDeveloperName(templateName) {

  // [1] Split on anything that is not a letter or a number
  const words = (templateName || "").split(/[^A-Za-z0-9]+/).filter((word) => word !== "");

  // [2] Capitalise each word and join them
  const developerName = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join("");

  // [3] A name must start with a letter
  const startsWithLetter = /^[A-Za-z]/.test(developerName);

  return startsWithLetter ? developerName : "";
}

// Builds the plain object Apex expects, with a number in the max length.
export function buildPayload(draft) {

  // [1] Copy only the fields Apex knows
  const payload = {};
  PAYLOAD_FIELDS.forEach((field) => {
    payload[field] = draft[field];
  });

  // [2] The max length is a number, or nothing when it is blank
  const lengthText = getFieldText(draft[FIELD_MAX_LENGTH]);
  const lengthNumber = Number(lengthText);
  payload[FIELD_MAX_LENGTH] = lengthText === "" || Number.isNaN(lengthNumber) ? null : lengthNumber;

  return payload;
}

// Turns an error from Apex or JavaScript into text that is safe to show.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return LABELS.fallbackError;
}
