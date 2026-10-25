/*
Component Name: aiAgentWizardDone

=================================================================
=================================================================

Description: The settings of the done screen of the AI Agent Wizard: the navigation targets and label text.

Step 1: Name the navigation targets
Step 2: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The page types the buttons open.
export const PAGE_TYPE_RECORD = "standard__recordPage";
export const PAGE_TYPE_OBJECT = "standard__objectPage";
export const ACTION_VIEW = "view";
export const ACTION_LIST = "list";

// The text between the parts of a list.
export const LIST_SEPARATOR = ", ";
export const VOWELS = "aeiou";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  liveSuffix: " is live",
  draftSuffix: " is saved as a draft",
  liveUsersMiddle: " users will see it in the chat window on ",
  livePagesAfter: " pages the next time they open one.",
  draftText: "It is switched off, so nobody sees it yet. Open the agent record or run this wizard again to activate it when it is ready.",
  created: "Created",
  saved: "Saved",
  model: "Model",
  noModel: "None yet",
  agentOne: "1 agent",
  dataSourceOne: "1 data source",
  dataSourceMany: " data sources",
  actionOne: "1 workflow action",
  actionMany: " workflow actions",
  assignmentOne: "1 assignment",
  assignmentMany: " assignments",
  and: " and ",
  openRecord: "Open the agent record",
  tryItBefore: "Try it on ",
  createAnother: "Create another agent",
  backToList: "Back to all agents"
};
