/*
Component Name: aiChatSuggestedAction

=================================================================
=================================================================

Description: A Workflow Action the AI suggested on its reply. The AI can only suggest; the user runs it here.

Step 1: Show the suggested action as a card or as inline buttons
Step 2: Let the user run it, edit its inputs first, or dismiss it
Step 3: Ask for confirmation first when the action requires it
Step 4: Tell the parent to run, decline or dismiss (aiAssistChat runs it through AIChatController.runSuggestedAction)
Step 5: Show the outcome the parent hands back in state

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, ACTIONS_DISPLAY_INLINE_BUTTONS, DEFAULT_DISPLAY, ACTION_STATUS, MODE, INPUT_TYPE, CONTAINER_CLASS, EVENTS, EDITABLE_INPUT_SELECTOR } from "./aiChatSuggestedActionSettings";
import { getStatus, hasInputFields, buildFieldViews, isEveryInputValid } from "./aiChatSuggestedActionHelper";

export default class AiChatSuggestedAction extends LightningElement {

  // Values passed in by the parent component
  @api action; // { name, description, inputFields, requiresConfirmation, confirmationMessage, hasRun }
  @api display = DEFAULT_DISPLAY; // 'Cards' | 'Inline Buttons'
  @api state = { status: ACTION_STATUS.IDLE }; // { status: 'idle' | 'running' | 'done' | 'failed' | 'dismissed', message }

  // Values the template reads
  labels = LABELS;

  // What the user is doing now, and the values they typed
  mode = MODE.BUTTONS; // 'buttons' | 'editing' | 'confirming'
  values = {};
  pendingInputs = null; // the inputs waiting for the user to confirm

  // The status to show, from the action and the state.
  get status() {

    // [1] Hand the work to the helper
    return getStatus(this.action, this.state);
  }

  // The component shows nothing when there is no action or it was dismissed.
  get isVisible() {

    // [1] There must be an action
    const hasAction = Boolean(this.action);

    // [2] It must not have been dismissed
    const isDismissed = this.status === ACTION_STATUS.DISMISSED;

    return hasAction && !isDismissed;
  }

  // Cards are the default look; only Inline Buttons switches it off.
  get isCard() {
    return this.display !== ACTIONS_DISPLAY_INLINE_BUTTONS;
  }

  get isInline() {
    return !this.isCard;
  }

  get containerClass() {
    return this.isCard ? CONTAINER_CLASS.CARD : CONTAINER_CLASS.INLINE;
  }

  get isRunning() {
    return this.status === ACTION_STATUS.RUNNING;
  }

  get isDone() {
    return this.status === ACTION_STATUS.DONE;
  }

  get isFailed() {
    return this.status === ACTION_STATUS.FAILED;
  }

  get isEditing() {
    return this.mode === MODE.EDITING;
  }

  get isConfirming() {
    return this.mode === MODE.CONFIRMING;
  }

  get hasInputs() {
    return hasInputFields(this.action);
  }

  // The message from the parent, or "Done" when it sent none.
  get resultMessage() {

    // [1] Read the message from the state, which may be missing
    const stateMessage = this.state && this.state.message;

    return stateMessage || LABELS.actionDone;
  }

  // The question on the confirmation step, or the action name as a question.
  get confirmationText() {

    // [1] Use the action's own message when it has one
    const customMessage = this.action.confirmationMessage;
    const defaultMessage = `${this.action.name}?`;

    return customMessage || defaultMessage;
  }

  get fieldViews() {
    return buildFieldViews(this.action.inputFields, this.values);
  }

  // Run button: run with no edited inputs
  handleRun() {
    this.startRun({});
  }

  // Edit first button: show the input fields
  handleEdit() {
    this.mode = MODE.EDITING;
  }

  // An input changed: keep its value, keyed by field name
  handleFieldChange(event) {

    // [1] Read which field changed
    const fieldName = event.target.dataset.field;

    // [2] A checkbox keeps its checked state, every other input keeps its value
    const isCheckbox = event.target.type === INPUT_TYPE.CHECKBOX;
    const value = isCheckbox ? event.target.checked : event.detail.value;

    // [3] Save the new value next to the others
    this.values = { ...this.values, [fieldName]: value };
  }

  // Run button on the edit form: run only when every input is valid
  handleRunEdited() {

    // [1] Find the inputs on the form
    const inputs = [...this.template.querySelectorAll(EDITABLE_INPUT_SELECTOR)];

    // [2] Stop here when an input is not valid
    const isValid = isEveryInputValid(inputs);

    if (!isValid) {
      return;
    }

    // [3] Run with a copy of the typed values
    this.startRun({ ...this.values });
  }

  // Confirm button: run with the inputs that were waiting
  handleConfirm() {
    const inputs = this.pendingInputs || {};

    this.dispatchRun(inputs);
  }

  // Cancel on the confirmation records that the action was offered and declined; Cancel while editing the inputs does not.
  handleCancel() {

    // [1] Tell the parent only when the user declined on the confirmation
    const isDeclined = this.mode === MODE.CONFIRMING;

    if (isDeclined) {
      this.dispatchEvent(new CustomEvent(EVENTS.DECLINE));
    }

    // [2] Go back to the buttons and forget the waiting inputs
    this.mode = MODE.BUTTONS;
    this.pendingInputs = null;
  }

  // Dismiss button: tell the parent to hide the action
  handleDismiss() {
    this.dispatchEvent(new CustomEvent(EVENTS.DISMISS));
  }

  // Actions flagged RequiresConfirmation__c stop at a confirmation step first.
  startRun(inputs) {

    // [1] Ask for confirmation first when the action needs it and the user has not confirmed yet
    const needsConfirmation = this.action.requiresConfirmation && this.mode !== MODE.CONFIRMING;

    if (needsConfirmation) {
      this.pendingInputs = inputs;
      this.mode = MODE.CONFIRMING;
      return;
    }

    // [2] Otherwise run now
    this.dispatchRun(inputs);
  }

  // Goes back to the buttons and tells the parent to run the action with these inputs.
  dispatchRun(inputs) {

    // [1] Go back to the buttons and forget the waiting inputs
    this.mode = MODE.BUTTONS;
    this.pendingInputs = null;

    // [2] Tell the parent to run the action
    this.dispatchEvent(new CustomEvent(EVENTS.RUN, { detail: { inputs } }));
  }
}
