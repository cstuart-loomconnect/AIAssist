/*
Component Name: aiAgentWizardStepModel

=================================================================
=================================================================

Description: The extended methods of the Model step: build the model rows with their tags and write the result of a connection check.

Step 1: Build one row for each model, with the line of detail and the tag that says how it is used
Step 2: Pick the model a new agent starts with
Step 3: Write what a connection check found

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { OPTION_CLASS, OPTION_SELECTED_CLASS, TAG_USED_CLASS, TAG_MUTED_CLASS, TAG_WARNING_CLASS, MILLISECONDS_PER_SECOND, DETAIL_SEPARATOR, NO_TEXT, LABELS } from "./aiAgentWizardStepModelSettings";

// Finds the most used model among the models, and null when there are none.
export function findMostUsedModel(models) {

  // [1] Keep the model with the most active agents
  const modelList = models || [];
  let mostUsed = null;

  modelList.forEach((model) => {
    const isMoreUsed = !mostUsed || (model.agentCount || 0) > (mostUsed.agentCount || 0);
    if (isMoreUsed) mostUsed = model;
  });

  return mostUsed;
}

// Builds the rows of the model list.
export function buildModelViews(models, modelConfigurationId) {

  // [1] The output limit of the most used model is what a lower limit is measured against
  const modelList = models || [];
  const mostUsed = findMostUsedModel(modelList);
  const mostUsedOutput = mostUsed ? mostUsed.maxOutputTokens : null;
  const modelViews = [];

  // [2] Build a row for each model
  modelList.forEach((model) => {
    const isSelected = model.modelId === modelConfigurationId;
    const agentCount = model.agentCount || 0;
    const hasLowerOutput = mostUsedOutput && model.maxOutputTokens && model.maxOutputTokens < mostUsedOutput && agentCount === 0;
    const outputText = model.maxOutputTokens ? Number(model.maxOutputTokens).toLocaleString() + LABELS.maxOutput : NO_TEXT;
    const temperatureText = model.temperature !== null && model.temperature !== undefined ? LABELS.temperature + model.temperature : NO_TEXT;
    const detail = [model.provider, model.modelIdentifier, outputText, temperatureText].filter((part) => Boolean(part)).join(DETAIL_SEPARATOR);

    // [3] The tag says how the model is used
    let tagLabel = LABELS.notUsed;
    let tagClass = TAG_MUTED_CLASS;
    if (agentCount > 0) tagLabel = formatUsedBy(agentCount);
    if (agentCount > 0) tagClass = TAG_USED_CLASS;
    if (hasLowerOutput) tagLabel = LABELS.lowerOutput;
    if (!model.isActive) tagLabel = LABELS.inactive;
    if (!model.isActive) tagClass = TAG_WARNING_CLASS;

    modelViews.push({ key: model.modelId, name: model.name, detail, isSelected, optionClass: isSelected ? OPTION_SELECTED_CLASS : OPTION_CLASS, tagLabel, tagClass });
  });

  return modelViews;
}

// Writes how many agents use a model.
export function formatUsedBy(agentCount) {

  // [1] One or many
  if (agentCount === 1) return LABELS.usedByOne;

  return LABELS.usedByMany.replace("{count}", agentCount);
}

// Writes what a connection check found, from the result Apex returned.
export function formatTestText(result) {

  // [1] A good check says how long the test message took
  if (result.isSuccessful) {

    const seconds = ((result.latencyMilliseconds || 0) / MILLISECONDS_PER_SECOND).toFixed(1);

    return LABELS.testReturnedBefore + seconds + LABELS.testReturnedAfter;
  }

  // [2] A failed check says why, and the HTTP status when there was one
  const reasonText = result.failureReason ? LABELS.testFailedReason + result.failureReason : NO_TEXT;
  const httpText = result.httpStatusCode ? LABELS.testFailedHttp + result.httpStatusCode + ")" : NO_TEXT;

  return LABELS.testFailedBefore + reasonText + httpText + LABELS.testFailedEnd;
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
