/*
Component Name: aiChatDebugTrace

=================================================================
=================================================================

Description: Debug mode's request trace for one AI reply (AIUsagePolicy__c.DebugModeEnabled__c).

Step 1: Take the trace (or an error message) that aiAssistChat loaded through AIChatController.getDebugTrace
Step 2: Show the status, model, tokens, steps and ids, leaving out any row the trace has no value for
Step 3: Let the user copy the ids or download request.json and response.json
Step 4: Tell the parent when the user closes the trace

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, STATUS_CLASS_OK, STATUS_CLASS_ERROR, REQUEST_FILE_PREFIX, RESPONSE_FILE_PREFIX, EVENT_CLOSE_TRACE } from "./aiChatDebugTraceSettings";
import { copyToClipboard, downloadTextFile, formatMilliseconds, formatLabel, isMissing, buildTokensLabel, buildModelLabel, buildStepView, buildCopyIdsText, buildDownloadFileName, getCopyLabel } from "./aiChatDebugTraceHelper";

// "close trace" is handed back up as an event: aiAssistChat owns the Apex call and the trace state.
// requestJson, responseJson and sentPreviewText only carry a value for a reply captured with debug mode already on.
// An older reply, or one for a non-debug user, has none of it and the panel just leaves that row out.
export default class AiChatDebugTrace extends LightningElement {

  // Values passed in by the parent component
  @api trace; // The trace for one reply. Empty while it is still loading.
  @api errorMessage; // Text shown when the trace could not be loaded

  // Values the template reads
  labels = LABELS;
  copyLabel = LABELS.copyIds;

  // The status pill text: 200 or ERR.
  get statusLabel() {

    // [1] Pick the label for the result
    return this.trace.isSuccess ? LABELS.statusOk : LABELS.statusError;
  }

  // The status pill class: green or red.
  get statusClass() {

    // [1] Pick the class for the result
    return this.trace.isSuccess ? STATUS_CLASS_OK : STATUS_CLASS_ERROR;
  }

  // How long the request took, e.g. "2.84s".
  get durationLabel() {

    // [1] Hand the work to the helper
    return formatMilliseconds(this.trace.durationMs);
  }

  // Provider, model configuration and model on one line.
  get modelLabel() {

    // [1] Hand the work to the helper
    return buildModelLabel(this.trace);
  }

  // Tokens sent and received, e.g. "1,240 / 380".
  get tokensLabel() {

    // [1] Hand the work to the helper
    return buildTokensLabel(this.trace.promptTokens, this.trace.replyTokens);
  }

  // How many fields were masked as PII, e.g. "3 fields".
  get piiLabel() {

    // [1] Hand the work to the helper
    return formatLabel(LABELS.piiFieldsCount, this.trace.piiFieldsMasked);
  }

  // True when the trace says how many tool iterations were used.
  get hasIterations() {

    // [1] Check the value is set
    return !isMissing(this.trace.toolCallingIterationsUsed);
  }

  // Tool iterations used out of the maximum, e.g. "2 of 5".
  get iterationsLabel() {

    // [1] Hand the work to the helper
    return formatLabel(LABELS.iterationsOf, this.trace.toolCallingIterationsUsed, this.trace.toolCallingIterationsMax);
  }

  // True when the trace says which attempt this was.
  get hasAttempts() {

    // [1] Check the value is set
    return !isMissing(this.trace.attemptNumber);
  }

  // True when the trace has at least one step.
  get hasSteps() {

    // [1] The trace may have no steps at all
    const steps = this.trace.steps;
    return !!steps && steps.length > 0;
  }

  // The steps turned into what the table needs.
  get stepViews() {

    // [1] Build one view per step
    return this.trace.steps.map(buildStepView);
  }

  // True when the trace carries the preview of what was sent.
  get hasSentPreview() {

    // [1] An empty preview counts as none
    return !!this.trace.sentPreviewText;
  }

  // True when the trace carries the request JSON.
  get hasRequestJson() {

    // [1] An empty request counts as none
    return !!this.trace.requestJson;
  }

  // True when the trace carries the response JSON.
  get hasResponseJson() {

    // [1] An empty response counts as none
    return !!this.trace.responseJson;
  }

  // Copies the conversation, user message and reply ids, then shows "Copied" on the button.
  async handleCopyIds() {

    // [1] Copy the ids
    const idsText = buildCopyIdsText(this.trace);
    const copied = await copyToClipboard(idsText);

    // [2] Show the result on the button
    this.copyLabel = getCopyLabel(copied);
  }

  // Downloads the request as request-<replyMessageId>.json.
  handleDownloadRequest() {

    // [1] Build the file name and save the file
    const fileName = buildDownloadFileName(REQUEST_FILE_PREFIX, this.trace.replyMessageId);
    downloadTextFile(fileName, this.trace.requestJson);
  }

  // Downloads the response as response-<replyMessageId>.json.
  handleDownloadResponse() {

    // [1] Build the file name and save the file
    const fileName = buildDownloadFileName(RESPONSE_FILE_PREFIX, this.trace.replyMessageId);
    downloadTextFile(fileName, this.trace.responseJson);
  }

  // Tells the parent the user closed the trace.
  handleCloseTrace() {

    // [1] Send the event
    this.dispatchEvent(new CustomEvent(EVENT_CLOSE_TRACE));
  }
}
