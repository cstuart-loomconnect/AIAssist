/*
Component Name: aiToolsDsSaveDialog

=================================================================
=================================================================

Description: The settings of the save dialog: label text.

Step 1: Hold the text of the title, the message, the table, the note and the buttons

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  titleStart: "Save changes to \"",
  titleEnd: "\"?",
  messageStart: " is used by ",
  messageOne: " active agent. Changing it changes what that agent can see.",
  messageMany: " active agents. Changing it changes what those agents can see.",
  columnAgent: "Agent",
  note: "The test must pass again before the change goes live. Until then the current version keeps running.",
  cancel: "Cancel",
  confirm: "Save and test"
};
