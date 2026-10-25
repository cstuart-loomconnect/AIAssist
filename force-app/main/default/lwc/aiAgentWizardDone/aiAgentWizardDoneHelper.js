/*
Component Name: aiAgentWizardDone

=================================================================
=================================================================

Description: The extended methods of the done screen: write what was created and the names of the objects.

Step 1: Write the list of what the save created
Step 2: Write the names of the objects, and the text of the Try it button

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LIST_SEPARATOR, VOWELS, NO_TEXT, LABELS } from "./aiAgentWizardDoneSettings";

// Writes a count with its one and many words.
export function formatCount(count, oneText, manyText) {

  // [1] One or many
  const total = count || 0;

  return total === 1 ? oneText : total + manyText;
}

// Writes the list of what a save created: "1 agent, 2 data sources, 0 workflow actions, 2 assignments".
export function buildCreatedText(saveResult) {

  // [1] One part for each kind of record
  const parts = [LABELS.agentOne, formatCount(saveResult.dataSourceCount, LABELS.dataSourceOne, LABELS.dataSourceMany), formatCount(saveResult.workflowActionCount, LABELS.actionOne, LABELS.actionMany), formatCount(saveResult.assignmentCount, LABELS.assignmentOne, LABELS.assignmentMany)];

  return parts.join(LIST_SEPARATOR);
}

// Finds the label of an object, and falls back to its API name.
export function getObjectLabel(apiName, objectOptions) {

  // [1] Look in the list the tab passed
  const found = (objectOptions || []).find((option) => option.apiName === apiName);

  return found ? found.label : apiName;
}

// Writes the names of the objects: "Opportunity and Account".
export function formatObjectList(objectApiNames, objectOptions) {

  // [1] Find the label of each object
  const names = (objectApiNames || []).map((apiName) => getObjectLabel(apiName, objectOptions));
  if (names.length <= 1) return names.join(LIST_SEPARATOR);

  // [2] Join them with commas and a last "and"
  const lastName = names[names.length - 1];
  const firstNames = names.slice(0, names.length - 1);

  return firstNames.join(LIST_SEPARATOR) + LABELS.and + lastName;
}

// Writes the Try it button: "Try it on an opportunity".
export function buildTryLabel(objectLabel) {

  // [1] The article depends on the first letter
  const lowerName = (objectLabel || NO_TEXT).toLowerCase();
  const article = VOWELS.includes(lowerName.charAt(0)) ? "an " : "a ";

  return LABELS.tryItBefore + article + lowerName;
}
