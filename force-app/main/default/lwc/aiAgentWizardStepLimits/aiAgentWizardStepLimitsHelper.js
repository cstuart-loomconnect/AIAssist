/*
Component Name: aiAgentWizardStepLimits

=================================================================
=================================================================

Description: The extended methods of the Limits step: work out the estimated use from the draft, the users and the policy, and sort the findings by field.

Step 1: Work out a typical conversation and the daily total
Step 2: Say whether the limits fit the usage policy
Step 3: Sort the findings by the field they belong to
Step 4: Build the token counting cards and the form element classes

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { CODE_TOKENS_OVER_POLICY, CODE_ROUNDS_OVER_CAP, TRACKING_CARDS, TYPICAL_MESSAGES, TOKENS_PER_MESSAGE, CONVERSATIONS_PER_USER_PER_DAY, WORDS_PER_TOKEN, MILLION, CARD_CLASS, CARD_SELECTED_CLASS, FORM_ELEMENT_CLASS, FORM_ELEMENT_ERROR_CLASS, PILL_FITS_CLASS, PILL_OVER_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardStepLimitsSettings";

// Writes a count of tokens: whole numbers up to a million, then millions with one decimal.
export function formatTokenCount(count) {

  // [1] A million or more is written as 1.2M
  if (count >= MILLION) return (count / MILLION).toFixed(1) + "M";

  // [2] Anything smaller is written with separators
  return Math.round(count).toLocaleString();
}

// Works out the rows of the Estimated use panel.
export function buildEstimateRows(draft, accessUserCount, policy) {

  // [1] A typical conversation: a few messages, and the tokens they use, within the limits
  const maxMessages = Number(draft.maxMessagesPerConversation) || 0;
  const maxTokens = Number(draft.maxTokensPerConversation) || 0;
  const typicalMessages = Math.min(maxMessages, TYPICAL_MESSAGES);
  const typicalTokens = Math.min(maxTokens, typicalMessages * TOKENS_PER_MESSAGE);
  const typicalText = typicalMessages + LABELS.typicalMessages + formatTokenCount(typicalTokens) + LABELS.typicalTokens;

  // [2] The users who would see the agent, and what they use in a day
  const hasUsers = accessUserCount !== null && accessUserCount !== undefined;
  const usersText = hasUsers ? accessUserCount + LABELS.usersFromAccess : LABELS.usersUnknown;
  const perUserPerDay = typicalTokens * CONVERSATIONS_PER_USER_PER_DAY;
  const dailyTotal = hasUsers ? formatTokenCount(accessUserCount * perUserPerDay) + LABELS.tokensUnit : LABELS.usersUnknown;
  const dailyLabel = LABELS.dailyTotalBefore + CONVERSATIONS_PER_USER_PER_DAY + LABELS.dailyTotalAfter;
  const rows = [{ key: "typical", label: LABELS.typical, value: typicalText, pillLabel: NO_TEXT }, { key: "users", label: LABELS.users, value: usersText, pillLabel: NO_TEXT }, { key: "daily", label: dailyLabel, value: dailyTotal, pillLabel: NO_TEXT }];

  // [3] The usage policy, and whether a user's day fits inside it
  rows.push(buildPolicyRow(policy, perUserPerDay));

  return rows;
}

// Builds the usage policy row of the estimate.
export function buildPolicyRow(policy, perUserPerDay) {

  // [1] No policy means no limit to fit
  if (!policy) return { key: "policy", label: LABELS.usagePolicy, value: LABELS.noPolicy, pillLabel: NO_TEXT };

  // [2] A policy without a token limit has nothing to fit
  if (!policy.maxTokensPer24Hours) return { key: "policy", label: LABELS.usagePolicy, value: policy.policyName + LABELS.policyNoLimit, pillLabel: NO_TEXT };

  // [3] Compare a user's day with the limit
  const isFit = perUserPerDay <= policy.maxTokensPer24Hours;
  const value = policy.policyName + LABELS.policyLimitBefore + formatTokenCount(policy.maxTokensPer24Hours) + LABELS.policyLimitAfter;

  return { key: "policy", label: LABELS.usagePolicy, value, pillLabel: isFit ? LABELS.fits : LABELS.over, pillClass: isFit ? PILL_FITS_CLASS : PILL_OVER_CLASS };
}

// Sorts the findings of the step by the field they belong to.
export function buildFindingMessages(findings) {

  // [1] The two limits that have a field, and the rest
  const messages = { tokens: NO_TEXT, rounds: NO_TEXT, hasAny: false };
  (findings || []).forEach((finding) => {
    messages.hasAny = true;
    if (finding.code === CODE_TOKENS_OVER_POLICY) messages.tokens = finding.message;
    if (finding.code === CODE_ROUNDS_OVER_CAP) messages.rounds = finding.message;
  });

  return messages;
}

// Writes how many words fit in a number of tokens.
export function formatWords(tokens) {

  // [1] About three quarters of a word for each token
  const tokenCount = Number(tokens) || 0;
  const words = Math.round((tokenCount * WORDS_PER_TOKEN) / 1000) * 1000;

  return words.toLocaleString();
}

// Builds the token counting cards, with the chosen one marked.
export function buildTrackingCards(tokenTrackingMethod) {

  // [1] One view for each way of counting
  const trackingCards = TRACKING_CARDS.map((card) => ({ ...card, cardClass: card.value === tokenTrackingMethod ? CARD_SELECTED_CLASS : CARD_CLASS }));

  return trackingCards;
}

// Gives the class of a form element, with the SLDS problem look when it has a message.
export function buildFormElementClass(message) {

  // [1] A message means a problem
  const formElementClass = message ? FORM_ELEMENT_ERROR_CLASS : FORM_ELEMENT_CLASS;

  return formElementClass;
}

// Turns the text of a number field into a number, or null when it is blank.
export function parseNumberOrNull(value) {

  // [1] Blank stays blank
  if (value === null || value === undefined || value === NO_TEXT) return null;

  // [2] Text becomes a number
  const number = Number(value);
  const parsed = Number.isFinite(number) ? number : null;

  return parsed;
}
