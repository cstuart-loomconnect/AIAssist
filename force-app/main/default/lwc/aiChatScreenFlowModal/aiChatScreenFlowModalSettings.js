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

// The statuses lightning-flow reports in its statuschange event.
export const FLOW_STATUS_FINISHED = "FINISHED";
export const FLOW_STATUS_FINISHED_SCREEN = "FINISHED_SCREEN";
export const FLOW_STATUS_ERROR = "ERROR";

// How this modal reports the end of the flow to aiAssistChat, in the outcome property of the outcome event.
export const FLOW_OUTCOME_FINISHED = "FINISHED";
export const FLOW_OUTCOME_ERROR = "ERROR";

// The name of the event sent to the parent.
export const EVENT_OUTCOME = "outcome";
