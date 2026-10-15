/*
Component Name: aiAssistSettingsForm

=================================================================
=================================================================

Description: The form for one settings row: a list of groups on the left, the fields of the chosen group on the right, and Save and Cancel.

Step 1: Show the groups of the row as a side list and the fields of the chosen group beside it
Step 2: Keep every change in a draft until the admin saves
Step 3: Check the draft for blank required numbers and numbers out of range before sending it
Step 4: Tell the panel to save the draft, and show any error the panel hands back

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { BADGE_CAN_OVERRIDE, BADGE_ORG_WIDE_ONLY, GROUP_ITEM_CLASS, GROUP_ITEM_SELECTED_CLASS, API_NAME_SEPARATOR, SENTENCE_END, EMPTY_TEXT, NO_MESSAGE, LABELS } from "./aiAssistSettingsFormSettings";

// Builds the side list: one item per group, with its field count and the class that marks the chosen one.
export function buildGroupItems(groups, selectedKey) {

  // [1] Start with an empty list
  const items = [];

  // [2] Build one item per group
  groups.forEach((group) => {

    const countLabel = formatFieldCount(group.fields.length);
    const isSelected = group.key === selectedKey;
    const itemClass = isSelected ? GROUP_ITEM_SELECTED_CLASS : GROUP_ITEM_CLASS;
    items.push({ key: group.key, label: group.label, countLabel, itemClass });
  });

  return items;
}

// Writes how many fields a group holds, such as "1 field" or "3 fields".
export function formatFieldCount(fieldCount) {

  // [1] One field is singular, any other number is plural
  const suffix = fieldCount === 1 ? LABELS.fieldSuffix : LABELS.fieldsSuffix;
  const countLabel = fieldCount + suffix;

  return countLabel;
}

// Builds what the template needs for each field of the chosen group.
export function buildFieldViews(group, draft, showScopeBadges) {

  // [1] Start with an empty list
  const fieldViews = [];

  // [2] Build one view per field
  group.fields.forEach((field) => {

    const value = draft[field.key];
    const apiName = group.objectName + API_NAME_SEPARATOR + field.key;
    const badgeLabel = getBadgeLabel(field, showScopeBadges);
    fieldViews.push({ key: field.key, field, value, apiName, badgeLabel });
  });

  return fieldViews;
}

// Gets the short text beside a field that says whether a profile or user may override it, or blank when badges are off.
export function getBadgeLabel(field, showScopeBadges) {

  // [1] No badges outside the organisation row of AI Assist Settings
  if (!showScopeBadges) return NO_MESSAGE;

  // [2] Say whether the field can be overridden
  const badgeLabel = field.overridable ? BADGE_CAN_OVERRIDE : BADGE_ORG_WIDE_ONLY;

  return badgeLabel;
}

// Says whether two sets of values hold the same things.
export function isSameValues(firstValues, secondValues) {

  // [1] Compare the values as text
  const firstText = JSON.stringify(firstValues);
  const secondText = JSON.stringify(secondValues);

  return firstText === secondText;
}

// Says whether a value is blank: nothing, or an empty box.
export function isBlankValue(value) {

  // [1] Nothing, or an empty text, counts as blank
  const isBlank = value === null || value === undefined || value === EMPTY_TEXT;

  return isBlank;
}

// Writes the message for a required field that is blank.
export function formatRequiredMessage(field) {

  // [1] The field name, then the fixed text
  const message = field.label + LABELS.requiredMessage;

  return message;
}

// Writes the message for a number outside its range.
export function formatRangeMessage(field) {

  // [1] The field name, the lowest value and the highest value
  const message = field.label + LABELS.rangeMessagePart1 + field.min + LABELS.rangeMessagePart2 + field.max + SENTENCE_END;

  return message;
}

// Finds the first blank required number or number out of range, so the form can open its group before the server is asked.
export function findFirstProblem(groups, draft) {

  // [1] Look at each field of each group
  for (let groupIndex = 0; groupIndex < groups.length; groupIndex++) {

    const group = groups[groupIndex];

    for (const field of group.fields) {

      const value = draft[field.key];
      const isBlank = isBlankValue(value);

      // [2] A required field must be filled in
      if (field.required && isBlank) return { groupIndex, message: formatRequiredMessage(field) };

      // [3] A number must sit inside its range
      const hasRange = field.min !== undefined && field.max !== undefined;
      const isBelowMin = Number(value) < field.min;
      const isAboveMax = Number(value) > field.max;
      const isOutOfRange = hasRange && !isBlank && (isBelowMin || isAboveMax);
      if (isOutOfRange) return { groupIndex, message: formatRangeMessage(field) };
    }
  }

  return null;
}
