/*
Component Name: aiChatTerms

=================================================================
=================================================================

Description: Shows the first-run terms and lets the user agree to them before they use AI Assist.

Step 1: The parent (aiAssistChat) passes in the policy link, the saving flag and any error message
Step 2: The user ticks the checkbox to say they have read the policy
Step 3: The "Agree and continue" button turns on once the box is ticked and nothing is saving
Step 4: On click the component sends the agree event so the parent can record the acknowledgment

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, AGREE_EVENT_NAME } from "./aiChatTermsSettings";

// First-run terms. The checkbox must be ticked before "Agree and continue" - the parent records the acknowledgment.
export default class AiChatTerms extends LightningElement {

  // Values passed in by the parent component
  @api policyUrl; // Link to the AI usage policy. When empty the policy name shows as plain text
  @api isSaving = false; // True while the parent is saving the acknowledgment
  @api errorMessage; // Text shown under the button when saving failed

  // Values the template reads
  labels = LABELS;

  // State of the component
  isAgreed = false;

  // True when the Agree button must be switched off.
  get isAgreeDisabled() {

    // [1] The button needs a ticked box and nothing already saving
    const isNotAgreed = !this.isAgreed;
    const isBusy = this.isSaving;

    return isNotAgreed || isBusy;
  }

  // Remembers whether the checkbox is ticked.
  handleAgreeChange(event) {

    // [1] Read the box state from the checkbox that sent the event
    const isChecked = event.target.checked;

    // [2] Keep it so the button can switch on or off
    this.isAgreed = isChecked;
  }

  // Tells the parent the user has agreed, but only when the box is ticked.
  handleAgree() {

    // [1] Do nothing until the box is ticked
    if (!this.isAgreed) {
      return;
    }

    // [2] Tell the parent
    const agreeEvent = new CustomEvent(AGREE_EVENT_NAME);
    this.dispatchEvent(agreeEvent);
  }
}
