/*
Component Name: aiAssistSettingsField

=================================================================
=================================================================

Description: One setting on the Settings tab: a label, help text and the control that fits its type.

Step 1: Show the label, the help text and the field name
Step 2: Show the control for the field type: switch, number, text, list of codes or choice
Step 3: Tell the form when the value changes
Step 4: Check the control on request, so the form can refuse a save with a bad value

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { FIELD_TYPE_TOGGLE, FIELD_TYPE_NUMBER, FIELD_TYPE_TEXT, FIELD_TYPE_URL, FIELD_TYPE_CODES, FIELD_TYPE_CHOICE, EVENT_CHANGE, INPUT_TYPE_TEXT, INPUT_TYPE_URL, CONTROL_SELECTOR, LABELS } from "./aiAssistSettingsFieldSettings";
import { formatInputValue } from "./aiAssistSettingsFieldHelper";

// One setting on the Settings tab. The form passes the field definition and its current value, and listens for change.
export default class AiAssistSettingsField extends LightningElement {

  // Values passed in by the parent component
  @api field; // { key, label, type, help, unit, required, min, max, blankHelp, dependencyHint, options: [{ label, value }] }
  @api value; // The current value: true or false, a number or text
  @api apiName; // The field name shown in small text, for example AIAssistSettings__c.MaxMessageLength__c
  @api badgeLabel; // Short text beside the label, or blank for none

  // Values the template reads
  labels = LABELS;

  // The kind of control to show.
  get isToggle() {

    // [1] Compare the field type with the toggle type
    const isToggleType = this.field.type === FIELD_TYPE_TOGGLE;

    return isToggleType;
  }

  get isNumber() {

    // [1] Compare the field type with the number type
    const isNumberType = this.field.type === FIELD_TYPE_NUMBER;

    return isNumberType;
  }

  get isText() {

    // [1] Text, web addresses and lists of codes all use a text box
    const fieldType = this.field.type;
    const isTextType = fieldType === FIELD_TYPE_TEXT || fieldType === FIELD_TYPE_URL || fieldType === FIELD_TYPE_CODES;

    return isTextType;
  }

  get isChoice() {

    // [1] Compare the field type with the radio buttons type
    const isChoiceType = this.field.type === FIELD_TYPE_CHOICE;

    return isChoiceType;
  }

  get isCodes() {

    // [1] Compare the field type with the list of codes type
    const isCodesType = this.field.type === FIELD_TYPE_CODES;

    return isCodesType;
  }

  // Values the controls read.
  get inputValue() {

    // [1] A blank value shows as an empty box
    const inputValue = formatInputValue(this.value);

    return inputValue;
  }

  get textInputType() {

    // [1] A web address uses the url box, everything else the text box
    const isUrl = this.field.type === FIELD_TYPE_URL;
    const inputType = isUrl ? INPUT_TYPE_URL : INPUT_TYPE_TEXT;

    return inputType;
  }

  get isChecked() {

    // [1] Only a true value switches the toggle on
    const isChecked = this.value === true;

    return isChecked;
  }

  // Whether each optional piece of text shows.
  get hasBadge() {

    // [1] A badge shows when the parent passed some text
    const hasBadge = Boolean(this.badgeLabel);

    return hasBadge;
  }

  get hasHelp() {

    // [1] The help text shows when the field has some
    const hasHelp = Boolean(this.field.help);

    return hasHelp;
  }

  get hasBlankHelp() {

    // [1] The blank text shows when the field has some
    const hasBlankHelp = Boolean(this.field.blankHelp);

    return hasBlankHelp;
  }

  get hasDependencyHint() {

    // [1] The dependency hint shows when the field has one
    const hasDependencyHint = Boolean(this.field.dependencyHint);

    return hasDependencyHint;
  }

  get hasUnit() {

    // [1] The unit shows when the field has one
    const hasUnit = Boolean(this.field.unit);

    return hasUnit;
  }

  // Event handlers
  handleToggleChange(event) {

    // [1] Keep the base component's own event from reaching the form
    event.stopPropagation();

    // [2] Tell the form whether the switch is on
    const isOn = event.target.checked;
    this.sendChange(isOn);
  }

  handleInputChange(event) {

    // [1] Keep the base component's own event from reaching the form
    event.stopPropagation();

    // [2] Tell the form what was typed
    const typedValue = event.target.value;
    this.sendChange(typedValue);
  }

  handleChoiceChange(event) {

    // [1] Keep the base component's own event from reaching the form
    event.stopPropagation();

    // [2] Tell the form what was chosen
    const chosenValue = event.detail.value;
    this.sendChange(chosenValue);
  }

  // Checks the control and shows its message. Returns true when the value is fine.
  @api
  validate() {

    // [1] Find the controls this field shows
    const controls = this.template.querySelectorAll(CONTROL_SELECTOR);
    let isValid = true;

    // [2] Ask each one to check itself
    controls.forEach((control) => {
      const isControlValid = control.reportValidity();
      if (!isControlValid) isValid = false;
    });

    return isValid;
  }

  // Private methods
  sendChange(newValue) {

    // [1] Tell the form which field changed and what it now holds
    const detail = { key: this.field.key, value: newValue };
    const changeEvent = new CustomEvent(EVENT_CHANGE, { detail });
    this.dispatchEvent(changeEvent);
  }
}
