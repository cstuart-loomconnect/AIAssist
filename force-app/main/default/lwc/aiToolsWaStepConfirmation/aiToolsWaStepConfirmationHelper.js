/*
Component Name: aiToolsWaStepConfirmation

=================================================================
=================================================================

Description: The extended methods of step 4 of the workflow action wizard: build the input chips and the preview rows.

Step 1: Build one chip for each input the agent or the server fills in
Step 2: Change whether an input is shown to the user
Step 3: Build the rows of the preview with sample values

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { DATA_TYPE_NUMBER, DATA_TYPE_BOOLEAN, DATA_TYPE_DATE, DATA_TYPE_DATE_TIME, SOURCE_USER, SOURCE_AGENT, SAMPLE_TEXT, SAMPLE_NUMBER, SAMPLE_BOOLEAN, SAMPLE_DATE_OFFSET_DAYS, SAMPLE_USER, DATE_LOCALE, CHIP_CLASS, CHIP_SELECTED_CLASS, CHIP_LOCKED_CLASS, NO_TEXT, LABELS } from "./aiToolsWaStepConfirmationSettings";

// Builds one chip for each input the agent or the server fills in. The agent's inputs can be chosen; the user's cannot.
export function buildChipViews(inputs) {

  // [1] Leave out the page's input and the ones nobody fills
  const chipViews = [];

  inputs.forEach((input, index) => {

    const isAgent = input.source === SOURCE_AGENT;
    const isUser = input.source === SOURCE_USER;
    if (!isAgent && !isUser) return;

    // [2] An agent input is chosen when it is shown; a user input is always grey
    const isSelected = isAgent && input.isConfirm === true;
    const chipClass = isUser ? CHIP_LOCKED_CLASS : isSelected ? CHIP_SELECTED_CLASS : CHIP_CLASS;

    chipViews.push({ key: input.name, index, name: input.name, chipClass, isSelected, isLocked: isUser, tick: LABELS.tick });
  });

  return chipViews;
}

// Returns the inputs with the choice flipped for one input.
export function toggleConfirmInput(inputs, index) {

  // [1] Copy every input, flipping the one at the index
  const toggledInputs = inputs.map((input, inputIndex) => (inputIndex === index ? { ...input, isConfirm: input.isConfirm !== true } : input));

  return toggledInputs;
}

// Turns a variable name into words, such as "dueDate" into "Due date".
export function humanise(name) {

  // [1] Put a space before each capital and capitalise the first letter
  const spaced = (name || NO_TEXT).replace(/([A-Z])/g, " $1").trim().toLowerCase();

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

// Gets a sample value for a data type, so the preview looks real.
export function getSampleValue(dataType) {

  // [1] A date or date and time is a week from today
  if (dataType === DATA_TYPE_DATE || dataType === DATA_TYPE_DATE_TIME) {

    const sampleDate = new Date();
    sampleDate.setDate(sampleDate.getDate() + SAMPLE_DATE_OFFSET_DAYS);

    return sampleDate.toLocaleDateString(DATE_LOCALE);
  }

  // [2] The other types have a fixed sample
  if (dataType === DATA_TYPE_NUMBER) return SAMPLE_NUMBER;
  if (dataType === DATA_TYPE_BOOLEAN) return SAMPLE_BOOLEAN;

  return SAMPLE_TEXT;
}

// Builds the rows of the preview: one for each input chosen to be shown, with a sample value.
export function buildPreviewRows(inputs) {

  // [1] Keep the chosen agent inputs
  const shownInputs = inputs.filter((input) => input.source === SOURCE_AGENT && input.isConfirm === true);

  // [2] Build one row for each
  const previewRows = shownInputs.map((input) => ({ key: input.name, label: humanise(input.name), value: getSampleValue(input.dataType) }));

  return previewRows;
}

// Builds the user's row of the preview when an input is filled by the signed in user.
export function buildUserRows(inputs) {

  // [1] Keep the inputs the server fills with the user
  const userInputs = inputs.filter((input) => input.source === SOURCE_USER);

  // [2] Build one row for each
  const userRows = userInputs.map((input) => ({ key: input.name, label: humanise(input.name), value: SAMPLE_USER }));

  return userRows;
}
