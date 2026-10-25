/*
Component Name: aiAgentWizardList

=================================================================
=================================================================

Description: The settings of the agent list of the AI Agent Wizard: segments, menu choices, class names and label text.

Step 1: Name the segments and the row menu choices
Step 2: Name the values that mirror Apex
Step 3: Hold the class names, the date style and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The segments above the table.
export const SEGMENT_ALL = "all";
export const SEGMENT_ACTIVE = "active";
export const SEGMENT_DRAFT = "draft";

// Values that mirror Apex: AIAgentWizardDataStructure.AgentRow.topFindingSeverity.
export const SEVERITY_BLOCKER = "Blocker";
export const SEVERITY_WARNING = "Warning";

// The classes of the status pill and of the hint line under a row.
export const PILL_ACTIVE_CLASS = "aiawl-pill aiawl-pill_success";
export const PILL_DRAFT_CLASS = "aiawl-pill aiawl-pill_neutral";
export const HINT_BLOCKER_CLASS = "aiawl-hint aiawl-hint_blocker";
export const HINT_WARNING_CLASS = "aiawl-hint aiawl-hint_warning";

// The variants of the segment buttons, the toast and the confirm dialog.
export const SEGMENT_SELECTED_CLASS = "aiawl-filter aiawl-filter_selected";
export const SEGMENT_CLASS = "aiawl-filter";

// The locale the last changed date is shown in.
export const DATE_LOCALE = "en-GB";

// The text between the parts of a list.
export const LIST_SEPARATOR = ", ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  intro: "An agent is an AI assistant set up for record pages. It uses a model, can read data sources and run workflow actions, and is offered only to the users you choose.",
  createAgent: "+ New agent",
  searchLabel: "Search agents",
  searchPlaceholder: "Search by name, page or model",
  segmentsAria: "Show agents",
  all: "All",
  active: "Active",
  draft: "Draft",
  columnName: "Name",
  columnStatus: "Status",
  columnPages: "Pages",
  columnModel: "Model",
  columnUsers: "Users",
  columnChanged: "Last changed",
  noPages: "(no pages)",
  noModel: "(no model)",
  allUsers: "All",
  loading: "Loading the agents",
  emptyTitle: "No agents yet",
  emptyDetail: "Create your first agent to get started.",
  noMatch: "No agents match your search.",
  hintBlockerDraft: "Can't activate: ",
  hintBlockerActive: "Needs fixing: ",
  hintWarningOne: "1 thing needs a look",
  hintWarningMiddle: " things need a look",
  fallbackError: "Something went wrong. Please try again."
};
