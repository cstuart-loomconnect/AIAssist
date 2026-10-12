/*
Component Name: aiChatDebugTrace

=================================================================
=================================================================

Description: Helper functions for aiChatDebugTrace that format the trace values and copy or download text.

Step 1: Format durations, counts and labels for display
Step 2: Build the view of each step and the text to copy
Step 3: Copy text to the clipboard and save text as a file

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, EMPTY_VALUE, STEP_STATUS_FAILED, STEP_STATUS_CLASSES, STEP_STATUS_CLASS_DEFAULT, STEP_ROW_CLASS, STEP_ROW_CLASS_FAILED, MILLISECONDS_PER_SECOND, SECONDS_DECIMAL_PLACES, MODEL_LABEL_SEPARATOR, TOKENS_SEPARATOR, COPY_IDS_LINE_SEPARATOR, JSON_FILE_EXTENSION, DOWNLOAD_DATA_URL_PREFIX, HIDDEN_ELEMENT_POSITION, HIDDEN_ELEMENT_OPACITY, HIDDEN_ELEMENT_DISPLAY } from "./aiChatDebugTraceSettings";

// Answers true when a value has not been set (null or undefined).
export function isMissing(value) {

  // [1] Compare against both kinds of "nothing"
  return value === null || value === undefined;
}

// Turns a duration into display text: 2840 -> "2.84s", 410 -> "410ms".
export function formatMilliseconds(value) {

  // [1] Show a dash when there is no duration
  if (isMissing(value)) return EMPTY_VALUE;

  // [2] A second or more reads better as seconds
  if (value >= MILLISECONDS_PER_SECOND) {
    const seconds = value / MILLISECONDS_PER_SECOND;
    return `${seconds.toFixed(SECONDS_DECIMAL_PLACES)}s`;
  }

  // [3] Under a second stays in milliseconds
  return `${value}ms`;
}

// Turns a count into display text: 1240 -> "1,240", nothing -> "—".
export function formatCount(value) {

  // [1] Show a dash when there is no count
  if (isMissing(value)) return EMPTY_VALUE;

  // [2] Add the thousands separators
  const count = Number(value);
  return count.toLocaleString();
}

// Fills {0}, {1} and so on in a label with the values given, in order.
export function formatLabel(template, ...values) {

  // [1] Replace each placeholder with the value at the same position
  let text = template;

  values.forEach((value, index) => {
    text = text.replace(`{${index}}`, value);
  });

  return text;
}

// Joins the tokens sent and the tokens received into one line of text.
export function buildTokensLabel(promptTokens, replyTokens) {

  // [1] Format each count
  const promptCount = formatCount(promptTokens);
  const replyCount = formatCount(replyTokens);

  // [2] Join them
  return `${promptCount}${TOKENS_SEPARATOR}${replyCount}`;
}

// Joins the provider, model configuration and model into one line of text.
export function buildModelLabel(trace) {

  // [1] Put the parts in the order they are shown
  const labelParts = [trace.provider, trace.modelConfiguration, trace.model];

  // [2] Drop the parts the trace does not have
  const filledParts = labelParts.filter(Boolean);

  // [3] Join what is left, or show a dash when nothing is left
  const modelLabel = filledParts.join(MODEL_LABEL_SEPARATOR);
  return modelLabel || EMPTY_VALUE;
}

// Turns one step from the trace into the values its table row needs.
export function buildStepView(step, index) {

  // [1] Work out the position, falling back to the row number
  const order = step.stepOrder || index + 1;

  // [2] Pick the pill class for the step status
  const statusClass = STEP_STATUS_CLASSES[step.status] || STEP_STATUS_CLASS_DEFAULT;

  // [3] Highlight the row when the step failed
  const isFailed = step.status === STEP_STATUS_FAILED;
  const rowClass = isFailed ? STEP_ROW_CLASS_FAILED : STEP_ROW_CLASS;

  // [4] Build the view
  return { key: `${index}`, order, stepType: step.stepType || EMPTY_VALUE, status: step.status || EMPTY_VALUE, msLabel: formatCount(step.durationMs), detail: step.stepDetail || step.label, statusClass, rowClass };
}

// Builds the text copied by "copy ids": the conversation, user message and reply ids, one per line.
export function buildCopyIdsText(trace) {

  // [1] One line per id
  const conversationLine = `${LABELS.copyIdsConversation}${trace.conversationId}`;
  const userMessageLine = `${LABELS.copyIdsUserMessage}${trace.userMessageId}`;
  const replyLine = `${LABELS.copyIdsReply}${trace.replyMessageId}`;

  // [2] Join the lines
  return [conversationLine, userMessageLine, replyLine].join(COPY_IDS_LINE_SEPARATOR);
}

// Builds the name of a downloaded file, e.g. "request-<messageId>.json".
export function buildDownloadFileName(prefix, messageId) {

  // [1] Prefix, message id and extension
  return `${prefix}${messageId}${JSON_FILE_EXTENSION}`;
}

// Gets the text for the copy button: "Copied" after a successful copy, otherwise the original label.
export function getCopyLabel(copied) {

  // [1] Pick the label for the result
  return copied ? LABELS.copied : LABELS.copyIds;
}

// Copies text to the clipboard and answers true when it worked.
export async function copyToClipboard(text) {

  // [1] Try the modern clipboard API first
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // Clipboard API blocked - fall through to the legacy path.
  }

  // [2] Fall back to copying from a hidden text box
  try {
    const textArea = document.createElement("textarea");
    textArea.value = text;
    textArea.setAttribute("readonly", "");
    textArea.style.position = HIDDEN_ELEMENT_POSITION;
    textArea.style.opacity = HIDDEN_ELEMENT_OPACITY;
    document.body.appendChild(textArea);
    textArea.select();
    const copied = document.execCommand("copy");
    document.body.removeChild(textArea);
    return copied;
  } catch {
    return false;
  }
}

// Saves text as a file through a temporary link.
export function downloadTextFile(fileName, text) {

  // [1] Build a link that holds the text
  const link = document.createElement("a");
  link.href = `${DOWNLOAD_DATA_URL_PREFIX}${encodeURIComponent(text)}`;
  link.download = fileName;
  link.style.display = HIDDEN_ELEMENT_DISPLAY;

  // [2] Click the link, then remove it
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}
