/*
Component Name: aiPromptTemplatesTryIt

=================================================================
=================================================================

Description: The extended methods of the Try it tab: the agent choices, the result columns, the saved message rows and the data sent to Apex.

Step 1: Build the agent choices and find the agent picked
Step 2: Build a result column for each side
Step 3: Build the saved message rows and keep the list up to date
Step 4: Build the payload for Apex and the error text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { SIDE_SAVED, VERDICT_BETTER, VERDICT_WORSE, STATUS_PASSED, STATUS_FAILED, PAYLOAD_FIELDS, LOCALE, TIME_OPTIONS, PILL_PASSED_CLASS, PILL_FAILED_CLASS, PILL_NEVER_CLASS, VERDICT_CHOSEN_VARIANT, VERDICT_PLAIN_VARIANT, RESULT_CLASS, RESULT_ERROR_CLASS, LABELS } from "./aiPromptTemplatesTryItSettings";

// Builds the choices of the Agent box.
export function buildAgentChoices(agentOptions) {

  // [1] One choice for each agent
  const optionList = agentOptions || [];
  const agentChoices = optionList.map((option) => ({ label: option.agentName, value: option.agentId }));

  return agentChoices;
}

// Finds the agent option with this id, or null.
export function findAgentOption(agentOptions, agentId) {

  // [1] Search the list
  const optionList = agentOptions || [];
  const found = optionList.find((option) => option.agentId === agentId);

  return found || null;
}

// Turns milliseconds and tokens into text such as "1.8s · 1,940 tokens".
export function formatRunMeta(run) {

  // [1] Seconds with one decimal
  const milliseconds = run.latencyMilliseconds || 0;
  const secondsText = (milliseconds / 1000).toFixed(1) + "s";

  // [2] Tokens with a thousands separator
  const tokens = run.totalTokens || 0;
  const tokensText = Number(tokens).toLocaleString(LOCALE) + LABELS.tokens;

  return secondsText + " · " + tokensText;
}

// Builds one result column: the title, the reply, the figures and the state of the Better and Worse buttons.
export function buildResultColumn(side, title, run, testMessage) {

  // [1] No run means no column content
  if (!run) return null;

  // [2] The text is the reply, or the reason it failed
  const isError = !run.isSuccessful;
  const replyText = run.replyText || LABELS.noReply;
  const text = isError ? run.errorMessage || LABELS.fallbackError : replyText;
  const metaText = isError ? "" : formatRunMeta(run);

  // [3] Which verdict is chosen on this side
  const verdict = testMessage ? (side === SIDE_SAVED ? testMessage.savedVerdict : testMessage.editedVerdict) : null;
  const betterVariant = verdict === VERDICT_BETTER ? VERDICT_CHOSEN_VARIANT : VERDICT_PLAIN_VARIANT;
  const worseVariant = verdict === VERDICT_WORSE ? VERDICT_CHOSEN_VARIANT : VERDICT_PLAIN_VARIANT;

  // [4] Build the view
  const resultClass = isError ? RESULT_ERROR_CLASS : RESULT_CLASS;
  const verdictDisabled = !testMessage || isError;

  return { side, title, text, metaText, resultClass, verdictDisabled, betterVariant, worseVariant, betterValue: VERDICT_BETTER, worseValue: VERDICT_WORSE };
}

// Turns a date and time into text such as "17 Oct, 21:05".
export function formatRunTime(dateValue) {

  // [1] No date means the message never ran
  if (!dateValue) return "";

  // [2] Format it in the UK order
  const formatter = new Intl.DateTimeFormat(LOCALE, TIME_OPTIONS);

  return formatter.format(new Date(dateValue));
}

// Builds one view per saved message.
export function buildMessageViews(testMessages, busyMessageId, isBusy) {

  // [1] One view for each message
  const messageList = testMessages || [];
  const messageViews = messageList.map((testMessage) => {

    // [2] The status pill of the last run
    let statusLabel = LABELS.neverRun;
    let statusClass = PILL_NEVER_CLASS;
    if (testMessage.lastRunStatus === STATUS_PASSED) {
      statusLabel = LABELS.passed;
      statusClass = PILL_PASSED_CLASS;
    }
    if (testMessage.lastRunStatus === STATUS_FAILED) {
      statusLabel = LABELS.failed;
      statusClass = PILL_FAILED_CLASS;
    }

    // [3] Build the view
    const isThisBusy = busyMessageId === testMessage.testMessageId;
    const runTimeText = formatRunTime(testMessage.lastRunOn);

    return { key: testMessage.testMessageId, testMessageId: testMessage.testMessageId, messageBody: testMessage.messageBody, statusLabel, statusClass, runTimeText, isDisabled: isBusy, runLabel: isThisBusy ? LABELS.loading : LABELS.run };
  });

  return messageViews;
}

// Returns the list with the message that has the same id replaced by the new one.
export function replaceMessage(testMessages, updatedMessage) {

  // [1] Swap the message that matches, and keep the rest
  const messageList = testMessages || [];
  const replaced = messageList.map((testMessage) => (testMessage.testMessageId === updatedMessage.testMessageId ? updatedMessage : testMessage));

  return replaced;
}

// Finds the saved message with this text, or null.
export function findMessageByBody(testMessages, messageBody) {

  // [1] Compare the text with the spaces trimmed
  const messageList = testMessages || [];
  const wantedText = (messageBody || "").trim();
  const found = messageList.find((testMessage) => (testMessage.messageBody || "").trim() === wantedText);

  return found || null;
}

// Builds the plain object Apex expects, with a number in the max length.
export function buildPayload(draft) {

  // [1] Copy only the fields Apex knows
  const payload = {};
  PAYLOAD_FIELDS.forEach((field) => {
    payload[field] = draft[field];
  });

  // [2] The max length is a number, or nothing when it is blank
  const lengthText = draft.maxResponseLength === null || draft.maxResponseLength === undefined ? "" : String(draft.maxResponseLength).trim();
  const lengthNumber = Number(lengthText);
  payload.maxResponseLength = lengthText === "" || Number.isNaN(lengthNumber) ? null : lengthNumber;

  return payload;
}

// Turns an error from Apex or JavaScript into text that is safe to show.
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
