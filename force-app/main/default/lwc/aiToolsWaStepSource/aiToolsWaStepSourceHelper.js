/*
Component Name: aiToolsWaStepSource

=================================================================
=================================================================

Description: The extended methods of step 2 of the workflow action wizard: build the rows and the inputs of the flow or class that was picked.

Step 1: Build one row for each flow or class
Step 2: Build the inputs of a flow from its variables
Step 3: Build the inputs of a class from the schema it describes
Step 4: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { DATA_TYPE_TEXT, DATA_TYPE_NUMBER, DATA_TYPE_BOOLEAN, DATA_TYPE_DATE, DATA_TYPE_DATE_TIME, SOURCE_PAGE, SOURCE_USER, SOURCE_AGENT, SOURCE_LEFT, SOURCE_UNSUPPORTED, SCHEMA_SOURCE_KEY, JSON_TYPE_NUMBER, JSON_TYPE_INTEGER, JSON_TYPE_BOOLEAN, JSON_FORMAT_DATE, JSON_FORMAT_DATE_TIME, PAGE_INPUT_NAME, USER_INPUT_PATTERN, DATE_LOCALE, ROW_CLASS, ROW_SELECTED_CLASS, NO_TEXT, LABELS } from "./aiToolsWaStepSourceSettings";

// Writes a date as day, month and year, such as 02/10/2026.
export function formatLongDate(dateValue) {

  // [1] Nothing to show when there is no date
  if (!dateValue) return NO_TEXT;

  // [2] Turn it into text
  const longDate = new Date(dateValue).toLocaleDateString(DATE_LOCALE);

  return longDate;
}

// Builds one row for each flow, with the chosen one marked.
export function buildFlowRows(flows, selectedName) {

  // [1] Build the rows
  const flowRows = flows.map((flow) => {

    const isSelected = flow.apiName === selectedName;

    return { key: flow.apiName, apiName: flow.apiName, label: flow.label, versionLabel: "v" + flow.versionNumber, inputCount: flow.inputCount, modifiedLabel: formatLongDate(flow.lastModified), isSelected, rowClass: isSelected ? ROW_SELECTED_CLASS : ROW_CLASS };
  });

  return flowRows;
}

// Builds one row for each Apex class, with the chosen one marked.
export function buildClassRows(classes, selectedName) {

  // [1] Build the rows
  const classRows = classes.map((apexClass) => {

    const isSelected = apexClass.className === selectedName;

    return { key: apexClass.className, className: apexClass.className, declaresLabel: apexClass.inputNames || LABELS.noneDeclared, calloutsLabel: apexClass.callouts || LABELS.noCallouts, hasCallouts: Boolean(apexClass.callouts), isSelected, rowClass: isSelected ? ROW_SELECTED_CLASS : ROW_CLASS };
  });

  return classRows;
}

// Chooses who fills a flow variable until the admin says otherwise.
export function getDefaultSource(variableName, isScreenFlow) {

  // [1] The open record fills recordId
  if (variableName === PAGE_INPUT_NAME) return SOURCE_PAGE;

  // [2] The person chatting fills an owner or user Id, except in a screen flow, which has no such fill
  if (USER_INPUT_PATTERN.test(variableName) && !isScreenFlow) return SOURCE_USER;

  // [3] A screen flow leaves the rest for the user, anything else is for the agent
  return isScreenFlow ? SOURCE_LEFT : SOURCE_AGENT;
}

// Builds the inputs of a flow from its input variables.
export function buildInputsFromVariables(variables, isScreenFlow) {

  // [1] Only input variables are inputs
  const inputVariables = variables.filter((variable) => variable.isInput);

  // [2] Build one input for each
  const inputs = inputVariables.map((variable) => {

    const typeLabel = variable.objectType ? variable.dataType + " (" + variable.objectType + ")" : variable.dataType;
    const source = variable.isSupported ? getDefaultSource(variable.name, isScreenFlow) : SOURCE_UNSUPPORTED;

    return { name: variable.name, dataType: variable.dataType, typeLabel, source, description: NO_TEXT, fixedValue: NO_TEXT, isConfirm: false, isRequired: true };
  });

  return inputs;
}

// Gets the data type for a JSON Schema property.
export function getDataTypeFromProperty(property) {

  // [1] One answer for each combination of type and format
  if (property.type === JSON_TYPE_NUMBER || property.type === JSON_TYPE_INTEGER) return DATA_TYPE_NUMBER;
  if (property.type === JSON_TYPE_BOOLEAN) return DATA_TYPE_BOOLEAN;
  if (property.format === JSON_FORMAT_DATE) return DATA_TYPE_DATE;
  if (property.format === JSON_FORMAT_DATE_TIME) return DATA_TYPE_DATE_TIME;

  return DATA_TYPE_TEXT;
}

// Builds the inputs of an Apex class from the schema it describes.
export function buildInputsFromSchema(inputSchema) {

  // [1] A class that describes nothing has no inputs yet
  if (!inputSchema) return [];

  try {

    // [2] Read the properties
    const properties = JSON.parse(inputSchema).properties || {};

    // [3] Build one input for each
    const inputs = Object.keys(properties).map((name) => {

      const property = properties[name];
      const dataType = getDataTypeFromProperty(property);
      const describedSource = property[SCHEMA_SOURCE_KEY];
      const source = describedSource || (name === PAGE_INPUT_NAME ? SOURCE_PAGE : SOURCE_AGENT);

      return { name, dataType, typeLabel: dataType, source, description: property.description || NO_TEXT, fixedValue: NO_TEXT, isConfirm: false, isRequired: true };
    });

    return inputs;

  } catch {

    return [];
  }
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
