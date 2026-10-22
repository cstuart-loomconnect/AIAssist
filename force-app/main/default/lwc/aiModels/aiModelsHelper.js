/*
Component Name: aiModels

=================================================================
=================================================================

Description: The extended methods of the AI Agent Models tab: build the model list, keep it in order, start a new model and write an error message.

Step 1: Build one list item for each model, with its pill and agent count
Step 2: Replace one model in the list with its saved version
Step 3: Build the values a new model starts from
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, MODEL_ITEM_CLASS, MODEL_ITEM_SELECTED_CLASS, PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, PILL_DRAFT_CLASS, DETAIL_SEPARATOR, NO_TEXT, NEW_MODEL_DEFAULTS } from "./aiModelsSettings";

// Builds the list items for the models, with an extra item for a new model that is not saved yet.
export function buildModelItems(models, selectedKey, isNewModel) {

  // [1] Build an item for each saved model
  const items = [];

  models.forEach((model) => {

    const isSelected = model.modelId === selectedKey;
    const itemClass = isSelected ? MODEL_ITEM_SELECTED_CLASS : MODEL_ITEM_CLASS;
    const pillLabel = model.isActive ? LABELS.active : LABELS.inactive;
    const pillClass = model.isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS;
    const agentLabel = formatAgentCount(model.agentCount);
    const detail = model.provider + DETAIL_SEPARATOR + agentLabel;
    items.push({ key: model.modelId, name: model.modelName, detail, itemClass, pillLabel, pillClass });
  });

  // [2] Add the new model at the top, selected
  if (isNewModel) items.unshift({ key: selectedKey, name: LABELS.newModelName, detail: LABELS.newModelNote, itemClass: MODEL_ITEM_SELECTED_CLASS, pillLabel: LABELS.draft, pillClass: PILL_DRAFT_CLASS });

  return items;
}

// Writes how many active agents use a model, such as "1 agent", "3 agents" or "not used".
export function formatAgentCount(agentCount) {

  // [1] No agents reads as not used
  if (!agentCount) return LABELS.notUsed;

  // [2] One agent is singular, any other number is plural
  const suffix = agentCount === 1 ? LABELS.agentOne : LABELS.agentMany;
  const agentLabel = agentCount + suffix;

  return agentLabel;
}

// Puts a saved model into the list in place of the old one, or at the end when it is new, and keeps the list in order with the active models first, then by name.
export function replaceModel(models, savedModel) {

  // [1] Remove the old version, if there is one
  const others = models.filter((model) => model.modelId !== savedModel.modelId);

  // [2] Add the saved one and put the list in order
  const combined = [...others, savedModel];
  combined.sort((first, second) => {

    if (first.isActive !== second.isActive) return first.isActive ? -1 : 1;

    return first.modelName.localeCompare(second.modelName);
  });

  return combined;
}

// Builds the values a new model starts from: the defaults, and the connection settings of the first provider.
export function buildNewModel(providers) {

  // [1] Take the first provider Apex offers, if it offered any
  const firstProvider = providers && providers.length > 0 ? providers[0] : null;
  const newModel = { ...NEW_MODEL_DEFAULTS };
  if (!firstProvider) return newModel;

  // [2] Start from its connection settings
  newModel.provider = firstProvider.provider;
  newModel.apiPath = firstProvider.apiPath || NO_TEXT;
  newModel.versionHeaderName = firstProvider.versionHeaderName || NO_TEXT;
  newModel.versionHeaderValue = firstProvider.versionHeaderValue || NO_TEXT;

  return newModel;
}

// Turns whatever an Apex call threw into text the admin can read.
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
