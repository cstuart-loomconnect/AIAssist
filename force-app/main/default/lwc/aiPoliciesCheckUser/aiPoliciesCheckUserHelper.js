/*
Component Name: aiPoliciesCheckUser

=================================================================
=================================================================

Description: The extended methods of the Check a user box: build the answer for the template and write an error message.

Step 1: Build the answer, with a line for each policy that was considered
Step 2: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import {
  OUTCOME_WINS,
  OUTCOME_APPLIES,
  OUTCOME_PILL_GOOD_CLASS,
  OUTCOME_PILL_MUTED_CLASS,
  WINNER_NAME_CLASS,
  NO_TEXT,
  NUMBER_LOCALE,
  NO_LIMIT_TEXT,
  LABELS
} from "./aiPoliciesCheckUserSettings";

// Writes a limit with commas, or "No limit" when it is blank.
export function formatLimit(limitValue) {
  // [1] A blank limit means no limit
  const isBlank = limitValue === null || limitValue === undefined;
  if (isBlank) return NO_LIMIT_TEXT;

  // [2] Write the number with commas
  const limitText = Number(limitValue).toLocaleString(NUMBER_LOCALE);

  return limitText;
}

// Builds the answer the template shows from the result of Apex.
export function buildResultView(result) {
  // [1] Build one line for each source that was considered
  const sourceRows = result.sources.map((source, index) => {
    const isGood =
      source.outcome === OUTCOME_WINS || source.outcome === OUTCOME_APPLIES;
    const pillClass = isGood
      ? OUTCOME_PILL_GOOD_CLASS
      : OUTCOME_PILL_MUTED_CLASS;
    const nameClass =
      source.outcome === OUTCOME_WINS ? WINNER_NAME_CLASS : NO_TEXT;

    return {
      key: index,
      sourceLabel: source.sourceLabel,
      policyName: source.policyName,
      nameClass,
      tokens: formatLimit(source.maxTokensPer24Hours),
      conversations: formatLimit(source.maxConversationsPer24Hours),
      outcome: source.outcome,
      pillClass
    };
  });

  // [2] Build the answer: the policy that applies, why, and what to do about an ignored policy
  const hasPolicy = Boolean(result.policyId);
  const policyName = hasPolicy ? result.policyName : LABELS.noPolicy;
  const hasIgnoredPolicy = Boolean(result.ignoredPolicyId);
  const buttonLabel = hasIgnoredPolicy
    ? LABELS.assignPrefix + result.ignoredPolicyName + LABELS.assignSuffix
    : NO_TEXT;

  return {
    policyName,
    hasPolicy,
    reason: result.reason,
    sourceRows,
    hasHint: Boolean(result.hintText),
    hint: result.hintText,
    hasIgnoredPolicy,
    buttonLabel
  };
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
