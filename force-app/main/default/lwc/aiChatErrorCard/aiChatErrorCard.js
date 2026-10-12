/*
Component Name: aiChatErrorCard

=================================================================
=================================================================

Description: The card shown when an AI reply failed, with a Try again button.

Step 1: Show the failure heading and message
Step 2: Show the debug detail when the parent passes one
Step 3: Tell the parent when the user clicks Try again
Step 4: Show the log reference and any retry error

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_RETRY } from "./aiChatErrorCardSettings";

// A reply that failed (AIMessageReadyEvent__e with IsSuccess__c false). Try again re-runs the newest message.
export default class AiChatErrorCard extends LightningElement {

  // Values passed in by the parent component
  @api reference; // Log reference the user can quote to an admin. When empty, it is hidden.
  @api debugDetail; // Extra detail for debug users. When empty, it is hidden.
  @api isRetrying = false; // true turns the Try again button off while a retry is running
  @api retryError; // Text shown under the card when the last retry failed. When empty, it is hidden.

  // Values the template reads
  labels = LABELS;

  // Tells the parent the user wants to try again.
  handleRetry() {

    // [1] Send the retry event
    const retryEvent = new CustomEvent(EVENT_RETRY);
    this.dispatchEvent(retryEvent);
  }
}
