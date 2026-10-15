/*
Component Name: aiAssistSettingsForm

=================================================================
=================================================================

Description: The form for one settings row: a list of groups on the left, the fields of the chosen group on the right, and Save and Cancel.

Step 1: Show the groups of the row as a side list and the fields of the chosen group beside it
Step 2: Keep every change in a draft until the admin saves
Step 3: Check the draft for blank required numbers and numbers out of range before sending it
Step 4: Tell the panel to save the draft, and show any error the panel hands back

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { EVENT_SAVE, FIELD_COMPONENT_SELECTOR, NO_MESSAGE, LABELS } from "./aiAssistSettingsFormSettings";
import { buildGroupItems, buildFieldViews, isSameValues, findFirstProblem } from "./aiAssistSettingsFormHelper";

// The form for one settings row. The panel gives it the groups and the saved values; the form keeps a draft and sends it back on Save.
export default class AiAssistSettingsForm extends LightningElement {

  // Values passed in by the parent component
  @api groups = []; // [{ key, label, objectName, fields: [{ key, label, type, ... }] }]
  @api values = {}; // The saved values by field name
  @api showScopeBadges = false; // True on the organisation row of AI Assist Settings, to mark which fields a profile or user may override
  @api isSaving = false; // True while the panel is saving, so the buttons are switched off
  @api errorMessage = NO_MESSAGE; // The message from the last failed save, or blank

  // Values the template reads
  labels = LABELS;

  // State of the form
  draft = {};
  savedValues = {};
  selectedGroupIndex = 0;
  problemMessage = NO_MESSAGE;

  // Lifecycle methods
  connectedCallback() {

    // [1] Start the draft from the saved values
    this.savedValues = { ...this.values };
    this.draft = { ...this.values };
  }

  // The groups turned into side list items.
  get groupItems() {

    // [1] Build one item per group, with its field count and the class that marks the chosen one
    const selectedKey = this.selectedGroup.key;
    const items = buildGroupItems(this.groups, selectedKey);

    return items;
  }

  get selectedGroup() {

    // [1] The group at the chosen position
    const selectedGroup = this.groups[this.selectedGroupIndex];

    return selectedGroup;
  }

  // The fields of the chosen group, with the draft value of each.
  get fieldViews() {

    // [1] Hand the work to the helper
    const fieldViews = buildFieldViews(this.selectedGroup, this.draft, this.showScopeBadges);

    return fieldViews;
  }

  // Whether the draft differs from the saved values.
  get isDirty() {

    // [1] Compare the draft with what is saved
    const isSame = isSameValues(this.draft, this.savedValues);

    return !isSame;
  }

  get isSaveDisabled() {

    // [1] Save needs a change, and waits while a save is running
    const hasNoChange = !this.isDirty;

    return hasNoChange || this.isSaving;
  }

  get saveLabel() {

    // [1] The button says Saving while a save is running
    const saveLabel = this.isSaving ? LABELS.saving : LABELS.save;

    return saveLabel;
  }

  get statusLabel() {

    // [1] The footer says whether there is anything to save
    const statusLabel = this.isDirty ? LABELS.unsaved : LABELS.noChanges;

    return statusLabel;
  }

  get shownError() {

    // [1] A problem found here comes before an error from the last save
    const shownError = this.problemMessage || this.errorMessage;

    return shownError;
  }

  get hasError() {

    // [1] A message means there is an error to show
    const hasError = Boolean(this.shownError);

    return hasError;
  }

  // Event handlers
  handleGroupSelect(event) {

    // [1] Show the fields of the group the admin picked
    const selectedKey = event.currentTarget.dataset.key;
    const index = this.groups.findIndex((group) => group.key === selectedKey);
    this.selectedGroupIndex = index;
  }

  handleFieldChange(event) {

    // [1] Read which field changed and its new value
    const { key, value } = event.detail;
    if (!key) return;

    // [2] Keep the new value in the draft
    this.draft = { ...this.draft, [key]: value };
    this.problemMessage = NO_MESSAGE;
  }

  handleCancel() {

    // [1] Put the draft back to the saved values
    this.draft = { ...this.savedValues };
    this.problemMessage = NO_MESSAGE;
  }

  handleSave() {

    // [1] Check the whole draft, including groups that are not on screen
    const problem = findFirstProblem(this.groups, this.draft);

    if (problem) {

      this.selectedGroupIndex = problem.groupIndex;
      this.problemMessage = problem.message;
      return;
    }

    // [2] Check the controls on screen, which show their own messages
    const fieldComponents = this.template.querySelectorAll(FIELD_COMPONENT_SELECTOR);
    let isValid = true;

    fieldComponents.forEach((fieldComponent) => {

      const isFieldValid = fieldComponent.validate();
      if (!isFieldValid) isValid = false;
    });

    if (!isValid) return;

    // [3] Send the draft to the panel
    const detail = { values: { ...this.draft } };
    const saveEvent = new CustomEvent(EVENT_SAVE, { detail });
    this.dispatchEvent(saveEvent);
  }
}
