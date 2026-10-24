/*
Component Name: aiToolsWaStepInputs

=================================================================
=================================================================

Description: The extended methods of step 3 of the workflow action wizard: build the rows of the inputs table and change one input.

Step 1: Build one row for each input, with the choices that suit it
Step 2: Change one input, add one or remove one
Step 3: Build the screen flow preview, the outputs text and the unsupported warning

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { DATA_TYPE_OPTIONS, BOOLEAN_OPTIONS, DATA_TYPE_TEXT, DATA_TYPE_NUMBER, DATA_TYPE_BOOLEAN, DATA_TYPE_DATE, DATA_TYPE_DATE_TIME, SOURCE_PAGE, SOURCE_USER, SOURCE_FIXED, SOURCE_AGENT, SOURCE_LEFT, SOURCE_UNSUPPORTED, PAGE_INPUT_NAME, SOURCE_OPTIONS_SERVER, SOURCE_OPTIONS_SCREEN, SOURCE_OPTION_PAGE, FIELD_TYPE_NUMBER, FIELD_TYPE_DATE, FIELD_TYPE_DATE_TIME, FIELD_TYPE_TEXT, PILL_PAGE_CLASS, PILL_UNSUPPORTED_CLASS, NO_TEXT, LABELS } from "./aiToolsWaStepInputsSettings";

// Gets the kind of field a fixed value of this data type is typed into.
// Copies a list of choices with the chosen one marked, because a plain drop-down needs to know which one is selected.
export function markChoices(choices, selectedValue) {

  // [1] Mark the choice whose value is the chosen one
  const markedChoices = choices.map((choice) => ({ label: choice.label, value: choice.value, isSelected: choice.value === selectedValue }));

  return markedChoices;
}

export function getFieldType(dataType) {

  // [1] One answer for each data type
  if (dataType === DATA_TYPE_NUMBER) return FIELD_TYPE_NUMBER;
  if (dataType === DATA_TYPE_DATE) return FIELD_TYPE_DATE;
  if (dataType === DATA_TYPE_DATE_TIME) return FIELD_TYPE_DATE_TIME;

  return FIELD_TYPE_TEXT;
}

// Gets the words in the Value column for an input nobody types into.
export function getStaticValueText(input, isApex, isScreenFlow) {

  // [1] One answer for each way of filling it
  if (input.source === SOURCE_PAGE) return LABELS.pageValue;
  if (input.source === SOURCE_USER) return LABELS.userValue;
  if (input.source === SOURCE_UNSUPPORTED) return LABELS.unsupportedValue;
  if (isScreenFlow) return LABELS.leftScreenValue;

  return isApex ? LABELS.leftApexValue : LABELS.leftFlowValue;
}

// Builds one row of the table for each input.
export function buildInputViews(inputs, isApex, isScreenFlow) {

  // [1] Choose the list of who can fill it
  const baseOptions = isScreenFlow ? SOURCE_OPTIONS_SCREEN : SOURCE_OPTIONS_SERVER;

  // [2] Build a row for each input
  const inputViews = inputs.map((input, index) => {

    const isPage = input.source === SOURCE_PAGE;
    const isUnsupported = input.source === SOURCE_UNSUPPORTED;
    const isFixedByName = input.name === PAGE_INPUT_NAME;
    const sourceOptions = isFixedByName ? [SOURCE_OPTION_PAGE, ...baseOptions] : baseOptions;
    const isAgent = input.source === SOURCE_AGENT;
    const isFixed = input.source === SOURCE_FIXED;
    const isBoolean = input.dataType === DATA_TYPE_BOOLEAN;
    const needsValue = isFixed && !String(input.fixedValue || NO_TEXT).trim();
    const needsDescription = isAgent && !(input.description || NO_TEXT).trim();

    return { key: index + ":" + input.name, index, name: input.name, typeLabel: input.typeLabel || input.dataType, dataType: input.dataType, isCustom: input.isCustom === true, isPill: isPage || isUnsupported, pillLabel: isPage ? SOURCE_OPTION_PAGE.label : LABELS.notSupported, pillClass: isPage ? PILL_PAGE_CLASS : PILL_UNSUPPORTED_CLASS, sourceChoices: markChoices(sourceOptions, input.source), typeChoices: markChoices(DATA_TYPE_OPTIONS, input.dataType), booleanChoices: markChoices(BOOLEAN_OPTIONS, input.fixedValue), source: input.source, isAgent, isFixedText: isFixed && !isBoolean, isFixedBoolean: isFixed && isBoolean, isStatic: !isAgent && !isFixed, staticText: getStaticValueText(input, isApex, isScreenFlow), description: input.description, fixedValue: input.fixedValue, fieldType: getFieldType(input.dataType), needsValue, needsDescription };
  });

  return inputViews;
}

// Returns the inputs with one input changed.
export function updateInput(inputs, index, changes) {

  // [1] Copy every input, changing the one at the index
  const updatedInputs = inputs.map((input, inputIndex) => (inputIndex === index ? { ...input, ...changes } : input));

  return updatedInputs;
}

// Returns the inputs with a new one the admin names, for the agent to fill in.
export function addInput(inputs) {

  // [1] Add an empty input at the end
  const newInput = { name: NO_TEXT, dataType: DATA_TYPE_TEXT, typeLabel: DATA_TYPE_TEXT, source: SOURCE_AGENT, description: NO_TEXT, fixedValue: NO_TEXT, isConfirm: false, isRequired: true, isCustom: true };

  return [...inputs, newInput];
}

// Returns the inputs without the one at the index.
export function removeInput(inputs, index) {

  // [1] Keep every other input
  const remainingInputs = inputs.filter((input, inputIndex) => inputIndex !== index);

  return remainingInputs;
}

// Writes how many inputs cannot be filled, such as "2 inputs can't be filled in by the agent. ".
export function buildUnsupportedCount(inputs) {

  // [1] Count them
  const unsupportedCount = inputs.filter((input) => input.source === SOURCE_UNSUPPORTED).length;

  return unsupportedCount;
}

// Writes the outputs as text, such as "taskId (Text) · taskSubject (Text)".
export function buildOutputsText(outputs) {

  // [1] Join each name with its type
  const outputTexts = outputs.map((output) => output.name + " (" + output.typeLabel + ")");

  return outputTexts.join(" · ");
}

// Turns a variable name into words, such as "noteSummary" into "Note summary".
export function humanise(name) {

  // [1] Put a space before each capital and capitalise the first letter
  const spaced = (name || NO_TEXT).replace(/([A-Z])/g, " $1").trim().toLowerCase();

  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

// Builds the fields of the screen flow preview: the inputs the agent pre-fills and the ones left for the user.
export function buildPreviewFields(inputs) {

  // [1] The page's own input is not a field the user sees
  const visibleInputs = inputs.filter((input) => input.source === SOURCE_AGENT || input.source === SOURCE_LEFT);

  // [2] Build one field for each
  const previewFields = visibleInputs.map((input) => {

    const isPrefilled = input.source === SOURCE_AGENT;

    return { key: input.name, label: humanise(input.name), isPrefilled, isLeft: !isPrefilled, value: input.description };
  });

  return previewFields;
}
