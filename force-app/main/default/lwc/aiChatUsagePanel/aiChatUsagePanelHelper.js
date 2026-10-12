/*
Component Name: aiChatUsagePanel

=================================================================
=================================================================

Description: Shows the user how much of each usage limit they have used today, in a panel that opens from the chat header.

Step 1: The parent (aiAssistChat) passes in a meter for each of the three usage limits
Step 2: The component shows a row for each, with the amount used and when it resets
Step 3: A limit the policy sets also gets a bar, amber when nearly used up and red when used up
Step 4: The close button, or the Escape key, tells the parent to close the panel

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LIMIT_LABELS, LABELS, WARN_PERCENT, FULL_PERCENT, TONE_OK, TONE_WARN, TONE_BAD, ROW_CLASS_PREFIX, BAR_STYLE_PREFIX, PLACEHOLDER_START, PLACEHOLDER_END, NUMBER_LOCALE } from "./aiChatUsagePanelSettings";

// Writes a number the way the user's locale does, such as 48,900.
export function formatAmount(value) {

  // [1] A blank value counts as nothing
  const amount = Number(value || 0);

  // [2] Write the number
  const amountLabel = amount.toLocaleString(NUMBER_LOCALE);

  return amountLabel;
}

// Puts values into a label, in order, in place of {0}, {1} and so on.
export function formatLabel(label, values) {

  // [1] Start with the label as it is
  let filledLabel = label;

  // [2] Replace each placeholder with its value
  values.forEach((value, index) => {

    const placeholder = `${PLACEHOLDER_START}${index}${PLACEHOLDER_END}`;
    filledLabel = filledLabel.replace(placeholder, value);
  });

  return filledLabel;
}

// Works out how full a limit is, from 0 to 100.
export function buildPercent(used, max) {

  // [1] A limit of nothing is full
  if (!max) return FULL_PERCENT;

  // [2] Work out the share used
  const share = Math.round((Number(used || 0) / Number(max)) * FULL_PERCENT);

  // [3] Never go past full
  const percent = Math.min(FULL_PERCENT, share);

  return percent;
}

// Picks the colour of a row from how full its limit is.
export function buildTone(percent) {

  // [1] Red when used up
  if (percent >= FULL_PERCENT) return TONE_BAD;

  // [2] Amber when nearly used up, otherwise calm
  if (percent >= WARN_PERCENT) return TONE_WARN;

  return TONE_OK;
}

// Writes the small label beside a limit that is nearly used up or reached. Blank when the limit is fine.
export function buildTagLabel(tone) {

  // [1] Pick the label from the colour
  if (tone === TONE_BAD) return LABELS.reached;
  if (tone === TONE_WARN) return LABELS.nearlyThere;

  return "";
}

// Writes the amounts for a limit that is set, such as "9,800 of 50,000 tokens".
export function buildUsageLabel(meter, unit) {

  // [1] Write the amount used and the limit
  const usedLabel = formatAmount(meter.used);
  const maxLabel = formatAmount(meter.max);

  // [2] Add the unit when there is one
  if (unit) return formatLabel(LABELS.usageOfUnit, [usedLabel, maxLabel, unit]);

  return formatLabel(LABELS.usageOf, [usedLabel, maxLabel]);
}

// Writes the line under the bar: what is left and when it resets, or what to do when the limit is used up.
export function buildHelpLabel(meter, text, tone) {

  // [1] A limit that is used up says what to do
  if (tone === TONE_BAD) return text.done;

  // [2] A limit that is fine just says when it resets
  if (tone !== TONE_WARN) return text.help;

  // [3] A limit that is nearly used up says what is left, then when it resets
  const left = Math.max(0, Number(meter.max) - Number(meter.used || 0));
  const leftLabel = text.unit ? formatLabel(LABELS.leftUnit, [formatAmount(left), text.unit]) : formatAmount(left);

  return formatLabel(LABELS.leftWithHelp, [leftLabel, text.help]);
}

// Picks the help line for a limit when it is fine. A limit that counts recent activity says how recent, when the agent has a timeout.
export function getHelpText(text, idleTimeoutMinutes) {

  // [1] Most limits just say when they reset
  if (!text.helpRecent || !idleTimeoutMinutes) return text.help;

  // [2] A count of open conversations says how recent a conversation has to be
  const helpText = formatLabel(text.helpRecent, [formatAmount(idleTimeoutMinutes)]);

  return helpText;
}

// Builds the row for one limit. Nothing for a limit this component has no words for.
export function buildRow(meter, idleTimeoutMinutes) {

  // [1] Take the words for this limit, with the help line that fits the agent's timeout
  const limitText = LIMIT_LABELS[meter.limitType];

  if (!limitText) return null;

  const text = { ...limitText, help: getHelpText(limitText, idleTimeoutMinutes) };

  // [2] A limit the policy does not set shows what is used, says there is no limit and has no bar
  const hasLimit = meter.max !== null && meter.max !== undefined;

  if (!hasLimit) return { key: meter.limitType, name: text.name, usageLabel: formatLabel(text.usedOnly, [formatAmount(meter.used)]), helpLabel: LABELS.noLimit, showBar: false, rowClass: `${ROW_CLASS_PREFIX}${TONE_OK}`, tagLabel: "" };

  // [3] Work out how full the limit is and its colour
  const percent = buildPercent(meter.used, meter.max);
  const tone = buildTone(percent);

  // [4] Write the words and hand back the row
  return { key: meter.limitType, name: text.name, usageLabel: buildUsageLabel(meter, text.unit), helpLabel: buildHelpLabel(meter, text, tone), showBar: true, percent, meterStyle: `${BAR_STYLE_PREFIX}${percent}%`, rowClass: `${ROW_CLASS_PREFIX}${tone}`, tagLabel: buildTagLabel(tone) };
}

// Builds the rows for every meter the user has. The agent's idle timeout is used to explain which conversations count as open.
export function buildRows(meters, idleTimeoutMinutes) {

  // [1] Nothing to show without meters
  if (!Array.isArray(meters)) return [];

  // [2] Build a row for each, dropping any this component has no words for
  const rows = meters.map((meter) => buildRow(meter, idleTimeoutMinutes)).filter(Boolean);

  return rows;
}
