/*
Component Name: aiAssistSettings

=================================================================
=================================================================

Description: The AI Assist Settings tab: change AI Assist Settings and AI Assist UI Settings.

Step 1: Load every row of both settings from Apex
Step 2: Show one tab for AI Assist Settings and one for AI Assist UI Settings
Step 3: Hand each tab to a panel
Step 4: Load the rows again whenever a panel saves or deletes one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS } from "./aiAssistSettingsSettings";

// Turns whatever an Apex call threw into text the admin can read.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return LABELS.fallbackError;
}
