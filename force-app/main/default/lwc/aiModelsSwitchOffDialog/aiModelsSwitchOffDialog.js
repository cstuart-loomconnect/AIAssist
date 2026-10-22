/*
Component Name: aiModelsSwitchOffDialog

=================================================================
=================================================================

Description: The dialog that asks before a model is switched off and lets the admin pick where each active agent moves to.

Step 1: Show the active agents that use the model, each with a choice of where it moves to
Step 2: Block the switch off when there is no other active model to move to
Step 3: Tell the tab whether the admin cancelled or confirmed, with the moves

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_CANCEL, EVENT_CONFIRM, NO_TEXT } from "./aiModelsSwitchOffDialogSettings";
import { buildMoveOptions, buildAgentViews, buildMessageParts, buildConfirmLabel, buildMoves } from "./aiModelsSwitchOffDialogHelper";

// The switch off dialog.
export default class AiModelsSwitchOffDialog extends LightningElement {

  // Values passed in by the parent component
  @api modelName = NO_TEXT; // The model being switched off
  @api options = null; // SwitchOffOptions from AIModelsController.getSwitchOffOptions
  @api isSaving = false; // True while the switch off runs, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last failed switch off, or blank

  // Values the template reads
  labels = LABELS;

  // State of the dialog: the model each agent moves to, by agent id. An agent with no entry moves to the first model.
  choices = {};

  get messageParts() {

    // [1] Hand the work to the helper
    const messageParts = buildMessageParts(this.options, this.modelName);

    return messageParts;
  }

  get hasAgents() {

    // [1] The table shows only when an active agent uses the model
    const hasAgents = this.messageParts.agentCount > 0;

    return hasAgents;
  }

  get agentViews() {

    // [1] Hand the work to the helper
    const agentViews = buildAgentViews(this.options, this.choices);

    return agentViews;
  }

  get hasNoOtherModel() {

    // [1] Agents cannot move when no other model is active
    const moveOptions = buildMoveOptions(this.options);
    const hasNoOtherModel = this.hasAgents && moveOptions.length === 0;

    return hasNoOtherModel;
  }

  get confirmLabel() {

    // [1] Hand the work to the helper
    const confirmLabel = buildConfirmLabel(this.messageParts.agentCount, this.isSaving);

    return confirmLabel;
  }

  get isConfirmDisabled() {

    // [1] Nothing happens twice, and agents with nowhere to go block the switch off
    const isConfirmDisabled = this.isSaving || this.hasNoOtherModel;

    return isConfirmDisabled;
  }

  get hasErrorMessage() {

    // [1] Show the message box only when there is a message
    const hasErrorMessage = Boolean(this.errorMessage);

    return hasErrorMessage;
  }

  // Event handlers
  handleMoveChange(event) {

    // [1] Keep the model chosen for the agent
    const agentId = event.target.dataset.agentId;
    this.choices = { ...this.choices, [agentId]: event.target.value };
  }

  handleCancel() {

    // [1] Tell the tab the admin changed their mind
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }

  handleConfirm() {

    // [1] Tell the tab to move the agents and switch the model off
    const moves = buildMoves(this.options, this.choices);
    this.dispatchEvent(new CustomEvent(EVENT_CONFIRM, { detail: { moves } }));
  }
}
