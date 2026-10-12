/*
Component Name: aiChatSaveDialog

=================================================================
=================================================================

Description: The dialog that confirms saving an AI reply to its record as a note or a task, with the text the user can still change.

Step 1: Show what will be created and the reply text in an editable box
Step 2: Keep track of the text as the user edits it
Step 3: Tell the parent the text to save when the user presses the save button
Step 4: Tell the parent when the user cancels, or presses Escape

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, TARGET_COPY, TARGET_NOTE, KEY_ESCAPE, TEXT_SELECTOR, EVENT_SAVE, EVENT_CANCEL } from "./aiChatSaveDialogSettings";

// aiAssistChat opens this dialog when the user picks a place in the reply's Save to record menu, and makes the Apex call itself.
export default class AiChatSaveDialog extends LightningElement {

  // Values passed in by the parent component
  @api target = TARGET_NOTE; // Where the reply is saved: 'NOTE' | 'TASK'
  @api text = ""; // The reply text to start from
  @api isSaving = false; // true turns the buttons off while the save is running
  @api errorMessage; // The reason the last save failed. When empty, nothing is shown.

  // Values the template reads
  labels = LABELS;

  // Tracked state
  draftText = ""; // The text as the user has edited it
  hasFocused = false; // true once the text box has been given focus

  // Starts the text box with the reply text.
  connectedCallback() {

    // [1] Copy what the parent passed in, because the user edits the copy
    this.draftText = this.text || "";
  }

  // Puts the cursor in the text box the first time the dialog draws.
  renderedCallback() {

    // [1] Only once
    if (this.hasFocused) return;

    // [2] Focus the text box
    const textBox = this.template.querySelector(TEXT_SELECTOR);

    if (textBox) {
      textBox.focus();
      this.hasFocused = true;
    }
  }

  // The wording for the place the reply is saved to.
  get copy() {

    // [1] Find the wording, or the note's wording for a target we do not know
    const copy = TARGET_COPY[this.target] || TARGET_COPY[TARGET_NOTE];

    return copy;
  }

  // The dialog heading.
  get heading() {

    return this.copy.heading;
  }

  // The line under the heading that says what will be created.
  get hint() {

    return this.copy.hint;
  }

  // The text of the save button.
  get saveLabel() {

    return this.copy.saveLabel;
  }

  // True when the save button is switched off: while saving, or when there is no text.
  get isSaveDisabled() {

    // [1] There is nothing to save when the text is blank
    const isBlank = this.draftText.trim().length === 0;

    return this.isSaving || isBlank;
  }

  // True when there is an error to show.
  get hasError() {

    return !!this.errorMessage;
  }

  // Remembers the text the user typed.
  handleInput(event) {

    // [1] Read the text from the box
    this.draftText = event.target.value;
  }

  // Tells the parent to save the text.
  handleSave() {

    // [1] Do nothing when the button is off
    if (this.isSaveDisabled) return;

    // [2] Send the text the user confirmed
    const saveEvent = new CustomEvent(EVENT_SAVE, { detail: { text: this.draftText } });
    this.dispatchEvent(saveEvent);
  }

  // Tells the parent the user does not want to save.
  handleCancel() {

    // [1] Do nothing while a save is running
    if (this.isSaving) return;

    // [2] Send the cancel event
    const cancelEvent = new CustomEvent(EVENT_CANCEL);
    this.dispatchEvent(cancelEvent);
  }

  // Cancels when the user presses Escape.
  handleKeyDown(event) {

    // [1] Cancel on Escape only
    if (event.key === KEY_ESCAPE) this.handleCancel();
  }
}
