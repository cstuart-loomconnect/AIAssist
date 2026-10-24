/*
Component Name: aiToolsDsType

=================================================================
=================================================================

Description: Step 1 of the data source wizard: choose how the data source reads data and whether it is about the open record.

Step 1: Show the two choices for how it reads data
Step 2: Show the two choices for whether it is about the open record
Step 3: Tell the wizard what was chosen

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { TYPE_CHOICES, BINDING_CHOICES, CHOICE_CLASS, CHOICE_SELECTED_CLASS, LABELS } from "./aiToolsDsTypeSettings";

// The Type step. It shows the draft's two choices and reports a new choice.
export default class AiToolsDsType extends LightningElement {

  // The draft of the wizard. Read only: changes are sent up in the draftchange event.
  @api draft;

  // Values the template reads
  labels = LABELS;

  // The choices for how the data source reads data.
  get typeItems() {

    // [1] Mark the one that is on
    const typeItems = this.buildItems(TYPE_CHOICES, this.draft.sourceType);

    return typeItems;
  }

  // The choices for whether it is about the open record.
  get bindingItems() {

    // [1] Mark the one that is on
    const bindingItems = this.buildItems(BINDING_CHOICES, this.draft.bindingType);

    return bindingItems;
  }

  // Event handlers
  handleTypeClick(event) {

    // [1] Tell the wizard the source type
    this.sendChange({ sourceType: event.currentTarget.dataset.value });
  }

  handleBindingClick(event) {

    // [1] Tell the wizard the binding type
    this.sendChange({ bindingType: event.currentTarget.dataset.value });
  }

  // Private methods
  buildItems(choices, selectedValue) {

    // [1] Add the class that says whether the choice is on
    const items = choices.map((choice) => {

      const isSelected = choice.value === selectedValue;
      const choiceClass = isSelected ? CHOICE_SELECTED_CLASS : CHOICE_CLASS;

      return { ...choice, choiceClass, isSelected };
    });

    return items;
  }

  sendChange(changes) {

    // [1] Send the change up to the wizard
    this.dispatchEvent(new CustomEvent("draftchange", { detail: { changes } }));
  }
}
