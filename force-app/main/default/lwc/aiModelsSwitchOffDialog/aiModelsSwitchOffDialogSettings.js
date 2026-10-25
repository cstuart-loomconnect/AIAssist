/*
Component Name: aiModelsSwitchOffDialog

=================================================================
=================================================================

Description: The settings of the switch off dialog: label text.

Step 1: Hold the text shown to the admin
Step 2: Hold the names of the events the dialog sends

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown to the user.
export const LABELS = {
  title: "Switch off this model?",
  isUsedBy: " is used by ",
  activeAgentOne: " active agent",
  activeAgentMany: " active agents",
  stopAnswering: ". If it's switched off, they stop answering.",
  columnAgent: "Agent",
  columnUsers: "Users",
  columnMoveTo: "Move to",
  openConversations: "Open conversations switch model from their next message.",
  noOtherModel:
    "There is no other active model to move the agents to. Switch another model on first.",
  cancel: "Cancel",
  switchOff: "Switch off",
  movePrefix: "Move ",
  moveAgentOne: " agent and switch off",
  moveAgentMany: " agents and switch off",
  saving: "Switching off"
};

// The names of the events the dialog sends to the tab.
export const EVENT_CANCEL = "cancel";
export const EVENT_CONFIRM = "confirm";

// The text of a value when it is empty.
export const NO_TEXT = "";
