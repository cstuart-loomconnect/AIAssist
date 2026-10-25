/*
Component Name: aiChatDebugTrace

=================================================================
=================================================================

Description: Settings for aiChatDebugTrace: label text, class names, file names and the other fixed values.

Step 1: Hold the label text the template shows
Step 2: Hold the class names for the status, the step rows and the step pills
Step 3: Hold the separators, file names and event name the controller and helper use

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Shown in place of a value that is missing
export const EMPTY_VALUE = "—";

// Statuses a step can have, each with the pill that shows it. Anything else (Blocked, Cancelled) reads as a warning.
export const STEP_STATUS_FAILED = "Failed";
export const STEP_STATUS_CLASSES = { Success: "pill pill_ok", Failed: "pill pill_error" };
export const STEP_STATUS_CLASS_DEFAULT = "pill pill_warn";

// Class names for a row in the steps table
export const STEP_ROW_CLASS = "step";
export const STEP_ROW_CLASS_FAILED = "step step_failed";

// Class names for the status pill in the trace header
export const STATUS_CLASS_OK = "status status_ok slds-m-left_x-small";
export const STATUS_CLASS_ERROR = "status status_error slds-m-left_x-small";

// Duration display: 1000 milliseconds is one second, shown with two decimals
export const MILLISECONDS_PER_SECOND = 1000;
export const SECONDS_DECIMAL_PLACES = 2;

// Separators used when joining values into one line of text
export const MODEL_LABEL_SEPARATOR = " · ";
export const TOKENS_SEPARATOR = " / ";
export const COPY_IDS_LINE_SEPARATOR = "\n";

// Downloaded request and response files
export const REQUEST_FILE_PREFIX = "request-";
export const RESPONSE_FILE_PREFIX = "response-";
export const JSON_FILE_EXTENSION = ".json";
export const DOWNLOAD_DATA_URL_PREFIX = "data:text/plain;charset=utf-8,";

// Hidden helper elements used to copy and download
export const HIDDEN_ELEMENT_POSITION = "fixed";
export const HIDDEN_ELEMENT_OPACITY = "0";
export const HIDDEN_ELEMENT_DISPLAY = "none";

// Event sent to the parent (aiAssistChat), which owns the trace state
export const EVENT_CLOSE_TRACE = "closetrace";

// Label text shown in the template
export const LABELS = {
  copied: "Copied",
  requestTrace: "Request trace",
  modelConfig: "model config",
  tokensInOut: "tokens in / out",
  toolCalls: "tool calls",
  toolIterations: "tool iterations",
  attempts: "attempts",
  piiMasked: "pii masked",
  stepOrder: "#",
  stepType: "step type",
  stepStatus: "status",
  stepMilliseconds: "ms",
  stepDetail: "step detail",
  sentPreviewPrefix: "sent:",
  conversation: "conversation",
  requestJson: "request.json",
  responseJson: "response.json",
  copyIds: "copy ids",
  closeTrace: "close trace",
  loading: "Loading…",
  statusOk: "200",
  statusError: "ERR",
  piiFieldsCount: "{0} fields",
  iterationsOf: "{0} of {1}",
  copyIdsConversation: "conversation: ",
  copyIdsUserMessage: "userMessage: ",
  copyIdsReply: "reply: "
};
