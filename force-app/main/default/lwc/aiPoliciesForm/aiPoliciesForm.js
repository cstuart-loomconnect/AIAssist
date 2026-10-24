/*
Component Name: aiPoliciesForm

=================================================================
=================================================================

Description: The Settings tab of one policy: name, description, limits and what users can do.

Step 1: Show the saved values of the policy in a draft the admin can change
Step 2: Check the draft when the admin saves, and show the reason when it is refused
Step 3: Tell the tab to save the draft, or to throw it away

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import {
  SECTIONS,
  FIELD_NAME,
  FIELD_DESCRIPTION,
  FIELD_IS_ACTIVE,
  FIELD_IS_DEFAULT,
  FIELD_CHANNELS,
  NAME_MAX_LENGTH,
  DESCRIPTION_MAX_LENGTH,
  EVENT_SAVE,
  EVENT_CANCEL,
  NO_TEXT,
  LABELS
} from "./aiPoliciesFormSettings";
import {
  buildDraft,
  buildSectionViews,
  buildSaveValues
} from "./aiPoliciesFormHelper";

// The Settings tab of one policy. The tab passes the saved values and listens for save and cancel.
export default class AiPoliciesForm extends LightningElement {
  // Values passed in by the parent component
  @api isSaving = false; // True while a save runs, so the buttons wait
  @api errorMessage = NO_TEXT; // The message from the last failed save, or blank

  // Values the template reads
  labels = LABELS;
  nameMaxLength = NAME_MAX_LENGTH;
  descriptionMaxLength = DESCRIPTION_MAX_LENGTH;

  // State of the form
  savedValues = {};
  draft = {};
  problemMessage = NO_TEXT;

  // The saved values of the policy, keyed by field name, with the name under Name. The form starts its draft from them.
  @api
  get values() {
    return this.savedValues;
  }

  set values(newValues) {
    // [1] Keep the saved values and start a draft from them
    this.savedValues = newValues || {};
    this.draft = buildDraft(this.savedValues);
    this.problemMessage = NO_TEXT;
  }

  // The sections and rows with the value of each.
  get sectionViews() {
    // [1] Hand the work to the helper
    const sectionViews = buildSectionViews(SECTIONS, this.draft);

    return sectionViews;
  }

  get nameValue() {
    // [1] A missing name shows as an empty box
    const nameValue = this.draft[FIELD_NAME] || NO_TEXT;

    return nameValue;
  }

  get descriptionValue() {
    // [1] A missing description shows as an empty box
    const descriptionValue = this.draft[FIELD_DESCRIPTION] || NO_TEXT;

    return descriptionValue;
  }

  get isActive() {
    // [1] Only a true value switches the toggle on
    const isActive = this.draft[FIELD_IS_ACTIVE] === true;

    return isActive;
  }

  get isDefault() {
    // [1] Only a true value switches the toggle on
    const isDefault = this.draft[FIELD_IS_DEFAULT] === true;

    return isDefault;
  }

  get saveLabel() {
    // [1] The button says Saving while a save is running
    const saveLabel = this.isSaving ? LABELS.saving : LABELS.save;

    return saveLabel;
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
  handleTextInput(event) {
    // [1] Keep what was typed in the draft
    const fieldName = event.target.dataset.key;
    this.draft = { ...this.draft, [fieldName]: event.target.value };
    this.problemMessage = NO_TEXT;
  }

  handleToggleChange(event) {
    // [1] Keep whether the switch is on
    const fieldName = event.target.dataset.key;
    this.draft = { ...this.draft, [fieldName]: event.target.checked };
  }

  handleSelectChange(event) {
    // [1] Keep the option that was chosen
    const fieldName = event.target.dataset.key;
    this.draft = { ...this.draft, [fieldName]: event.target.value };
  }

  handleSegmentClick(event) {
    // [1] Keep the choice that was clicked
    const fieldName = event.currentTarget.dataset.key;
    const chosenValue = event.currentTarget.dataset.value;
    this.draft = { ...this.draft, [fieldName]: chosenValue };
  }

  handleChannelsChange(event) {
    // [1] Keep the channels that are ticked
    this.draft = { ...this.draft, [FIELD_CHANNELS]: event.detail.value };
  }

  handleCancel() {
    // [1] Tell the tab to throw the draft away
    this.dispatchEvent(new CustomEvent(EVENT_CANCEL));
  }

  handleSave() {
    // [1] Check the draft and build the values Apex expects
    const result = buildSaveValues(this.draft, SECTIONS);

    if (result.problem) {
      this.problemMessage = result.problem;
      return;
    }

    // [2] Send the values to the tab
    const detail = { values: result.values };
    this.dispatchEvent(new CustomEvent(EVENT_SAVE, { detail }));
  }
}
