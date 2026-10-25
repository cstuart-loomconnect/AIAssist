/*
Component Name: aiAgentWizardPicker

=================================================================
=================================================================

Description: The extended methods of the picker: build the rows with their tags and messages, and apply the filter and the search.

Step 1: Work out how each data source or action fits the agent
Step 2: Build the rows and keep those the filter and the search let through
Step 3: Build the filter buttons and the line that says what is shown

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { KIND_DATA_SOURCE, FILTER_FITS, FILTER_NOT_ADDED, FILTERS, BINDING_BOUND, ACTION_TYPE_APEX, ACTION_TYPE_SCREEN_FLOW, OPTION_CLASS, OPTION_SELECTED_CLASS, OPTION_DISABLED_CLASS, FILTER_BUTTON_CLASS, FILTER_BUTTON_SELECTED_CLASS, TAG_CLASS, TAG_SUCCESS_CLASS, TAG_WARNING_CLASS, DETAIL_SEPARATOR, LIST_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardPickerSettings";

// Finds the label of an object, and falls back to its API name.
export function getObjectLabel(apiName, objectOptions) {

  // [1] Look in the list the step passed
  const found = (objectOptions || []).find((option) => option.apiName === apiName);

  return found ? found.label : apiName;
}

// Writes the type of an action for the admin.
export function formatActionType(actionType) {

  // [1] One answer for each type
  if (actionType === ACTION_TYPE_SCREEN_FLOW) return LABELS.screenFlowType;
  if (actionType === ACTION_TYPE_APEX) return LABELS.apexType;

  return LABELS.flowType;
}

// Builds the line of detail under the name of an option.
export function buildDetail(kind, option) {

  // [1] A data source shows its type, object and binding
  if (kind === KIND_DATA_SOURCE) {

    const bindingText = option.bindingType === BINDING_BOUND ? LABELS.bound : LABELS.unbound;

    return [option.sourceType, option.targetObject, bindingText].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR);
  }

  // [2] An action shows its type and the object it changes
  return [formatActionType(option.actionType), option.targetObject].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR);
}

// Says whether a data source is bound to an object the agent does not appear on. Actions are not checked here, because the object they name is the one they change; Apex reports the rest.
export function isObjectMismatch(kind, option, objectApiNames) {

  // [1] Only a bound data source needs the object
  const isBound = kind === KIND_DATA_SOURCE && option.bindingType === BINDING_BOUND;
  const isMismatch = isBound && Boolean(option.targetObject) && !(objectApiNames || []).includes(option.targetObject);

  return isMismatch;
}

// Builds the rows of the picker.
export function buildPickerRows(kind, options, addedIds, objectApiNames, objectOptions, selectedIds, filter, searchText) {

  // [1] Work out the state of each option
  const rows = [];
  const isDataSource = kind === KIND_DATA_SOURCE;
  const searchWords = (searchText || NO_TEXT).trim().toLowerCase();

  (options || []).forEach((option) => {
    const id = isDataSource ? option.dataSourceId : option.actionId;
    const isAdded = (addedIds || []).includes(id);
    const isMismatch = isObjectMismatch(kind, option, objectApiNames);
    const hasVersionProblem = !isDataSource && option.hasActiveFlowVersion === false;

    // [2] Keep it when the filter and the search let it through
    const searchable = (option.name + " " + (option.developerName || NO_TEXT)).toLowerCase();
    if (filter === FILTER_FITS && isMismatch) return;
    if (filter === FILTER_NOT_ADDED && isAdded) return;
    if (searchWords && !searchable.includes(searchWords)) return;

    // [3] The tag says how it fits, and the message says what to know
    let tagLabel = option.isActive ? LABELS.active : LABELS.inactive;
    let tagClass = option.isActive ? TAG_SUCCESS_CLASS : TAG_CLASS;
    let message = NO_TEXT;
    if (!option.isActive) message = LABELS.inactiveMessage;
    if (option.isActive && hasVersionProblem) message = LABELS.noVersionMessage;
    if (isMismatch) tagLabel = getObjectLabel(option.targetObject, objectOptions) + LABELS.onlySuffix;
    if (isMismatch) tagClass = TAG_WARNING_CLASS;
    if (isMismatch) message = LABELS.mismatchBefore + getObjectLabel(option.targetObject, objectOptions) + LABELS.mismatchMiddle + getObjectLabel(option.targetObject, objectOptions) + LABELS.mismatchAfter;
    if (isAdded) tagLabel = LABELS.alreadyAdded;
    if (isAdded) tagClass = TAG_CLASS;
    if (isAdded) message = NO_TEXT;

    const isDisabled = isAdded || isMismatch;
    const isSelected = !isDisabled && selectedIds.includes(id);
    let optionClass = isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS;
    if (isDisabled) optionClass = OPTION_DISABLED_CLASS;
    rows.push({ key: id, name: option.name, detail: buildDetail(kind, option), tagLabel, tagClass, message, hasMessage: Boolean(message) && !isAdded, isDisabled, isSelected, optionClass });
  });

  return rows;
}

// Builds the three filter buttons, with the chosen one marked.
export function buildFilterButtons(filter) {

  // [1] One button for each filter
  const filterButtons = FILTERS.map((candidate) => ({ value: candidate.value, label: candidate.label, buttonClass: candidate.value === filter ? FILTER_BUTTON_SELECTED_CLASS : FILTER_BUTTON_CLASS }));

  return filterButtons;
}

// Writes the line that says which objects the list is for.
export function buildShowingText(kind, objectApiNames, objectOptions) {

  // [1] The labels of the objects the agent appears on
  const names = (objectApiNames || []).map((apiName) => getObjectLabel(apiName, objectOptions));
  const lead = kind === KIND_DATA_SOURCE ? LABELS.showingDataSources : LABELS.showingActions;
  const listText = names.length > 0 ? names.join(LIST_SEPARATOR) : NO_TEXT;
  const showingText = kind === KIND_DATA_SOURCE ? lead + (listText ? listText + LABELS.andUnbound : LABELS.unbound) : lead + (listText || LABELS.unbound);

  return showingText;
}
