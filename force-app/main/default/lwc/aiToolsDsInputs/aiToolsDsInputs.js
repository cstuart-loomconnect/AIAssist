/*
Component Name: aiToolsDsInputs

=================================================================
=================================================================

Description: Step 3 of the data source wizard: the inputs of the data source, who fills each one and what the agent is told about it.

Step 1: Show one row for each input, read from the binds of the query or the class
Step 2: Let the admin type, for each input the agent fills, its type, whether it is required and a description
Step 3: Show the input schema that will be saved, and tell the wizard about each change

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { SOURCE_TYPE_APEX, LABELS } from "./aiToolsDsInputsSettings";
import { buildInputViews, buildSchemaText, buildNewInput, changeInput } from "./aiToolsDsInputsHelper";

// The Inputs step.
export default class AiToolsDsInputs extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // Values the template reads
  labels = LABELS;

  get isApex() {

    // [1] Only an Apex data source lets the admin add and name inputs, because a query takes them from its binds
    const isApex = this.draft.sourceType === SOURCE_TYPE_APEX;

    return isApex;
  }

  get inputViews() {

    // [1] Hand the work to the helper
    const inputViews = buildInputViews(this.draft.inputs, this.isApex);

    return inputViews;
  }

  get hasInputs() {

    // [1] There is at least one input
    const hasInputs = this.draft.inputs.length > 0;

    return hasInputs;
  }

  get introText() {

    // [1] The sentence depends on where the inputs come from
    const introText = this.isApex ? LABELS.introApex : LABELS.intro;

    return introText;
  }

  get emptyText() {

    // [1] The sentence depends on where the inputs come from
    const emptyText = this.isApex ? LABELS.noInputs : LABELS.noInputsSoql;

    return emptyText;
  }

  get noteText() {

    // [1] The sentence names what runs
    const noteText = this.isApex ? LABELS.noteApex : LABELS.noteSoql;

    return noteText;
  }

  get schemaText() {

    // [1] Hand the work to the helper
    const schemaText = buildSchemaText(this.draft.inputs);

    return schemaText;
  }

  // Event handlers
  handleNameChange(event) {

    // [1] Keep a plain name, because it is also a bind name
    this.sendInputChange(event, { name: event.target.value.replace(/[^A-Za-z0-9_]/g, "") });
  }

  handleTypeChange(event) {

    // [1] Keep the type
    this.sendInputChange(event, { type: event.target.value });
  }

  handleRequiredChange(event) {

    // [1] Keep whether it is required
    this.sendInputChange(event, { isRequired: event.target.checked });
  }

  handleDescriptionChange(event) {

    // [1] Keep what was typed
    this.sendInputChange(event, { description: event.target.value });
  }

  handleAddInput() {

    // [1] Add an input the agent fills in
    const inputs = [...this.draft.inputs, buildNewInput(this.draft.inputs)];
    this.sendChange({ inputs });
  }

  handleRemoveInput(event) {

    // [1] Take the input out
    const index = Number(event.currentTarget.dataset.index);
    const inputs = this.draft.inputs.filter((input, inputIndex) => inputIndex !== index);
    this.sendChange({ inputs });
  }

  // Private methods
  sendInputChange(event, changes) {

    // [1] Change the input the control belongs to
    const index = Number(event.target.dataset.index);
    this.sendChange({ inputs: changeInput(this.draft.inputs, index, changes) });
  }

  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
