/*
Component Name: aiPoliciesDeleteDialog

=================================================================
=================================================================

Description: The delete dialog: asks where the people of a policy move to before it is deleted.

Step 1: Ask Apex how many people the policy covers and which policies they can move to
Step 2: Let the admin choose the default policy or another policy, and refuse to delete the default policy
Step 3: Tell the tab whether the admin cancelled or confirmed, with the policy to move to

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import getDeleteOptions from "@salesforce/apex/AIPoliciesController.getDeleteOptions";
import { MOVE_TO_DEFAULT, MOVE_TO_OTHER, EVENT_CANCEL, EVENT_CONFIRM, NO_TEXT, LABELS } from "./aiPoliciesDeleteDialogSettings";
import { buildMessageParts, buildPolicyChoices, getMoveToPolicyId, isMoveChosen, formatErrorMessage } from "./aiPoliciesDeleteDialogHelper";

// The delete dialog.
export default class AiPoliciesDeleteDialog extends LightningElement {

  // Values passed in by the parent component
  @api policyId; // The policy being deleted
  @api policyName = NO_TEXT; // The name of that policy
  @api isSaving = false; // True while the delete runs, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last failed delete, or blank

  // Values the template reads
  labels = LABELS;
  defaultMode = MOVE_TO_DEFAULT;
  otherMode = MOVE_TO_OTHER;

  // State of the dialog
  options = null;
  isLoading = true;
  loadErrorMessage = NO_TEXT;
  moveMode = MOVE_TO_DEFAULT;
  otherPolicyId = null;

  // Lifecycle methods
  connectedCallback() {

    // [1] Ask who the policy covers and where they can move
    this.loadOptions();
  }

  get title() {

    // [1] The title names the policy
    const title = LABELS.titlePrefix + this.policyName + LABELS.titleSuffix;

    return title;
  }

  get messageParts() {

    // [1] Hand the work to the helper
    const messageParts = buildMessageParts(this.options, this.policyName);

    return messageParts;
  }

  get isDefaultPolicy() {

    // [1] The default policy cannot be deleted
    const isDefaultPolicy = Boolean(this.options) && this.options.isDefault === true;

    return isDefaultPolicy;
  }

  get showChoices() {

    // [1] The choices show when there are people to move and the policy can be deleted
    const showChoices = Boolean(this.options) && this.messageParts.hasPeople && !this.isDefaultPolicy;

    return showChoices;
  }

  get hasDefaultPolicy() {

    // [1] The first choice needs a default policy to move to
    const hasDefaultPolicy = Boolean(this.options) && Boolean(this.options.defaultPolicyId);

    return hasDefaultPolicy;
  }

  get defaultChoiceLabel() {

    // [1] The first choice names the default policy
    const name = this.options && this.options.defaultPolicyName ? this.options.defaultPolicyName : NO_TEXT;
    const defaultChoiceLabel = LABELS.moveToDefaultPrefix + name + LABELS.moveToDefaultSuffix;

    return defaultChoiceLabel;
  }

  get isDefaultMode() {

    // [1] The first choice is picked
    const isDefaultMode = this.moveMode === MOVE_TO_DEFAULT;

    return isDefaultMode;
  }

  get isOtherMode() {

    // [1] The second choice is picked
    const isOtherMode = this.moveMode === MOVE_TO_OTHER;

    return isOtherMode;
  }

  get policyChoices() {

    // [1] Hand the work to the helper
    const policyChoices = buildPolicyChoices(this.options, this.otherPolicyId);

    return policyChoices;
  }

  get hasNoOtherPolicy() {

    // [1] People cannot move when no other policy exists
    const hasNoOtherPolicy = this.showChoices && !this.hasDefaultPolicy && this.policyChoices.length === 0;

    return hasNoOtherPolicy;
  }

  get shownError() {

    // [1] A problem loading comes before an error from the last delete
    const shownError = this.loadErrorMessage || this.errorMessage;

    return shownError;
  }

  get hasError() {

    // [1] A message means there is an error to show
    const hasError = Boolean(this.shownError);

    return hasError;
  }

  get confirmLabel() {

    // [1] The button names what it does
    const hasPeople = this.messageParts.hasPeople;
    const idleLabel = hasPeople ? LABELS.moveAndDelete : LABELS.delete;
    const confirmLabel = this.isSaving ? LABELS.saving : idleLabel;

    return confirmLabel;
  }

  get isConfirmDisabled() {

    // [1] Nothing happens twice, the default policy stays, and the people need somewhere to go
    const isMoveReady = isMoveChosen(this.options, this.moveMode, this.otherPolicyId);
    const isConfirmDisabled = this.isSaving || this.isLoading || this.isDefaultPolicy || !isMoveReady;

    return isConfirmDisabled;
  }

  // Event handlers
  handleModeChange(event) {

    // [1] Keep the way the admin chose
    this.moveMode = event.target.value;
  }

  handleOtherPolicyChange(event) {

    // [1] Keep the policy the admin chose
    this.otherPolicyId = event.target.value;
  }

  handleCancel() {

    // [1] Tell the tab the admin changed their mind
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }

  handleConfirm() {

    // [1] Tell the tab to move the people and delete the policy
    const moveToPolicyId = getMoveToPolicyId(this.options, this.moveMode, this.otherPolicyId);
    this.dispatchEvent(new CustomEvent(EVENT_CONFIRM, { detail: { moveToPolicyId } }));
  }

  // Private methods
  async loadOptions() {

    try {

      // [1] Read who the policy covers and where they can move
      this.options = await getDeleteOptions({ policyId: this.policyId });

      // [2] Without a default policy to move to, the second choice is the only one
      if (!this.options.defaultPolicyId) this.moveMode = MOVE_TO_OTHER;

    } catch (error) {

      // [3] Show the reason
      this.loadErrorMessage = formatErrorMessage(error);

    } finally {

      this.isLoading = false;
    }
  }
}
