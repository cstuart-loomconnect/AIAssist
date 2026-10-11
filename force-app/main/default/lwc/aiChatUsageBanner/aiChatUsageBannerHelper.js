/*
Component Name: aiChatUsageBanner

=================================================================
=================================================================

Description: Tells the user they have reached a usage limit, how far they are, and what it stops, as soon as the window opens.

Step 1: The parent (aiAssistChat) passes in the usage limit the user has reached (AIChatDataStructure.UsageLimitState)
Step 2: The component shows the limit, what it stops and a meter of how much has been used
Step 3: For the open conversations limit it offers a button to open the history, so the user can end one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import {
  LIMIT_TYPE,
  LIMIT_LABELS,
  LABELS,
  PLACEHOLDERS,
  MAX_PERCENT,
  NUMBER_LOCALE
} from "./aiChatUsageBannerSettings";

// Writes a number the way the user's locale does, such as 48,900.
export function formatAmount(value) {
  // [1] Write the number
  const amountLabel = Number(value || 0).toLocaleString(NUMBER_LOCALE);

  return amountLabel;
}

// How full the meter is, from 0 to 100.
export function buildPercent(used, max) {
  // [1] A limit of nothing is full
  if (!max) return MAX_PERCENT;

  // [2] Work out the share, and never go past full
  const percent = Math.min(
    MAX_PERCENT,
    Math.round((Number(used || 0) / Number(max)) * MAX_PERCENT)
  );

  return percent;
}

// The line under the title, from what the limit stops.
export function buildSubLabel(limitState) {
  // [1] Notify Only blocks nothing
  if (limitState.isNotifyOnly) return LABELS.subNotifyOnly;

  // [2] A limit that blocks messages blocks all of them; any other only stops a new conversation
  return limitState.blocksMessages
    ? LABELS.subBlocksMessages
    : LABELS.subBlocksNewConversations;
}

// Everything the template shows for a reached limit. Nothing when no limit is reached or the type is unknown.
export function buildView(limitState) {
  // [1] Nothing to show
  if (!limitState || !LIMIT_LABELS[limitState.limitType]) return null;

  // [2] Take the text for this limit
  const text = LIMIT_LABELS[limitState.limitType];
  const values = [
    formatAmount(limitState.used),
    formatAmount(limitState.max),
    text.unit
  ];
  const usageLabel = PLACEHOLDERS.reduce(
    (label, placeholder, index) => label.replace(placeholder, values[index]),
    LABELS.usageOf
  );

  // [3] Hand back the view
  return {
    title: text.title,
    subLabel: buildSubLabel(limitState),
    usageLabel,
    resetLabel: text.reset,
    percent: buildPercent(limitState.used, limitState.max),
    isNotifyOnly: !!limitState.isNotifyOnly,
    showHistoryButton:
      limitState.limitType === LIMIT_TYPE.OPEN && !limitState.isNotifyOnly
  };
}
