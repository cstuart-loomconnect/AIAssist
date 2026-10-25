/*
Component Name: aiToolsDsInputs

=================================================================
=================================================================

Description: The extended methods of the Inputs step: build one row for each input and write the input schema that is saved.

Step 1: Build one row for each input, with who fills it and the controls it needs
Step 2: Write the input schema text from the inputs
Step 3: Build a new input and change one input in the list

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { INPUT_SOURCE_PAGE, INPUT_SOURCE_AGENT, INPUT_SOURCE_KEY, INPUT_TYPE_SCHEMAS, INPUT_TYPE_STRING, NEW_INPUT_NAME, NO_TEXT, PILL_PAGE_CLASS, PILL_AGENT_CLASS, TYPE_OPTIONS, LABELS } from "./aiToolsDsInputsSettings";

// Builds one row for each input.
export function buildInputViews(inputs, canEditNames) {

  // [1] Work out who fills each input and which controls its row shows
  const inputViews = inputs.map((input, index) => {

    const isPage = input.source === INPUT_SOURCE_PAGE;

    return { key: "input" + index, index, name: input.name, type: input.type, isRequired: input.isRequired, description: input.description, isPage, isAgent: !isPage, filledByLabel: isPage ? LABELS.filledByPage : LABELS.filledByAgent, pillClass: isPage ? PILL_PAGE_CLASS : PILL_AGENT_CLASS, canEditName: !isPage && canEditNames, canRemove: !isPage && canEditNames, typeChoices: TYPE_OPTIONS.map((option) => ({ label: option.label, value: option.value, isSelected: option.value === input.type })) };
  });

  return inputViews;
}

// Writes the input schema text from the inputs, the same way the wizard writes it when it saves.
export function buildSchemaText(inputs) {

  // [1] Write each input, the page ones with only the x-source key
  const properties = {};
  const required = [];

  inputs.forEach((input) => {

    if (input.source === INPUT_SOURCE_PAGE) {

      properties[input.name] = { type: "string", [INPUT_SOURCE_KEY]: INPUT_SOURCE_PAGE };

    } else {

      const typeSchema = INPUT_TYPE_SCHEMAS.find((item) => item.type === input.type) || INPUT_TYPE_SCHEMAS[0];
      const property = { type: typeSchema.schemaType };
      if (typeSchema.format) property.format = typeSchema.format;
      if (input.description) property.description = input.description;
      properties[input.name] = property;
    }

    if (input.isRequired) required.push(input.name);
  });

  // [2] Build the schema and write it as text
  const schemaText = JSON.stringify({ type: "object", properties, required }, null, 2);

  return schemaText;
}

// Builds an input the admin has just added to an Apex data source, with a name that no other input has.
export function buildNewInput(inputs) {

  // [1] Add a number to the name until it is free
  const names = inputs.map((input) => input.name);
  let name = NEW_INPUT_NAME;
  let counter = 1;

  while (names.includes(name)) {

    counter = counter + 1;
    name = NEW_INPUT_NAME + counter;
  }

  return { name, source: INPUT_SOURCE_AGENT, type: INPUT_TYPE_STRING, isRequired: true, description: NO_TEXT };
}

// Changes one input of the list and keeps the others as they are.
export function changeInput(inputs, index, changes) {

  // [1] Copy the list with the one input changed
  const changedInputs = inputs.map((input, inputIndex) => (inputIndex === index ? { ...input, ...changes } : input));

  return changedInputs;
}
