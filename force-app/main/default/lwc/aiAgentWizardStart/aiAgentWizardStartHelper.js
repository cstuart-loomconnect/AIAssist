/*
Component Name: aiAgentWizardStart

=================================================================
=================================================================

Description: The extended methods of the start screen: build the rows of the copy list.

Step 1: Build one row for each agent that can be copied

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { OPTION_CLASS, OPTION_SELECTED_CLASS, LIST_SEPARATOR, LABELS } from "./aiAgentWizardStartSettings";

// Turns API names into the labels the admin knows.
export function formatObjectNames(objectApiNames, objectOptions) {

  // [1] Find the label of each object, and fall back to the API name
  const names = [];
  const apiNames = objectApiNames || [];

  apiNames.forEach((apiName) => {
    const found = objectOptions.find((option) => option.apiName === apiName);
    names.push(found ? found.label : apiName);
  });

  return names.join(LIST_SEPARATOR);
}

// Builds the rows of the list of agents that can be copied.
export function buildCopyViews(copyOptions, objectOptions, selectedId) {

  // [1] Build a row for each agent
  const copyViews = [];
  const copyList = copyOptions || [];

  copyList.forEach((copyOption) => {
    const isSelected = copyOption.agentId === selectedId;
    const detail = formatObjectNames(copyOption.objectApiNames, objectOptions);
    const optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    const statusLabel = copyOption.isActive ? LABELS.active : LABELS.draft;
    copyViews.push({ key: copyOption.agentId, name: copyOption.name, detail, isSelected, statusLabel, optionClass });
  });

  return copyViews;
}
