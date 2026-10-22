/*
Component Name: aiPoliciesForm

=================================================================
=================================================================

Description: The extended methods of the policy form: build the draft, build what each row shows and check the draft before it is sent.

Step 1: Build the draft from the saved values, with numbers written with commas
Step 2: Build the sections and rows with the value, the options and the classes of each
Step 3: Check the draft and build the values Apex expects

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ROW_TYPE_NUMBER, ROW_TYPE_SEGMENTS, ROW_TYPE_TOGGLE, ROW_TYPE_SELECT, ROW_TYPE_MULTI, FIELD_NAME, FIELD_CHANNELS, LIMIT_FIELDS, MULTI_SEPARATOR, SEGMENT_CLASS, SEGMENT_SELECTED_CLASS, NO_TEXT, NUMBER_LOCALE, LABELS } from "./aiPoliciesFormSettings";

// Says whether a value is blank: nothing, or an empty box.
export function isBlankValue(value) {

  // [1] Nothing, or an empty text, counts as blank
  const isBlank = value === null || value === undefined || value === NO_TEXT;

  return isBlank;
}

// Turns a stored number into text with commas, such as 200,000, and a blank into an empty box.
export function formatNumberText(storedValue) {

  // [1] A blank limit shows as an empty box
  if (isBlankValue(storedValue)) return NO_TEXT;

  // [2] Write the number with commas
  const numberText = Number(storedValue).toLocaleString(NUMBER_LOCALE);

  return numberText;
}

// Turns a stored multi-select value ("A;B") into the list the checkbox group needs.
export function buildChannelList(storedValue) {

  // [1] A blank value means nothing is ticked
  if (isBlankValue(storedValue)) return [];

  // [2] A list stays as it is
  if (Array.isArray(storedValue)) return storedValue;

  // [3] Text is split on the separator
  const channels = String(storedValue).split(MULTI_SEPARATOR);

  return channels;
}

// Builds the draft the form edits from the values of the saved policy.
export function buildDraft(values) {

  // [1] Start from a copy of the saved values
  const draft = { ...values };

  // [2] Show each limit with commas
  LIMIT_FIELDS.forEach((fieldName) => {
    draft[fieldName] = formatNumberText(values[fieldName]);
  });

  // [3] Keep the channels as a list
  draft[FIELD_CHANNELS] = buildChannelList(values[FIELD_CHANNELS]);

  return draft;
}

// Builds the choices of the segmented control, marking the chosen one.
export function buildSegments(row, draftValue) {

  // [1] One choice per option, with the class that marks the chosen one
  const segments = row.options.map((option) => {

    const isSelected = option.value === draftValue;
    const segmentClass = isSelected ? SEGMENT_SELECTED_CLASS : SEGMENT_CLASS;

    return { value: option.value, label: option.label, segmentClass, isSelected };
  });

  return segments;
}

// Builds the choices of the dropdown, marking the chosen one.
export function buildSelectOptions(row, draftValue) {

  // [1] One option per choice, marking the chosen one
  const selectOptions = row.options.map((option) => ({ value: option.value, label: option.label, isSelected: option.value === draftValue }));

  return selectOptions;
}

// Gets the help line under the segmented control: the help of the chosen option.
export function getSegmentHelp(row, draftValue) {

  // [1] Find the chosen option
  const chosenOption = row.options.find((option) => option.value === draftValue);
  const segmentHelp = chosenOption ? chosenOption.help : NO_TEXT;

  return segmentHelp;
}

// Builds the sections the template shows, with the control and the value of each row.
export function buildSectionViews(sections, draft) {

  // [1] Build one view per section
  const sectionViews = sections.map((section) => {

    // [2] Build one view per row
    const rows = section.rows.map((row) => {

      const draftValue = draft[row.key];
      const isNumber = row.type === ROW_TYPE_NUMBER;
      const isSegments = row.type === ROW_TYPE_SEGMENTS;
      const isToggle = row.type === ROW_TYPE_TOGGLE;
      const isSelect = row.type === ROW_TYPE_SELECT;
      const isMulti = row.type === ROW_TYPE_MULTI;
      const hasOptions = isSegments || isSelect || isMulti;
      const segments = isSegments ? buildSegments(row, draftValue) : [];
      const segmentHelp = isSegments ? getSegmentHelp(row, draftValue) : NO_TEXT;
      const selectOptions = isSelect ? buildSelectOptions(row, draftValue) : [];
      const multiOptions = isMulti ? row.options : [];
      const multiValue = isMulti ? draftValue || [] : [];
      const hasHelp = Boolean(row.help);
      const isChecked = draftValue === true;
      const numberValue = isNumber ? draftValue : NO_TEXT;

      return { key: row.key, label: row.label, help: row.help, hasHelp, apiName: row.key, isNumber, isSegments, isToggle, isSelect, isMulti, hasOptions, segments, segmentHelp, selectOptions, multiOptions, multiValue, isChecked, numberValue };
    });

    return { key: section.key, label: section.label, rows };
  });

  return sectionViews;
}

// Reads a limit typed in the box as a number, or null when it is blank. Returns undefined when it is not a whole number above zero.
export function parseLimit(typedText) {

  // [1] A blank limit means no limit
  if (isBlankValue(typedText)) return null;

  // [2] Take the commas and spaces out, then read the number
  const cleanText = String(typedText).replace(/[,\s]/g, NO_TEXT);
  const limitValue = Number(cleanText);

  // [3] Only a whole number above zero is a limit
  const isWholeNumber = cleanText !== NO_TEXT && Number.isInteger(limitValue) && limitValue > 0;
  if (!isWholeNumber) return undefined;

  return limitValue;
}

// Finds the label of a limit field, for a message.
export function getLimitLabel(fieldName, sections) {

  // [1] Look through every row of every section
  for (const section of sections) {

    const row = section.rows.find((candidate) => candidate.key === fieldName);
    if (row) return row.label;
  }

  return fieldName;
}

// Checks the draft and builds the values Apex expects. Returns { values } when it is fine, or { problem } with the message to show.
export function buildSaveValues(draft, sections) {

  // [1] A policy needs a name
  const name = isBlankValue(draft[FIELD_NAME]) ? NO_TEXT : String(draft[FIELD_NAME]).trim();
  if (name === NO_TEXT) return { problem: LABELS.nameRequired };

  // [2] Start from a copy of the draft
  const values = { ...draft, [FIELD_NAME]: name };

  // [3] Each limit becomes a number, or blank for no limit
  for (const fieldName of LIMIT_FIELDS) {

    const limitValue = parseLimit(draft[fieldName]);
    if (limitValue === undefined) return { problem: getLimitLabel(fieldName, sections) + LABELS.limitProblemPart1 + LABELS.limitProblemPart2 };
    values[fieldName] = limitValue;
  }

  return { values };
}
