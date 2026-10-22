/*
Component Name: aiModelsForm

=================================================================
=================================================================

Description: The extended methods of the model form: build the provider cards, the credential choices and the test result, and apply a provider's starting settings.

Step 1: Build the provider cards and the credential choices
Step 2: Apply a provider's starting connection settings when the provider changes
Step 3: Build what the test result box shows, and the values sent to Apex

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { PROVIDER_CARDS, CARD_CLASS, CARD_SELECTED_CLASS, FIELD_PROVIDER, FIELD_API_PATH, FIELD_VERSION_HEADER_NAME, FIELD_VERSION_HEADER_VALUE, FIELD_TEMPERATURE, NUMBER_FIELDS, NO_TEXT, LABELS, RESULT_SUCCESS_CLASS, RESULT_FAILURE_CLASS, TEST_CONNECTED, TEST_REPLIED_IN, TEST_INPUT_TOKENS, TEST_OUTPUT_TOKENS, TEST_HTTP, TEST_SEPARATOR, TEST_COULDNT_CONNECT, TEST_STATUS_SEPARATOR, TEST_FAILURES, TEST_FAILURE_DEFAULT } from "./aiModelsFormSettings";

// Builds one card for each provider Apex offers, marking the chosen one.
export function buildProviderCards(providers, selectedProvider) {

  // [1] Build a card for each provider
  const providerList = providers || [];
  const cards = providerList.map((providerOption) => {

    const cardText = PROVIDER_CARDS[providerOption.provider] || { title: providerOption.provider, description: NO_TEXT };
    const isSelected = providerOption.provider === selectedProvider;
    const cardClass = isSelected ? CARD_SELECTED_CLASS : CARD_CLASS;

    return { key: providerOption.provider, provider: providerOption.provider, title: cardText.title, description: cardText.description, cardClass, isSelected };
  });

  return cards;
}

// Finds the option Apex offered for a provider, or null.
export function findProviderOption(providers, provider) {

  // [1] Search the list
  const providerList = providers || [];
  const providerOption = providerList.find((option) => option.provider === provider);

  return providerOption || null;
}

// Builds the choices of the named credential box, keeping the credential the model has even when Setup does not list it.
export function buildCredentialOptions(credentials, selectedCredential) {

  // [1] One choice for each credential in Setup
  const credentialList = credentials || [];
  const options = credentialList.map((credential) => ({ value: credential.credentialName, label: credential.label, isSelected: credential.credentialName === selectedCredential }));

  // [2] Keep the credential the model has when it is not in the list
  const isListed = options.some((option) => option.value === selectedCredential);
  if (selectedCredential && !isListed) options.unshift({ value: selectedCredential, label: selectedCredential, isSelected: true });

  return options;
}

// Changes the provider of a draft. The API path and version header follow the new provider's starting settings, unless the admin typed their own.
export function applyProviderPreset(draft, providers, nextProvider) {

  // [1] Find the starting settings of the old and the new provider
  const oldOption = findProviderOption(providers, draft[FIELD_PROVIDER]);
  const newOption = findProviderOption(providers, nextProvider);
  const nextDraft = { ...draft, [FIELD_PROVIDER]: nextProvider };
  if (!newOption) return nextDraft;

  // [2] Replace each setting that is blank or still the old provider's own
  nextDraft[FIELD_API_PATH] = pickPresetValue(draft[FIELD_API_PATH], oldOption ? oldOption.apiPath : null, newOption.apiPath);
  nextDraft[FIELD_VERSION_HEADER_NAME] = pickPresetValue(draft[FIELD_VERSION_HEADER_NAME], oldOption ? oldOption.versionHeaderName : null, newOption.versionHeaderName);
  nextDraft[FIELD_VERSION_HEADER_VALUE] = pickPresetValue(draft[FIELD_VERSION_HEADER_VALUE], oldOption ? oldOption.versionHeaderValue : null, newOption.versionHeaderValue);

  // [3] Keep the temperature inside what the new provider accepts
  const temperature = draft[FIELD_TEMPERATURE];
  const isTooHigh = typeof temperature === "number" && temperature > newOption.maxTemperature;
  if (isTooHigh) nextDraft[FIELD_TEMPERATURE] = newOption.maxTemperature;

  return nextDraft;
}

// Chooses the new starting value when the current one is blank or was the old starting value, and keeps the admin's own value otherwise.
export function pickPresetValue(currentValue, oldPresetValue, newPresetValue) {

  // [1] A blank value or the old provider's own value follows the new provider
  const isBlank = !currentValue;
  const isOldPreset = currentValue === oldPresetValue;
  const pickedValue = isBlank || isOldPreset ? newPresetValue || NO_TEXT : currentValue;

  return pickedValue;
}

// Reads a number from what was typed, and gives null when nothing was typed.
export function parseNumberOrNull(text) {

  // [1] Nothing typed is no number
  if (text === null || text === undefined || String(text).trim() === NO_TEXT) return null;

  const parsedNumber = Number(text);

  return Number.isNaN(parsedNumber) ? null : parsedNumber;
}

// Builds the values sent to Apex: the draft with its number fields as numbers.
export function buildModelPayload(draft) {

  // [1] Copy the draft, then turn each number field into a number
  const payload = { ...draft };
  NUMBER_FIELDS.forEach((fieldName) => {

    payload[fieldName] = parseNumberOrNull(draft[fieldName]);
  });

  return payload;
}

// Writes the help under the temperature box, such as "0 to 1. Lower is more predictable."
export function buildTemperatureHelp(providers, provider) {

  // [1] The highest temperature the provider accepts
  const providerOption = findProviderOption(providers, provider);
  const maxTemperature = providerOption ? providerOption.maxTemperature : NO_TEXT;
  const temperatureHelp = LABELS.temperatureHelpStart + maxTemperature + LABELS.temperatureHelpEnd;

  return temperatureHelp;
}

// Writes the used by line under the form, such as "Used by 3 active agents".
export function buildUsedByText(agentCount) {

  // [1] None, one, or many
  if (!agentCount) return LABELS.notUsed;
  if (agentCount === 1) return LABELS.usedByOne;

  const usedByText = LABELS.usedByStart + agentCount + LABELS.usedByEnd;

  return usedByText;
}

// Writes a time in milliseconds as seconds with one decimal, such as 1.2s.
export function formatLatency(latencyMilliseconds) {

  // [1] Milliseconds to seconds, to one decimal
  const seconds = (latencyMilliseconds / 1000).toFixed(1);

  return seconds + "s";
}

// Puts the model's own values into a sentence that holds {credential} or {model}.
export function fillPlaceholders(text, credential, model) {

  // [1] Replace each placeholder
  const filledText = text.split("{credential}").join(credential || NO_TEXT).split("{model}").join(model || NO_TEXT);

  return filledText;
}

// Builds what the test result box shows from the result Apex returned, or null when there is no result.
export function buildTestView(testResult, modelIdentifier) {

  // [1] No test has run
  if (!testResult) return null;

  // [2] A test that passed
  if (testResult.isSuccessful) return buildSuccessView(testResult);

  // [3] A test that failed
  return buildFailureView(testResult, modelIdentifier);
}

// Builds the box for a test that passed: "Connected. Replied in 1.2s · 18 input, 6 output tokens · HTTP 200".
export function buildSuccessView(testResult) {

  // [1] Say how long the reply took, when that is known
  const parts = [];
  if (testResult.latencyMilliseconds || testResult.latencyMilliseconds === 0) parts.push(TEST_REPLIED_IN + formatLatency(testResult.latencyMilliseconds));

  // [2] Say how many tokens were used, when the provider told us
  const hasTokens = testResult.inputTokens > 0 || testResult.outputTokens > 0;
  if (hasTokens) parts.push(testResult.inputTokens + TEST_INPUT_TOKENS + testResult.outputTokens + TEST_OUTPUT_TOKENS);

  // [3] Say which status came back
  if (testResult.httpStatusCode) parts.push(TEST_HTTP + testResult.httpStatusCode);

  const detail = parts.join(TEST_SEPARATOR);

  return { isSuccess: true, boxClass: RESULT_SUCCESS_CLASS, headline: TEST_CONNECTED, detail, hints: [], hasHints: false };
}

// Builds the box for a test that failed: a headline, what the provider did, and what to check.
export function buildFailureView(testResult, modelIdentifier) {

  // [1] Pick the wording for the reason
  const failure = TEST_FAILURES[testResult.failureReason] || TEST_FAILURES[TEST_FAILURE_DEFAULT];

  // [2] Write the headline, with the status when one came back
  const reasonText = testResult.httpStatusCode ? TEST_HTTP + testResult.httpStatusCode + TEST_STATUS_SEPARATOR + failure.reason : capitaliseFirst(failure.reason);
  const headline = TEST_COULDNT_CONNECT + " " + reasonText + ".";

  // [3] Fill in the credential and the model, in the detail and in each hint
  const detail = fillPlaceholders(failure.detail, testResult.namedCredential, modelIdentifier);
  const hints = failure.hints.map((hint, index) => ({ key: index, text: fillPlaceholders(hint, testResult.namedCredential, modelIdentifier) }));

  return { isSuccess: false, boxClass: RESULT_FAILURE_CLASS, headline, detail, hints, hasHints: hints.length > 0 };
}

// Makes the first letter of a text a capital.
export function capitaliseFirst(text) {

  // [1] Capitalise the first letter and keep the rest
  const capitalisedText = text.charAt(0).toUpperCase() + text.slice(1);

  return capitalisedText;
}
