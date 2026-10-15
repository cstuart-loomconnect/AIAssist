/*
Component Name: aiAssistSettingsField

=================================================================
=================================================================

Description: One setting on the Settings tab: a label, help text and the control that fits its type.

Step 1: Show the label, the help text and the field name
Step 2: Show the control for the field type: switch, number, text, list of codes, choice, dropdown or checkboxes
Step 3: Tell the form when the value changes
Step 4: Check the control on request, so the form can refuse a save with a bad value

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The kinds of control a field can use. The Settings tab names one of these on each field.
export const FIELD_TYPE_TOGGLE = "toggle";
export const FIELD_TYPE_NUMBER = "number";
export const FIELD_TYPE_TEXT = "text";
export const FIELD_TYPE_URL = "url";
export const FIELD_TYPE_CODES = "codes";
export const FIELD_TYPE_CHOICE = "choice";
export const FIELD_TYPE_SELECT = "select";
export const FIELD_TYPE_MULTI = "multi";

// A multi-select picklist is stored as text split by this character. Mirrors AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR.
export const MULTI_SEPARATOR = ";";

// The event this component sends to the form.
export const EVENT_CHANGE = "change";

// Input types for lightning-input.
export const INPUT_TYPE_TEXT = "text";
export const INPUT_TYPE_URL = "url";

// The controls a field can show, found by name so each one can be asked to check itself.
export const CONTROL_SELECTOR = "lightning-input, lightning-combobox, lightning-radio-group, lightning-checkbox-group";

// The text a blank value is shown as.
export const EMPTY_TEXT = "";

// Text shown to the user.
export const LABELS = {
  required: "Required",
  on: "On",
  off: "Off",
  codesHelp: "Separate the codes with commas.",
  apiNamePrefix: "Field: "
};
