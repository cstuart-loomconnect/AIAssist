/*
Component Name: aiChatFeedbackPanel

=================================================================
=================================================================

Description: The "What went wrong?" panel shown after a thumbs down, with a reason and an optional comment.

Step 1: Show the reasons and keep track of the one the user picked
Step 2: Keep track of the comment the user types
Step 3: Tell the parent when the user skips
Step 4: Tell the parent the reason and comment when the user sends

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, FEEDBACK_REASONS, EVENT_SKIP, EVENT_SUBMIT, ARIA_PRESSED_TRUE, ARIA_PRESSED_FALSE } from "./aiChatFeedbackPanelSettings";

// The rating itself is already saved when this panel opens; the panel only adds the detail.
export default class AiChatFeedbackPanel extends LightningElement {

  // Values passed in by the parent component
  @api isSubmitting = false; // true turns the Skip and Send buttons off while the feedback is being saved

  // Values the template reads
  labels = LABELS;

  // Tracked state
  selectedReason = FEEDBACK_REASONS[0]; // The reason the user picked
  comment = ""; // The text the user typed

  // The reasons turned into what the template needs: the text and whether it is the selected one.
  get reasonViews() {

    // [1] Build one view per reason
    const reasonViews = [];

    FEEDBACK_REASONS.forEach((value) => {
      const isSelected = value === this.selectedReason;
      const pressed = isSelected ? ARIA_PRESSED_TRUE : ARIA_PRESSED_FALSE;
      reasonViews.push({ value, pressed });
    });

    return reasonViews;
  }

  // Remembers the reason the user clicked.
  handleReason(event) {

    // [1] Read the reason from the button that was clicked
    this.selectedReason = event.currentTarget.dataset.value;
  }

  // Remembers the comment the user typed.
  handleComment(event) {

    // [1] Read the text from the box
    this.comment = event.target.value;
  }

  // Tells the parent the user does not want to leave feedback.
  handleSkip() {

    // [1] Send the skip event
    const skipEvent = new CustomEvent(EVENT_SKIP);
    this.dispatchEvent(skipEvent);
  }

  // Tells the parent the reason and comment the user chose.
  handleSubmit() {

    // [1] Gather what the user entered
    const detail = { reason: this.selectedReason, comment: this.comment };

    // [2] Send it to the parent
    const submitEvent = new CustomEvent(EVENT_SUBMIT, { detail });
    this.dispatchEvent(submitEvent);
  }
}
