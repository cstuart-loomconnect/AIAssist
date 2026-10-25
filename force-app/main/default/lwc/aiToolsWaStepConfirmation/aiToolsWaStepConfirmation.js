/*
Component Name: aiToolsWaStepConfirmation

=================================================================
=================================================================

Description: Step 4 of the workflow action wizard: whether the user confirms, the message, and which inputs are shown with it.

Step 1: Show whether confirmation is required, locked on for a write
Step 2: Let the admin write the message and choose which inputs the user sees
Step 3: Show a preview of the card the user will see in the chat
Step 4: Tell the wizard what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ACTION_TYPE_SCREEN_FLOW, EXECUTION_WRITE, LABELS } from "./aiToolsWaStepConfirmationSettings";
import { buildChipViews, toggleConfirmInput, buildPreviewRows, buildUserRows } from "./aiToolsWaStepConfirmationHelper";

// Step 4. It shows the confirmation of the draft and reports every change to the wizard.
export default class AiToolsWaStepConfirmation extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: requiresConfirmation, confirmationMessage, inputs, executionType and actionType are read here

  // Values the template reads
  labels = LABELS;

  get isScreenFlow() {

    // [1] A screen flow is confirmed by the user pressing Finish
    const isScreenFlow = this.draft.actionType === ACTION_TYPE_SCREEN_FLOW;

    return isScreenFlow;
  }

  get isWrite() {

    // [1] A write always confirms, unless it is a screen flow
    const isWrite = this.draft.executionType === EXECUTION_WRITE;

    return isWrite;
  }

  get isLocked() {

    // [1] The switch cannot be turned off for a write
    const isLocked = this.isWrite && !this.isScreenFlow;

    return isLocked;
  }

  get isRequired() {

    // [1] On when locked, otherwise as the admin chose
    const isRequired = this.isLocked || this.draft.requiresConfirmation === true;

    return isRequired;
  }

  get showConfirmationFields() {

    // [1] The message and the chips only matter when the user confirms
    const showConfirmationFields = this.isRequired && !this.isScreenFlow;

    return showConfirmationFields;
  }

  get chipViews() {

    // [1] Hand the work to the helper
    const chipViews = buildChipViews(this.draft.inputs);

    return chipViews;
  }

  get hasChips() {

    // [1] There are chips when there is something to choose from
    const hasChips = this.chipViews.length > 0;

    return hasChips;
  }

  get previewRows() {

    // [1] The chosen agent inputs, then the user's own
    const previewRows = [...buildPreviewRows(this.draft.inputs), ...buildUserRows(this.draft.inputs)];

    return previewRows;
  }

  get previewHead() {

    // [1] The action's name, then that it needs the user's OK
    const name = this.draft.actionName || this.draft.sourceLabel;
    const previewHead = name + LABELS.needsYourOk;

    return previewHead;
  }

  // Event handlers
  handleRequiredChange(event) {

    // [1] Keep the admin's choice
    this.reportChanges({ requiresConfirmation: event.target.checked });
  }

  handleMessageChange(event) {

    // [1] Keep the message
    this.reportChanges({ confirmationMessage: event.target.value });
  }

  handleChipClick(event) {

    // [1] Flip whether the input is shown to the user
    const index = Number(event.currentTarget.dataset.index);
    this.reportChanges({ inputs: toggleConfirmInput(this.draft.inputs, index) });
  }

  // Private methods
  reportChanges(changes) {

    // [1] Tell the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
