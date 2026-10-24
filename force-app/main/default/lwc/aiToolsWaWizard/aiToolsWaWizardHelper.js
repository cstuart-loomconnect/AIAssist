/*
Component Name: aiToolsWaWizard

=================================================================
=================================================================

Description: The extended methods of the workflow action wizard: build and read the input schema, build the action to save, check each step and keep the draft in the browser.

Step 1: Turn the inputs of the draft into the input schema, and the schema back into inputs
Step 2: Turn the draft into the action Apex saves, and a saved action into a draft
Step 3: Work out whether each step is complete, and how the stepper shows it
Step 4: Keep the draft of a new action in the browser
Step 5: Turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STEP_TYPE, STEP_SOURCE, STEP_INPUTS, STEP_CONFIRMATION, STEP_TEST, STEP_NAMES, ACTION_TYPE_APEX, ACTION_TYPE_FLOW, ACTION_TYPE_SCREEN_FLOW, EXECUTION_WRITE, DATA_TYPE_TEXT, DATA_TYPE_NUMBER, DATA_TYPE_BOOLEAN, DATA_TYPE_DATE, DATA_TYPE_DATE_TIME, SOURCE_PAGE, SOURCE_USER, SOURCE_FIXED, SOURCE_AGENT, SOURCE_LEFT, SOURCE_UNSUPPORTED, SCHEMA_SOURCE_KEY, SCHEMA_VALUE_KEY, SCHEMA_CONFIRM_KEY, JSON_TYPE_STRING, JSON_TYPE_NUMBER, JSON_TYPE_INTEGER, JSON_TYPE_BOOLEAN, JSON_FORMAT_DATE, JSON_FORMAT_DATE_TIME, STEP_CLASS, STEP_CURRENT_CLASS, STEP_DONE_CLASS, STEP_ERROR_CLASS, MARKER_DONE, MARKER_ERROR, NO_TEXT, LABELS } from "./aiToolsWaWizardSettings";

// Gets the JSON Schema type and format for a data type.
export function getJsonType(dataType) {

  // [1] One answer for each data type
  if (dataType === DATA_TYPE_NUMBER) return { type: JSON_TYPE_NUMBER, format: null };
  if (dataType === DATA_TYPE_BOOLEAN) return { type: JSON_TYPE_BOOLEAN, format: null };
  if (dataType === DATA_TYPE_DATE) return { type: JSON_TYPE_STRING, format: JSON_FORMAT_DATE };
  if (dataType === DATA_TYPE_DATE_TIME) return { type: JSON_TYPE_STRING, format: JSON_FORMAT_DATE_TIME };

  return { type: JSON_TYPE_STRING, format: null };
}

// Gets the data type for a JSON Schema property.
export function getDataTypeFromProperty(property) {

  // [1] Read the type and format
  const jsonType = property.type || JSON_TYPE_STRING;
  const format = property.format || NO_TEXT;

  // [2] One answer for each combination
  if (jsonType === JSON_TYPE_NUMBER || jsonType === JSON_TYPE_INTEGER) return DATA_TYPE_NUMBER;
  if (jsonType === JSON_TYPE_BOOLEAN) return DATA_TYPE_BOOLEAN;
  if (format === JSON_FORMAT_DATE) return DATA_TYPE_DATE;
  if (format === JSON_FORMAT_DATE_TIME) return DATA_TYPE_DATE_TIME;

  return DATA_TYPE_TEXT;
}

// Turns the text typed for a fixed value into the value the schema holds.
export function getFixedSchemaValue(fixedValue, dataType) {

  // [1] A number is saved as a number and a boolean as true or false
  if (dataType === DATA_TYPE_NUMBER) return Number(fixedValue);
  if (dataType === DATA_TYPE_BOOLEAN) return String(fixedValue) === "true";

  return fixedValue;
}

// Builds the text saved in InputSchema__c from the inputs of the draft.
export function buildInputSchema(inputs) {

  // [1] Add each input that is filled by someone
  const properties = {};
  const requiredNames = [];

  inputs.forEach((input) => {

    const isNotPassed = input.source === SOURCE_LEFT || input.source === SOURCE_UNSUPPORTED;
    if (isNotPassed) return;

    // [2] Write the type, and then who fills it
    const jsonType = getJsonType(input.dataType);
    const property = { type: jsonType.type };
    if (jsonType.format) property.format = jsonType.format;

    if (input.source === SOURCE_PAGE || input.source === SOURCE_USER) {

      property.type = JSON_TYPE_STRING;
      delete property.format;
      property[SCHEMA_SOURCE_KEY] = input.source;

    } else if (input.source === SOURCE_FIXED) {

      property[SCHEMA_SOURCE_KEY] = SOURCE_FIXED;
      property[SCHEMA_VALUE_KEY] = getFixedSchemaValue(input.fixedValue, input.dataType);

    } else {

      // [3] The agent fills it, so it needs a description, may be required and may be shown at the confirmation
      if (input.description) property.description = input.description;
      if (input.isRequired !== false) requiredNames.push(input.name);
      if (input.isConfirm === true) property[SCHEMA_CONFIRM_KEY] = true;
    }

    properties[input.name] = property;
  });

  // [4] Return the schema as text
  const schema = { type: "object", properties, required: requiredNames };

  return JSON.stringify(schema);
}

// Reads the text saved in InputSchema__c into inputs, for a class or a flow that no longer lists them.
export function buildInputsFromSchema(inputSchema) {

  // [1] No schema, no inputs
  if (!inputSchema) return [];

  try {

    // [2] Read the properties and the names that are required
    const schema = JSON.parse(inputSchema);
    const properties = schema.properties || {};
    const requiredNames = schema.required || [];
    const inputs = [];

    // [3] Build one input for each property
    Object.keys(properties).forEach((name) => {

      const property = properties[name];
      const savedSource = property[SCHEMA_SOURCE_KEY];
      const source = savedSource || SOURCE_AGENT;
      const dataType = getDataTypeFromProperty(property);
      const fixedValue = property[SCHEMA_VALUE_KEY] === undefined ? NO_TEXT : String(property[SCHEMA_VALUE_KEY]);

      inputs.push({ name, dataType, typeLabel: dataType, source, description: property.description || NO_TEXT, fixedValue, isConfirm: property[SCHEMA_CONFIRM_KEY] === true, isRequired: requiredNames.includes(name) });
    });

    return inputs;

  } catch {

    return [];
  }
}

// Builds the inputs of a saved flow action: every input variable the flow has now, filled in from what was saved, and "not passed" when the action did not use it.
export function buildInputsFromVariables(variables, inputSchema, isScreenFlow) {

  // [1] Read what was saved
  const savedInputs = buildInputsFromSchema(inputSchema);
  const inputVariables = variables.filter((variable) => variable.isInput);

  // [2] Build one input for each input variable
  const inputs = inputVariables.map((variable) => {

    const savedInput = savedInputs.find((candidate) => candidate.name === variable.name);
    const typeLabel = variable.objectType ? variable.dataType + " (" + variable.objectType + ")" : variable.dataType;

    if (!variable.isSupported) return { name: variable.name, dataType: variable.dataType, typeLabel, source: SOURCE_UNSUPPORTED, description: NO_TEXT, fixedValue: NO_TEXT, isConfirm: false, isRequired: false };

    if (!savedInput) return { name: variable.name, dataType: variable.dataType, typeLabel, source: SOURCE_LEFT, description: NO_TEXT, fixedValue: NO_TEXT, isConfirm: false, isRequired: false };

    return { ...savedInput, dataType: variable.dataType, typeLabel };
  });

  // [3] A screen flow has no user or fixed fills, so those become "left for the user"
  const finalInputs = inputs.map((input) => (isScreenFlow && (input.source === SOURCE_USER || input.source === SOURCE_FIXED) ? { ...input, source: SOURCE_LEFT } : input));

  return finalInputs;
}

// Turns a saved action into the draft the wizard edits.
export function buildDraftFromDetail(detail, variables) {

  // [1] Work out the type and where the inputs come from
  const isApex = detail.actionType === ACTION_TYPE_APEX;
  const isScreenFlow = detail.actionType === ACTION_TYPE_SCREEN_FLOW;
  const sourceName = isApex ? detail.apexClassName : detail.flowApiName;
  const inputs = isApex ? buildInputsFromSchema(detail.inputSchema) : buildInputsFromVariables(variables, detail.inputSchema, isScreenFlow);
  const outputs = variables.filter((variable) => variable.isOutput).map((variable) => ({ name: variable.name, typeLabel: variable.dataType }));

  // [2] Build the draft
  const draft = { actionId: detail.actionId, actionType: detail.actionType, executionType: detail.executionType, sourceName, sourceLabel: sourceName, flowVersion: null, inputs, outputs, targetObject: detail.targetObject || NO_TEXT, requiresConfirmation: detail.requiresConfirmation === true, confirmationMessage: detail.confirmationMessage || NO_TEXT, actionName: detail.actionName, developerName: detail.developerName, isDeveloperNameEdited: true, description: detail.description || NO_TEXT, outputDescription: detail.outputDescription || NO_TEXT, isActive: detail.isActive === true, lastTestStatus: detail.lastTestStatus || null, agentCount: detail.agentCount || 0 };

  return draft;
}

// True when a write action must confirm: any write that is not a screen flow, or any action where the admin switched confirmation on.
export function isConfirmationNeeded(draft) {

  // [1] A screen flow is confirmed by the user pressing Finish, so only the admin's choice counts
  const isScreenFlow = draft.actionType === ACTION_TYPE_SCREEN_FLOW;
  const isWrite = draft.executionType === EXECUTION_WRITE;
  const isForced = isWrite && !isScreenFlow;

  return isForced || (draft.requiresConfirmation === true && !isScreenFlow);
}

// Builds the action Apex saves and tests from the draft.
export function buildActionDetail(draft) {

  // [1] Work out the type and the confirmation
  const isApex = draft.actionType === ACTION_TYPE_APEX;
  const needsConfirmation = isConfirmationNeeded(draft);

  // [2] Build the action
  const detail = { actionId: draft.actionId, actionName: draft.actionName, developerName: draft.developerName, description: draft.description, outputDescription: draft.outputDescription, actionType: draft.actionType, executionType: draft.executionType, apexClassName: isApex ? draft.sourceName : null, flowApiName: isApex ? null : draft.sourceName, targetObject: draft.targetObject, requiresConfirmation: needsConfirmation, confirmationMessage: needsConfirmation ? draft.confirmationMessage : null, inputSchema: buildInputSchema(draft.inputs), isActive: draft.isActive, lastTestStatus: draft.lastTestStatus };

  return detail;
}

// True when every input the admin has to fill in has been filled in.
export function areInputsComplete(inputs) {

  // [1] An agent input needs a description and a fixed input needs a value
  const incompleteInputs = inputs.filter((input) => {

    const needsDescription = input.source === SOURCE_AGENT && !(input.description || NO_TEXT).trim();
    const needsValue = input.source === SOURCE_FIXED && !String(input.fixedValue || NO_TEXT).trim();

    return needsDescription || needsValue;
  });

  return incompleteInputs.length === 0;
}

// True when the step has everything it needs.
export function isStepValid(draft, stepNumber) {

  // [1] The type step always has an answer, and so do the test and the screen flow's confirmation
  if (stepNumber === STEP_TYPE || stepNumber === STEP_TEST) return true;

  // [2] The source step needs a flow or a class
  if (stepNumber === STEP_SOURCE) return Boolean(draft.sourceName);

  // [3] The inputs step needs every input filled in
  if (stepNumber === STEP_INPUTS) return areInputsComplete(draft.inputs);

  // [4] The confirmation step needs a message when it confirms
  if (stepNumber === STEP_CONFIRMATION) return !isConfirmationNeeded(draft) || Boolean((draft.confirmationMessage || NO_TEXT).trim());

  // [5] The details step needs a name, an API name and a description
  const hasName = Boolean((draft.actionName || NO_TEXT).trim());
  const hasApiName = Boolean((draft.developerName || NO_TEXT).trim());
  const hasDescription = Boolean((draft.description || NO_TEXT).trim());

  return hasName && hasApiName && hasDescription;
}

// True when the step should show the warning marker: the inputs step with an input the agent cannot fill, or a step the admin has passed that is not complete.
export function hasStepProblem(draft, stepNumber, currentStep) {

  // [1] The inputs step is flagged while an input cannot be filled in
  const hasUnsupportedInput = draft.inputs.some((input) => input.source === SOURCE_UNSUPPORTED);
  if (stepNumber === STEP_INPUTS && hasUnsupportedInput && stepNumber <= currentStep) return true;

  // [2] A step the admin has already passed must be complete
  return stepNumber < currentStep && !isStepValid(draft, stepNumber);
}

// Builds the stepper: a marker, a label and a class for each step.
export function buildStepViews(draft, currentStep, maxStep) {

  // [1] Build one view for each step
  const stepViews = STEP_NAMES.map((step) => {

    const isCurrent = step.number === currentStep;
    const isReachable = step.number <= maxStep;
    const hasProblem = hasStepProblem(draft, step.number, currentStep);
    const isDone = step.number < currentStep && !hasProblem;

    // [2] Choose the class and the marker
    let stepClass = STEP_CLASS;
    let marker = String(step.number);

    if (hasProblem) {

      stepClass = STEP_ERROR_CLASS;
      marker = MARKER_ERROR;

    } else if (isCurrent) {

      stepClass = STEP_CURRENT_CLASS;

    } else if (isDone) {

      stepClass = STEP_DONE_CLASS;
      marker = MARKER_DONE;
    }

    const hasLine = step.number < STEP_NAMES.length;

    return { number: step.number, label: step.label, stepClass, marker, isDisabled: !isReachable, hasLine };
  });

  return stepViews;
}

// Gets the label for the pill beside the title.
export function getTypePillLabel(actionType) {

  // [1] One label for each type
  if (actionType === ACTION_TYPE_APEX) return LABELS.typePillApex;
  if (actionType === ACTION_TYPE_SCREEN_FLOW) return LABELS.typePillScreenFlow;
  if (actionType === ACTION_TYPE_FLOW) return LABELS.typePillFlow;

  return NO_TEXT;
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
