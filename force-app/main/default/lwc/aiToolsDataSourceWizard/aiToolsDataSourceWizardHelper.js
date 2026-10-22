/*
Component Name: aiToolsDataSourceWizard

=================================================================
=================================================================

Description: The extended methods of the data source wizard: build a draft from a saved data source and back, keep the inputs in step with the query, check each step and build the stepper.

Step 1: Build a new draft, or a draft from a saved data source, and turn a draft back into what Apex saves
Step 2: Read and write the input schema, and keep the inputs in step with the binds in the query
Step 3: Say whether each step is complete and build the stepper
Step 4: Write what was tested so far and turn whatever an Apex call threw into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STEP_TYPE, STEP_QUERY, STEP_INPUTS, STEP_TEST, STEP_DETAILS, SOURCE_TYPE_SOQL, SOURCE_TYPE_APEX, BINDING_BOUND, QUERY_MODE_VISUAL, INPUT_SOURCE_PAGE, INPUT_SOURCE_AGENT, INPUT_SOURCE_KEY, BIND_RECORD_ID, INPUT_TYPE_ID, INPUT_TYPE_STRING, INPUT_TYPE_SCHEMAS, INPUT_NAME_PATTERN, DEFAULT_MAX_ROWS, NO_TEXT, STEP_CIRCLE_CLASS, STEP_CIRCLE_CURRENT_CLASS, STEP_CIRCLE_DONE_CLASS, STEP_CIRCLE_ERROR_CLASS, STEP_NAME_CLASS, STEP_NAME_CURRENT_CLASS, STEP_STATE_DONE, STEP_STATE_ERROR, STEP_STATE_CURRENT, STEP_STATE_TODO, LABELS } from "./aiToolsDataSourceWizardSettings";

// Builds the draft of a data source that has not been started.
export function buildNewDraft() {

  // [1] Start with a bound SOQL data source, the two choices the Type step shows first
  const draft = { dataSourceId: null, sourceType: SOURCE_TYPE_SOQL, bindingType: BINDING_BOUND, queryMode: QUERY_MODE_VISUAL, soqlTemplate: NO_TEXT, builder: null, maxRows: DEFAULT_MAX_ROWS, queryErrorCount: null, queryBinds: [], recordObjectApiName: null, apexClassName: NO_TEXT, apexDeclaredSchema: NO_TEXT, inputs: [], testRecordId: NO_TEXT, testInputValues: {}, testRunAsUserId: NO_TEXT, testRunAsUserName: NO_TEXT, testHistory: [], hasTested: false, sourceName: NO_TEXT, developerName: NO_TEXT, isDeveloperNameEdited: false, description: NO_TEXT, outputDescription: NO_TEXT, targetObject: NO_TEXT, isActive: true, agentCount: 0 };

  return draft;
}

// Builds the draft of a data source that is already saved.
export function buildDraftFromDetail(detail) {

  // [1] Start from a new draft, so every key exists
  const draft = buildNewDraft();
  // [2] Copy what was saved
  draft.dataSourceId = detail.dataSourceId;
  draft.sourceType = detail.sourceType;
  draft.bindingType = detail.bindingType || BINDING_BOUND;
  draft.soqlTemplate = detail.soqlTemplate || NO_TEXT;
  draft.apexClassName = detail.apexClassName || NO_TEXT;
  draft.maxRows = detail.maxRows || DEFAULT_MAX_ROWS;
  draft.sourceName = detail.sourceName;
  draft.developerName = detail.developerName;
  draft.isDeveloperNameEdited = true;
  draft.description = detail.description || NO_TEXT;
  draft.outputDescription = detail.outputDescription || NO_TEXT;
  draft.targetObject = detail.targetObject || NO_TEXT;
  draft.isActive = detail.isActive === true;
  draft.agentCount = detail.agentCount || 0;

  // [3] Read the inputs back from the saved schema
  draft.inputs = parseInputSchema(detail.inputSchema);

  return draft;
}

// Turns the draft into what Apex saves and tests.
export function buildDetailFromDraft(draft) {

  // [1] Only the fields of the chosen source type are sent
  const isSoql = draft.sourceType === SOURCE_TYPE_SOQL;
  const maxRows = isSoql ? Number(draft.maxRows) : null;

  // [2] Build the detail
  const detail = { dataSourceId: draft.dataSourceId, sourceName: draft.sourceName, developerName: draft.developerName, description: draft.description, outputDescription: draft.outputDescription, sourceType: draft.sourceType, bindingType: draft.bindingType, targetObject: draft.targetObject, maxRows, soqlTemplate: isSoql ? draft.soqlTemplate : null, apexClassName: isSoql ? null : draft.apexClassName, inputSchema: buildInputSchema(draft.inputs), isActive: draft.isActive };

  return detail;
}

// Builds what the Test step sends: the record, the agent inputs and the user to check.
export function buildTestRequest(draft) {

  // [1] An empty record is sent as nothing
  const recordId = draft.testRecordId || null;
  const runAsUserId = draft.testRunAsUserId || null;
  const inputValues = JSON.parse(JSON.stringify(draft.testInputValues));
  const request = { recordId, inputValues, runAsUserId };

  return request;
}

// Finds how an input type is written in the schema.
export function findInputTypeSchema(inputType) {

  // [1] An unknown type is written as text
  const typeSchema = INPUT_TYPE_SCHEMAS.find((item) => item.type === inputType) || INPUT_TYPE_SCHEMAS[0];

  return typeSchema;
}

// Writes the inputs as the input schema text that is saved on the data source.
export function buildInputSchema(inputs) {

  // [1] Write each input, the page ones with only the x-source key
  const properties = {};
  const required = [];

  inputs.forEach((input) => {

    if (input.source === INPUT_SOURCE_PAGE) {

      properties[input.name] = { type: "string", [INPUT_SOURCE_KEY]: INPUT_SOURCE_PAGE };

    } else {

      const typeSchema = findInputTypeSchema(input.type);
      const property = { type: typeSchema.schemaType };
      if (typeSchema.format) property.format = typeSchema.format;
      if (input.description) property.description = input.description;
      properties[input.name] = property;
    }

    if (input.isRequired) required.push(input.name);
  });

  // [2] Build the schema and write it as text
  const schema = { type: "object", properties, required };
  const schemaText = JSON.stringify(schema, null, 2);

  return schemaText;
}

// Reads the inputs back from the saved input schema text.
export function parseInputSchema(schemaText) {

  // [1] No schema means no inputs
  if (!schemaText) return [];

  // [2] Read the schema, and treat text that cannot be read as no inputs
  let schema = {};

  try {

    schema = JSON.parse(schemaText);

  } catch {

    return [];
  }

  const properties = schema.properties || {};
  const requiredNames = schema.required || [];
  const inputs = [];

  // [3] Build one input from each property
  Object.keys(properties).forEach((name) => {

    const property = properties[name];
    const isPage = property[INPUT_SOURCE_KEY] === INPUT_SOURCE_PAGE;
    const typeSchema = INPUT_TYPE_SCHEMAS.find((item) => item.schemaType === property.type && item.format === (property.format || NO_TEXT) && item.type !== INPUT_TYPE_ID);
    const inputType = isPage ? INPUT_TYPE_ID : typeSchema ? typeSchema.type : INPUT_TYPE_STRING;
    const isRequired = requiredNames.includes(name);
    inputs.push({ name, source: isPage ? INPUT_SOURCE_PAGE : INPUT_SOURCE_AGENT, type: inputType, isRequired, description: property.description || NO_TEXT });
  });

  return inputs;
}

// Keeps the inputs of a SOQL data source in step with the binds in its query, keeping what the admin already wrote.
export function mergeInputsWithBinds(inputs, binds, typeByBind, isBound) {

  // [1] Build one input for each bind, in the order the query uses them
  const mergedInputs = [];

  binds.forEach((bind) => {

    // [2] The open record is filled by the page, and only when the data source is bound
    if (bind === BIND_RECORD_ID) {

      if (isBound) mergedInputs.push({ name: BIND_RECORD_ID, source: INPUT_SOURCE_PAGE, type: INPUT_TYPE_ID, isRequired: true, description: NO_TEXT });
      return;
    }

    // [3] Any other bind is filled by the agent. Keep what was written, and take the type from the field the bind is compared to
    const existingInput = inputs.find((input) => input.name === bind && input.source === INPUT_SOURCE_AGENT);
    const bindType = typeByBind[bind] || INPUT_TYPE_STRING;

    if (existingInput) mergedInputs.push({ ...existingInput, type: typeByBind[bind] || existingInput.type });
    else mergedInputs.push({ name: bind, source: INPUT_SOURCE_AGENT, type: bindType, isRequired: true, description: NO_TEXT });
  });

  return mergedInputs;
}

// Says whether one step has everything it needs.
export function isStepValid(step, draft) {

  // [1] The Query step needs a query with no errors, or a class
  if (step === STEP_QUERY) {

    if (draft.sourceType === SOURCE_TYPE_APEX) return Boolean(draft.apexClassName);

    const hasQuery = Boolean(draft.soqlTemplate && draft.soqlTemplate.trim());

    return hasQuery && draft.queryErrorCount === 0;
  }

  // [2] The Inputs step needs every agent input named, unique, and described for the agent
  if (step === STEP_INPUTS) {

    const names = draft.inputs.map((input) => input.name);
    const hasBadName = draft.inputs.some((input) => !INPUT_NAME_PATTERN.test(input.name || NO_TEXT));
    const hasDuplicate = new Set(names).size !== names.length;
    const hasMissingDescription = draft.inputs.some((input) => input.source === INPUT_SOURCE_AGENT && !(input.description || NO_TEXT).trim());

    return !hasBadName && !hasDuplicate && !hasMissingDescription;
  }

  // [3] The Details step needs a name, an API name and a description
  if (step === STEP_DETAILS) {

    const hasName = Boolean(draft.sourceName && draft.sourceName.trim());
    const hasDescription = Boolean(draft.description && draft.description.trim());
    const hasApiName = INPUT_NAME_PATTERN.test(draft.developerName || NO_TEXT);

    return hasName && hasDescription && hasApiName;
  }

  // [4] The Type and Test steps are always complete
  return true;
}

// Builds the stepper: one item for each step with its circle, name and state.
export function buildStepViews(draft, currentStep) {

  // [1] Name each step. The second step is named for the source type
  const isApex = draft.sourceType === SOURCE_TYPE_APEX;
  const steps = [
    { number: STEP_TYPE, label: LABELS.stepType },
    { number: STEP_QUERY, label: isApex ? LABELS.stepApexClass : LABELS.stepQuery },
    { number: STEP_INPUTS, label: LABELS.stepInputs },
    { number: STEP_TEST, label: LABELS.stepTest },
    { number: STEP_DETAILS, label: LABELS.stepDetails }
  ];

  // [2] Work out the state of each step
  const stepViews = steps.map((step) => {

    const isCurrent = step.number === currentStep;
    const isPast = step.number < currentStep;
    const hasError = step.number === STEP_QUERY && !isApex && draft.queryErrorCount > 0 && step.number <= currentStep;
    let state = STEP_STATE_TODO;

    if (hasError) state = STEP_STATE_ERROR;
    else if (isPast) state = STEP_STATE_DONE;
    else if (isCurrent) state = STEP_STATE_CURRENT;

    // [3] Pick the classes and the text in the circle
    let circleClass = STEP_CIRCLE_CLASS;
    if (state === STEP_STATE_CURRENT) circleClass = STEP_CIRCLE_CURRENT_CLASS;
    if (state === STEP_STATE_DONE) circleClass = STEP_CIRCLE_DONE_CLASS;
    if (state === STEP_STATE_ERROR) circleClass = STEP_CIRCLE_ERROR_CLASS;

    const nameClass = isCurrent ? STEP_NAME_CURRENT_CLASS : STEP_NAME_CLASS;

    return { number: step.number, label: step.label, circleClass, nameClass, isDone: state === STEP_STATE_DONE, isError: state === STEP_STATE_ERROR, isNumber: state === STEP_STATE_CURRENT || state === STEP_STATE_TODO, isDisabled: !isPast };
  });

  return stepViews;
}

// Adds a test result to what was tested so far, replacing an earlier result for the same user.
export function addTestHistory(testHistory, status, runAsName) {

  // [1] Keep the results for other users, and replace the one for this user
  const userName = runAsName || NO_TEXT;
  const others = testHistory.filter((item) => item.userName !== userName);

  return [...others, { status, userName }];
}

// Writes what was tested so far, such as "Passed as you · Partial as Trainee adviser".
export function formatTestHistory(testHistory) {

  // [1] Write each result
  const parts = testHistory.map((item) => {

    const who = item.userName ? LABELS.lastTestAs + item.userName : LABELS.lastTestYou;

    return item.status + who;
  });

  return parts;
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

// Keeps the inputs in step with the query when the draft changes, and returns the changes with the new inputs.
export function applyDraftChanges(draft, changes) {

  // [1] Put the changes on a copy of the draft
  const nextDraft = { ...draft, ...changes };
  const isBound = nextDraft.bindingType === BINDING_BOUND;
  const hasChangedType = changes.sourceType !== undefined && changes.sourceType !== draft.sourceType;
  const hasChangedBinding = changes.bindingType !== undefined && changes.bindingType !== draft.bindingType;
  const hasNewBinds = changes.queryBinds !== undefined;
  const hasNewClass = changes.apexDeclaredSchema !== undefined;

  // [2] Changing the source type starts the inputs again
  if (hasChangedType) nextDraft.inputs = [];

  // [3] A SOQL data source takes its inputs from the binds in the query
  const isSoql = nextDraft.sourceType === SOURCE_TYPE_SOQL;

  if (isSoql && (hasNewBinds || hasChangedType || hasChangedBinding)) {

    const typeByBind = changes.queryBindTypes || draft.queryBindTypes || {};
    nextDraft.inputs = mergeInputsWithBinds(nextDraft.inputs, nextDraft.queryBinds, typeByBind, isBound);
  }

  // [4] An Apex class that describes its own inputs fills them in
  if (!isSoql && hasNewClass) nextDraft.inputs = nextDraft.apexDeclaredSchema ? parseInputSchema(nextDraft.apexDeclaredSchema) : [];

  // [5] An Apex data source that is bound always has the open record as an input
  if (!isSoql && (hasChangedType || hasChangedBinding || hasNewClass)) {

    const hasRecordInput = nextDraft.inputs.some((input) => input.name === BIND_RECORD_ID);
    const agentInputs = nextDraft.inputs.filter((input) => input.name !== BIND_RECORD_ID);
    const recordInput = { name: BIND_RECORD_ID, source: INPUT_SOURCE_PAGE, type: INPUT_TYPE_ID, isRequired: true, description: NO_TEXT };

    if (isBound) nextDraft.inputs = hasRecordInput ? nextDraft.inputs : [recordInput, ...agentInputs];
    else nextDraft.inputs = agentInputs;
  }

  return nextDraft;
}
