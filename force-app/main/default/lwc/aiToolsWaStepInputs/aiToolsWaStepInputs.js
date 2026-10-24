/*
Component Name: aiToolsWaStepInputs

=================================================================
=================================================================

Description: Step 3 of the workflow action wizard: who fills each input of the flow or class.

Step 1: Show each input with who can fill it in, and the choices that suit it
Step 2: Let the admin change who fills an input, describe it for the agent or give it a fixed value
Step 3: Show the outputs, the warning for inputs that cannot be filled, and a preview for a screen flow
Step 4: Tell the wizard what changed

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { ACTION_TYPE_APEX, ACTION_TYPE_SCREEN_FLOW, SOURCE_FIXED, DATA_TYPE_BOOLEAN, NO_TEXT, LABELS } from "./aiToolsWaStepInputsSettings";
import { buildInputViews, updateInput, addInput, removeInput, buildUnsupportedCount, buildOutputsText, buildPreviewFields } from "./aiToolsWaStepInputsHelper";

// Step 3. It shows the inputs of the draft and reports every change to the wizard.
export default class AiToolsWaStepInputs extends LightningElement {

  // Values passed in by the parent component
  @api draft; // The wizard's draft: inputs, outputs, actionType, sourceLabel and flowVersion are read here

  // Values the template reads
  labels = LABELS;

  get isApex() {

    // [1] An Apex action lets the admin add inputs
    const isApex = this.draft.actionType === ACTION_TYPE_APEX;

    return isApex;
  }

  get isScreenFlow() {

    // [1] A screen flow shows a preview
    const isScreenFlow = this.draft.actionType === ACTION_TYPE_SCREEN_FLOW;

    return isScreenFlow;
  }

  get isFlow() {

    // [1] A flow shows its outputs and the note about changes
    const isFlow = !this.isApex;

    return isFlow;
  }

  get showOutputs() {

    // [1] Only an autolaunched flow gives outputs back
    const showOutputs = this.isFlow && !this.isScreenFlow;

    return showOutputs;
  }

  get introText() {

    // [1] Say what this step is for
    if (this.isApex) return LABELS.introApex;

    return this.isScreenFlow ? LABELS.introScreenFlow : LABELS.introFlow;
  }

  get columnName() {

    // [1] A flow has variables, a class has inputs
    const columnName = this.isApex ? LABELS.columnInput : LABELS.columnVariable;

    return columnName;
  }

  get inputViews() {

    // [1] Hand the work to the helper
    const inputViews = buildInputViews(this.draft.inputs, this.isApex, this.isScreenFlow);

    return inputViews;
  }

  get hasInputs() {

    // [1] There is a table when there is at least one input
    const hasInputs = this.draft.inputs.length > 0;

    return hasInputs;
  }

  get unsupportedText() {

    // [1] Say how many inputs cannot be filled in, or nothing when none
    const unsupportedCount = buildUnsupportedCount(this.draft.inputs);
    if (unsupportedCount === 0) return NO_TEXT;

    const countText = unsupportedCount === 1 ? LABELS.unsupportedOne : unsupportedCount + LABELS.unsupportedMany;

    return countText + LABELS.unsupportedAdvice;
  }

  get hasUnsupported() {

    // [1] There is a warning when something is unsupported
    const hasUnsupported = Boolean(this.unsupportedText);

    return hasUnsupported;
  }

  get outputsText() {

    // [1] The outputs as text, or a sentence saying there are none
    const hasOutputs = this.draft.outputs.length > 0;
    const outputsText = hasOutputs ? buildOutputsText(this.draft.outputs) : LABELS.noOutputs;

    return outputsText;
  }

  get flowNoteText() {

    // [1] Name the flow and its version, then say it is flagged when it changes
    const versionText = this.draft.flowVersion ? " v" + this.draft.flowVersion : NO_TEXT;
    const flowNoteText = this.draft.sourceLabel + versionText + LABELS.flowChangeNote;

    return flowNoteText;
  }

  get previewFields() {

    // [1] Hand the work to the helper
    const previewFields = buildPreviewFields(this.draft.inputs);

    return previewFields;
  }

  get previewTitle() {

    // [1] The action's name, or the flow's
    const previewTitle = this.draft.actionName || this.draft.sourceLabel;

    return previewTitle;
  }

  // Event handlers
  handleSourceChange(event) {

    // [1] Change who fills the input, and clear what only the old choice needs
    const index = Number(event.currentTarget.dataset.index);
    const source = event.target.value;
    const defaultFixedValue = source === SOURCE_FIXED && this.draft.inputs[index].dataType === DATA_TYPE_BOOLEAN ? "true" : this.draft.inputs[index].fixedValue;
    this.reportInputs(updateInput(this.draft.inputs, index, { source, fixedValue: defaultFixedValue }));
  }

  handleDescriptionChange(event) {

    // [1] Keep what the admin wrote for the agent
    const index = Number(event.currentTarget.dataset.index);
    this.reportInputs(updateInput(this.draft.inputs, index, { description: event.target.value }));
  }

  handleFixedChange(event) {

    // [1] Keep the fixed value, which comes from a text box or from the true or false list
    const index = Number(event.currentTarget.dataset.index);
    const fixedValue = event.target.value;
    this.reportInputs(updateInput(this.draft.inputs, index, { fixedValue }));
  }

  handleNameChange(event) {

    // [1] Keep the name the admin typed for an input they added
    const index = Number(event.currentTarget.dataset.index);
    this.reportInputs(updateInput(this.draft.inputs, index, { name: event.target.value.trim() }));
  }

  handleTypeChange(event) {

    // [1] Keep the type the admin chose for an input they added
    const index = Number(event.currentTarget.dataset.index);
    const dataType = event.target.value;
    this.reportInputs(updateInput(this.draft.inputs, index, { dataType, typeLabel: dataType, fixedValue: NO_TEXT }));
  }

  handleAddInput() {

    // [1] Add an input for the admin to name
    this.reportInputs(addInput(this.draft.inputs));
  }

  handleRemoveInput(event) {

    // [1] Take an input the admin added out again
    const index = Number(event.currentTarget.dataset.index);
    this.reportInputs(removeInput(this.draft.inputs, index));
  }

  handleTargetObjectChange(event) {

    // [1] Keep the object the action works on
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { targetObject: event.target.value.trim() } } }));
  }

  // Private methods
  reportInputs(inputs) {

    // [1] Tell the wizard the inputs changed
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes: { inputs } } }));
  }
}
