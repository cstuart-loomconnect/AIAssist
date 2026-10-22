/*
Component Name: aiToolsWaStepType

=================================================================
=================================================================

Description: Step 1 of the workflow action wizard: what runs the action, and whether it changes data.

Step 1: Show the three ways an action can run, and which one is chosen
Step 2: Show whether the action reads or writes data
Step 3: Tell the wizard what the admin chose

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ACTION_TYPE_SCREEN_FLOW, EXECUTION_READ_ONLY, EXECUTION_WRITE, CARD_CLASS, CARD_SELECTED_CLASS, CHOICE_CLASS, CHOICE_SELECTED_CLASS, TYPE_CARDS, LABELS, NO_TEXT } from "./aiToolsWaStepTypeSettings";

// Step 1. It shows the draft and reports each choice to the wizard.
export default class AiToolsWaStepType extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: actionType and executionType are read here

  // Values the template reads
  labels = LABELS;

  get cardViews() {

    // [1] One view for each way of running, with the chosen one marked
    const cardViews = TYPE_CARDS.map((card) => ({ ...card, cardClass: card.value === this.draft.actionType ? CARD_SELECTED_CLASS : CARD_CLASS }));

    return cardViews;
  }

  get readOnlyClass() {

    // [1] Chosen when the action reads only
    const readOnlyClass = this.draft.executionType === EXECUTION_READ_ONLY ? CHOICE_SELECTED_CLASS : CHOICE_CLASS;

    return readOnlyClass;
  }

  get writeClass() {

    // [1] Chosen when the action writes
    const writeClass = this.draft.executionType === EXECUTION_WRITE ? CHOICE_SELECTED_CLASS : CHOICE_CLASS;

    return writeClass;
  }

  get isScreenFlow() {

    // [1] A screen flow is confirmed by the user finishing it
    const isScreenFlow = this.draft.actionType === ACTION_TYPE_SCREEN_FLOW;

    return isScreenFlow;
  }

  get showWriteNote() {

    // [1] Warn that a write asks first, except for a screen flow
    const showWriteNote = this.draft.executionType === EXECUTION_WRITE && !this.isScreenFlow;

    return showWriteNote;
  }

  get showScreenFlowNote() {

    // [1] Explain why a screen flow has no separate confirmation
    const showScreenFlowNote = this.isScreenFlow;

    return showScreenFlowNote;
  }

  handleTypeClick(event) {

    // [1] Nothing changes when the admin picks the type that is already chosen
    const chosenType = event.currentTarget.dataset.value;
    if (chosenType === this.draft.actionType) return;

    // [2] A new type starts again from the next step, because flows and classes are different lists
    const changes = { actionType: chosenType, sourceName: NO_TEXT, sourceLabel: NO_TEXT, flowVersion: null, inputs: [], outputs: [] };
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }

  handleExecutionClick(event) {

    // [1] Report the choice, and make a write confirm
    const executionType = event.currentTarget.dataset.value;
    const requiresConfirmation = executionType === EXECUTION_WRITE ? true : this.draft.requiresConfirmation;
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { executionType, requiresConfirmation } } }));
  }
}
