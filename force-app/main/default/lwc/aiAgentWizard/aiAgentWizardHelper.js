/*
Component Name: aiAgentWizard

=================================================================
=================================================================

Description: The extended methods of the AI Agent Wizard tab: check the fields of the steps, build the stepper and the findings of a step, and write dates and error messages.

Step 1: Check the fields the admin must fix before going on
Step 2: Pick out what the Apex checks found for one step, and add the local problems to it
Step 3: Build the steps of the stepper with their markers
Step 4: Turn dates and errors into text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { STEP_BASICS, STEP_CONVERSATIONS, STEP_LIMITS, STEP_NAMES, STEP_REVIEW, SEVERITY_BLOCKER, FIELD_AGENT_NAME, FIELD_DEVELOPER_NAME, FIELD_OBJECTS, FIELD_IDLE, FIELD_RETENTION, FIELD_MESSAGES, FIELD_TOKENS, FIELD_ROUNDS, DEVELOPER_NAME_PATTERN, STEP_CLASS, STEP_CURRENT_CLASS, STEP_DONE_CLASS, STEP_ERROR_CLASS, STEP_CURRENT_ERROR_CLASS, MARKER_DONE, MARKER_ERROR, DATE_LOCALE, NO_TEXT, LABELS } from "./aiAgentWizardSettings";

// Builds the draft Apex is sent: a plain copy without the fields the wizard only shows, so the call carries nothing the Apex class cannot read.
export function toApexDraft(draft) {

  // [1] Copy it as plain data, and leave out what Apex never reads back
  const apexDraft = JSON.parse(JSON.stringify(draft));
  delete apexDraft.lastModifiedDate;
  delete apexDraft.userCount;

  return apexDraft;
}

// Says whether a number from a field is a whole number of at least one.
export function isPositiveNumber(value) {

  // [1] A blank or text value is not a number
  const hasValue = value !== null && value !== undefined && value !== NO_TEXT;
  if (!hasValue) return false;

  // [2] It must be at least one
  const number = Number(value);
  const isPositive = Number.isFinite(number) && number >= 1;

  return isPositive;
}

// Builds the problems with the draft that the admin must fix before going on. A live problem is shown at once, the others only after Next was pressed.
export function buildFieldErrors(draft, check, showErrors) {

  // [1] Basics: the name, the API name and the objects
  const errors = [];
  const developerName = draft.developerName || NO_TEXT;
  const objectApiNames = draft.objectApiNames || [];
  const isNameTaken = Boolean(check && check.isDeveloperNameTaken);
  if (!draft.agentName) errors.push({ step: STEP_BASICS, field: FIELD_AGENT_NAME, message: LABELS.enterName, isLive: false });
  if (!developerName) errors.push({ step: STEP_BASICS, field: FIELD_DEVELOPER_NAME, message: LABELS.enterApiName, isLive: false });
  if (developerName && !DEVELOPER_NAME_PATTERN.test(developerName)) errors.push({ step: STEP_BASICS, field: FIELD_DEVELOPER_NAME, message: LABELS.apiNameFormat, isLive: true });
  if (developerName && isNameTaken) errors.push({ step: STEP_BASICS, field: FIELD_DEVELOPER_NAME, message: LABELS.apiNameTakenBefore + developerName + LABELS.apiNameTakenAfter, isLive: true });
  if (objectApiNames.length === 0) errors.push({ step: STEP_BASICS, field: FIELD_OBJECTS, message: LABELS.chooseObject, isLive: false });

  // [2] Conversations: the numbers must be positive
  if (!isPositiveNumber(draft.idleTimeoutMinutes)) errors.push({ step: STEP_CONVERSATIONS, field: FIELD_IDLE, message: LABELS.enterIdle, isLive: false });
  if (!isPositiveNumber(draft.conversationRetentionDays)) errors.push({ step: STEP_CONVERSATIONS, field: FIELD_RETENTION, message: LABELS.enterRetention, isLive: false });

  // [3] Limits: the numbers must be positive
  if (!isPositiveNumber(draft.maxMessagesPerConversation)) errors.push({ step: STEP_LIMITS, field: FIELD_MESSAGES, message: LABELS.enterWholeNumber, isLive: false });
  if (!isPositiveNumber(draft.maxTokensPerConversation)) errors.push({ step: STEP_LIMITS, field: FIELD_TOKENS, message: LABELS.enterWholeNumber, isLive: false });
  if (!isPositiveNumber(draft.maxToolCallingIterations)) errors.push({ step: STEP_LIMITS, field: FIELD_ROUNDS, message: LABELS.enterWholeNumber, isLive: false });

  // [4] Keep the live ones, and the rest only once Next was pressed
  const shownErrors = errors.filter((error) => showErrors || error.isLive);

  return shownErrors;
}

// Builds the lookup a step uses to find the message of a field: { fieldName: message }.
export function buildFieldErrorMap(errors, step) {

  // [1] Keep the first message of each field of the step
  const fieldErrorMap = {};
  const stepErrors = errors.filter((error) => error.step === step);
  stepErrors.forEach((error) => {
    if (!fieldErrorMap[error.field]) fieldErrorMap[error.field] = error.message;
  });

  return fieldErrorMap;
}

// Picks out what the Apex checks found for one step.
export function getStepFindings(findings, step) {

  // [1] The checks may not have run yet
  const findingList = findings || [];
  const stepFindings = findingList.filter((finding) => finding.step === step);

  return stepFindings;
}

// Builds the findings the Review step lists: everything Apex found, plus a blocker for each step with a local problem Apex did not report.
export function buildReviewFindings(findings, errors) {

  // [1] Start from what Apex found
  const findingList = findings || [];
  const reviewFindings = [...findingList];

  // [2] Add a blocker for each step whose local problem Apex did not report
  errors.forEach((error) => {
    const isReported = findingList.some((finding) => finding.step === error.step && finding.severity === SEVERITY_BLOCKER);
    const isAdded = reviewFindings.some((finding) => finding.code === error.field);
    if (!isReported && !isAdded) reviewFindings.push({ severity: SEVERITY_BLOCKER, step: error.step, code: error.field, title: error.message, message: NO_TEXT });
  });

  return reviewFindings;
}

// Builds the steps of the stepper: a number, a tick for a step that is fine or an exclamation mark for a step with a problem.
export function buildStepViews(step, maxStep, findings, errors) {

  // [1] Work out the state of each step
  const stepViews = [];
  const findingList = findings || [];

  STEP_NAMES.forEach((stepName) => {
    const isCurrent = stepName.number === step;
    const isReached = stepName.number <= maxStep;
    const hasFinding = findingList.some((finding) => finding.step === stepName.number);
    const hasError = errors.some((error) => error.step === stepName.number);
    const hasProblem = isReached && (hasFinding || hasError) && stepName.number !== STEP_REVIEW;
    const isDone = isReached && !isCurrent && !hasProblem;

    // [2] Pick the class and the marker
    let stepClass = STEP_CLASS;
    let marker = String(stepName.number);
    if (isCurrent) stepClass = STEP_CURRENT_CLASS;
    if (isDone) stepClass = STEP_DONE_CLASS;
    if (hasProblem) stepClass = isCurrent ? STEP_CURRENT_ERROR_CLASS : STEP_ERROR_CLASS;
    if (isDone) marker = MARKER_DONE;
    if (hasProblem) marker = MARKER_ERROR;

    stepViews.push({ number: stepName.number, label: stepName.label, detail: stepName.detail, stepClass, marker, isDisabled: !isReached });
  });

  return stepViews;
}

// Turns a date from Apex into the day, month and year the admin reads.
export function formatLastChanged(value) {

  // [1] A new agent has no date
  if (!value) return NO_TEXT;

  // [2] Write it in the local style
  const formatted = new Date(value).toLocaleDateString(DATE_LOCALE);

  return formatted;
}

// Turns whatever an Apex call threw into text.
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
