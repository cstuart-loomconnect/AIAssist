/*
Component Name: aiAgentWizardStepBasics

=================================================================
=================================================================

Description: The extended methods of the Basics step: make the API name from the name, and build the chips, search matches and prompt template rows.

Step 1: Make an API name from the agent name
Step 2: Build the chips and the matches of the object search
Step 3: Build the prompt template rows
Step 4: Write the problem count, and the errors Apex threw

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { FORM_ELEMENT_CLASS, FORM_ELEMENT_ERROR_CLASS, OPTION_CLASS, OPTION_SELECTED_CLASS, DETAIL_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardStepBasicsSettings";

// Makes an API name from an agent name: letters and numbers only, starting with a letter.
export function buildDeveloperName(agentName) {

  // [1] Keep letters and numbers only
  const lettersAndNumbers = (agentName || NO_TEXT).replace(/[^A-Za-z0-9]/g, NO_TEXT);

  // [2] Drop any numbers at the start, because the name must start with a letter
  const developerName = lettersAndNumbers.replace(/^[0-9]+/, NO_TEXT);

  return developerName;
}

// Gives the class of a form element, with the SLDS problem look when it has a message.
export function buildFormElementClass(message) {

  // [1] A message means a problem
  const formElementClass = message ? FORM_ELEMENT_ERROR_CLASS : FORM_ELEMENT_CLASS;

  return formElementClass;
}

// Finds the label of an object from the lists the step knows.
export function getObjectLabel(apiName, objectOptions, foundOptions) {

  // [1] Look in both lists, and fall back to the API name
  const found = objectOptions.find((option) => option.apiName === apiName) || foundOptions.find((option) => option.apiName === apiName);
  const objectLabel = found ? found.label : apiName;

  return objectLabel;
}

// Builds the chips of the objects the agent appears on.
export function buildObjectChips(objectApiNames, objectOptions, foundOptions) {

  // [1] One chip for each chosen object
  const chips = [];
  const apiNames = objectApiNames || [];

  apiNames.forEach((apiName) => {
    chips.push({ apiName, label: getObjectLabel(apiName, objectOptions, foundOptions) });
  });

  return chips;
}

// Builds the matches of the object search, leaving out the objects already chosen.
export function buildSearchMatches(searchResults, objectApiNames) {

  // [1] Hide what is chosen
  const chosen = objectApiNames || [];
  const matches = searchResults.filter((result) => !chosen.includes(result.apiName));

  return matches;
}

// Builds the rows of the prompt template list.
export function buildTemplateViews(promptTemplates, promptTemplateId) {

  // [1] Is there a pick? Without one, the default template is the one in use
  const templateList = promptTemplates || [];
  const hasPick = templateList.some((template) => template.templateId === promptTemplateId);
  const templateViews = [];

  templateList.forEach((template) => {
    const isSelected = hasPick ? template.templateId === promptTemplateId : Boolean(template.isDefault);
    const hasVersion = template.version !== null && template.version !== undefined;
    const versionText = hasVersion ? "v" + template.version + " " + LABELS.live.toLowerCase() : LABELS.noLiveVersion;
    const usedText = formatUsedBy(template.agentCount);
    const parts = [template.isDefault ? NO_TEXT : versionText, template.description, usedText].filter((part) => Boolean(part));
    const detail = parts.join(DETAIL_SEPARATOR);
    const optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    const tagLabel = template.isDefault ? LABELS.defaultTag : LABELS.live;
    templateViews.push({ key: template.templateId, name: template.name, detail, isSelected, optionClass, tagLabel, isDefaultTag: Boolean(template.isDefault) });
  });

  return templateViews;
}

// Writes how many agents use a template.
export function formatUsedBy(agentCount) {

  // [1] Nothing is said about a template nobody uses
  if (!agentCount) return NO_TEXT;
  if (agentCount === 1) return LABELS.usedByOne;

  return LABELS.usedByMany.replace("{count}", agentCount);
}

// Writes the count of problems at the top of the step.
export function formatProblemCount(count) {

  // [1] One or many
  if (count === 1) return LABELS.fixOne;

  return count + LABELS.fixMany;
}

// Turns whatever an Apex call threw into text.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return NO_TEXT;
}
