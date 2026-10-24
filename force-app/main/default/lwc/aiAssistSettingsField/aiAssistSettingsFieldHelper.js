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

import { EMPTY_TEXT } from "./aiAssistSettingsFieldSettings";

// Turns a stored value into text for a text or number box, so a blank shows as an empty box.
export function formatInputValue(storedValue) {

  // [1] Blank stays blank
  const isBlank = storedValue === null || storedValue === undefined;
  if (isBlank) return EMPTY_TEXT;

  return storedValue;
}
