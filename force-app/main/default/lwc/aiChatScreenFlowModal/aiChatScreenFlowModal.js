/*
Component Name: aiChatScreenFlowModal

=================================================================
=================================================================

Description: Runs a Screen Flow action in a modal over the chat window and reports how it ended.

Step 1: The parent (aiAssistChat) opens the modal with the label, the flow API name and the flow input variables
Step 2: lightning-flow runs the flow as the signed-in user, so the user's own permissions apply
Step 3: When the flow finishes or fails, the modal sends an outcome event to the parent
Step 4: A flow without a finish screen closes the modal itself; one with a finish screen stays open until the user closes it

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import LightningModal from "lightning/modal";
import { api } from "lwc";
import { FLOW_STATUS_FINISHED, FLOW_STATUS_FINISHED_SCREEN, FLOW_STATUS_ERROR, FLOW_OUTCOME_FINISHED, FLOW_OUTCOME_ERROR, EVENT_OUTCOME } from "./aiChatScreenFlowModalSettings";

// Shows a Screen Flow action in a modal over the chat window, because the window is too narrow for a flow. lightning-flow runs the flow as the signed-in user, so the user's own permissions apply. Each outcome is reported as an "outcome" event (FINISHED or ERROR) for aiAssistChat to record; closing the modal at any time resolves the open() promise.
export default class AiChatScreenFlowModal extends LightningModal {

  // Values passed in by the parent when it opens the modal
  @api label; // Title in the modal header
  @api flowApiName; // API name of the Screen Flow to run
  @api inputVariables = []; // [{ name, type, value }] handed to the flow

  // Reacts to each status change from lightning-flow and reports the end of the flow to the parent.
  handleStatusChange(event) {

    // [1] Read the status lightning-flow reported
    const status = event.detail.status;
    const isFinished = status === FLOW_STATUS_FINISHED;
    const isFinishedScreen = status === FLOW_STATUS_FINISHED_SCREEN;
    const isError = status === FLOW_STATUS_ERROR;

    // [2] The flow ended well: tell the parent
    if (isFinished || isFinishedScreen) {
      this.sendOutcome(FLOW_OUTCOME_FINISHED);

      // A flow with a finish screen stays open so the user can read it; one without closes itself.
      if (isFinished) this.close();

      return;
    }

    // [3] The flow failed: tell the parent
    if (isError) this.sendOutcome(FLOW_OUTCOME_ERROR);
  }

  // Sends the outcome event to the parent with the way the flow ended.
  sendOutcome(outcome) {

    // [1] Build the event detail and send the event
    const detail = { outcome };

    this.dispatchEvent(new CustomEvent(EVENT_OUTCOME, { detail }));
  }
}
