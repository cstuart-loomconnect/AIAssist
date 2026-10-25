/*
Component Name: aiPromptTemplatesArchiveDialog

=================================================================
=================================================================

Description: The dialog that asks before a template is archived and lets the admin pick where each agent moves to.

Step 1: Show the agents that use the template, each with a choice of where it moves to
Step 2: Block the archive of the default template and say why
Step 3: Tell the parent whether the admin cancelled or confirmed, with the moves

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiPromptTemplatesArchiveDialogSettings";
import { buildMoveOptions, buildAgentViews, buildMessageParts, buildConfirmLabel, buildMoves } from "./aiPromptTemplatesArchiveDialogHelper";

// The archive dialog.
export default class AiPromptTemplatesArchiveDialog extends LightningElement {

  // Values passed in by the parent component
  @api templateId = null; // The template being archived
  @api templateName = "";
  @api options = null; // ArchiveOptions from AIPromptTemplatesController.getArchiveOptions
  @api isSaving = false; // True while the archive runs, so the buttons wait

  // Values the template reads
  labels = LABELS;

  // State of the dialog: the template each agent moves to, by agent id. A blank value means the default.
  choices = {};

  get title() {

    // [1] Ask about this template
    const title = 'Archive "' + this.templateName + '"?';

    return title;
  }

  get messageParts() {

    // [1] Hand the work to the helper
    const messageParts = buildMessageParts(this.options, this.templateName);

    return messageParts;
  }

  get hasAgents() {

    // [1] The table shows only when an agent uses the template
    const hasAgents = this.messageParts.agentCount > 0;

    return hasAgents;
  }

  get isDefault() {

    // [1] The default template cannot be archived
    const isDefault = Boolean(this.options && this.options.isDefault);

    return isDefault;
  }

  get agentViews() {

    // [1] Hand the work to the helper
    const agentViews = buildAgentViews(this.options, this.choices);

    return agentViews;
  }

  get moveOptions() {

    // [1] Hand the work to the helper
    const moveOptions = buildMoveOptions(this.options, this.templateId);

    return moveOptions;
  }

  get confirmLabel() {

    // [1] Hand the work to the helper
    const confirmLabel = buildConfirmLabel(this.messageParts.agentCount);

    return confirmLabel;
  }

  get isConfirmDisabled() {

    // [1] The default cannot be archived, and nothing happens twice
    const isConfirmDisabled = this.isDefault || this.isSaving;

    return isConfirmDisabled;
  }

  get noteClass() {

    // [1] The note is red when it is the reason the archive is blocked
    const noteClass = this.isDefault ? "aipt-note aipt-note_blocked slds-m-top_small slds-p-around_small" : "aipt-note slds-m-top_small";

    return noteClass;
  }

  // Event handlers
  handleMoveChange(event) {

    // [1] Remember where this agent goes
    const agentId = event.target.dataset.agentId;
    this.choices = { ...this.choices, [agentId]: event.detail.value };
  }

  handleCancel() {

    // [1] Tell the parent to close the dialog
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleConfirm() {

    // [1] Tell the parent to archive, with where each agent goes
    const moves = buildMoves(this.options, this.choices);
    this.dispatchEvent(new CustomEvent("confirm", { detail: { moves } }));
  }
}
