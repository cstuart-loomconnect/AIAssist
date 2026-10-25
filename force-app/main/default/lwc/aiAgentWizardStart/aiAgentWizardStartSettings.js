/*
Component Name: aiAgentWizardStart

=================================================================
=================================================================

Description: The settings of the start screen of the AI Agent Wizard: the two ways to begin, class names and label text.

Step 1: Name the two ways to begin
Step 2: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two ways to start an agent.
export const MODE_BLANK = "blank";
export const MODE_COPY = "copy";

// The classes of a card and of a row in a list.
export const CARD_CLASS = "aiawst-card";
export const CARD_SELECTED_CLASS = "aiawst-card aiawst-card_selected";
export const OPTION_CLASS = "aiawst-option";
export const OPTION_SELECTED_CLASS = "aiawst-option aiawst-option_selected";

export const LIST_SEPARATOR = ", ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  title: "Create an agent",
  intro: "Start with a blank agent, or copy an existing one.",
  blankTitle: "Blank agent",
  blankDetail: "Every field empty. Best when you know exactly what you want.",
  copyTitle: "Copy an existing agent",
  copyDetail: "Clone an agent's settings, data sources and actions, then change what differs.",
  copyHeading: "Agents to copy",
  active: "Active",
  draft: "Draft",
  noAgents: "There are no agents to copy yet.",
  cancel: "Cancel",
  start: "Start"
};
