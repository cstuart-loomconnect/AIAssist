/*
Component Name: aiAgentWizardStepItems

=================================================================
=================================================================

Description: The settings of the Data sources and Workflow actions steps of the AI Agent Wizard: which list the step shows, action types, class names and label text.

Step 1: Name the two lists the step can show, and the values that mirror Apex
Step 2: Hold the class names
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The two lists the step can show. The tab passes one of these as the kind.
export const KIND_DATA_SOURCE = "dataSource";
export const KIND_ACTION = "action";

// The draft fields that hold the ids of each list.
export const FIELD_DATA_SOURCE_IDS = "dataSourceIds";
export const FIELD_ACTION_IDS = "workflowActionIds";

// Values that mirror AIWorkflowAction__c.ActionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";

// Values that mirror the finding codes AIAgentWizardController gives to checkDraft.
export const CODE_WORKFLOW_ACTIONS_DISABLED = "WorkflowActionsDisabled";

// Values that mirror AIAgentWizardDataStructure.Finding.severity.
export const SEVERITY_BLOCKER = "Blocker";

// The classes of the pills in a row and of the severity pills of a finding.
export const PILL_CLASS = "aiawit-pill";
export const PILL_WARNING_CLASS = "aiawit-pill aiawit-pill_warning";
export const PILL_DANGER_CLASS = "aiawit-pill aiawit-pill_danger";

// The text between the parts of a line of detail.
export const DETAIL_SEPARATOR = " · ";
export const LIST_SEPARATOR = ", ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  introDataSources: "Everything this agent can read. Add data sources here from the ones that already exist.",
  introActions: "Everything this agent can change or launch. Write actions always ask the user first.",
  searchDataSources: "Search data sources",
  searchActions: "Search workflow actions",
  addDataSource: "Add data source",
  addAction: "Add workflow action",
  addedDirectly: "Added directly",
  remove: "Remove",
  bound: "bound",
  unbound: "unbound",
  maxRows: "max {count} rows",
  piiMasked: "PII masked",
  inactive: "Inactive",
  asksFirst: "Asks first",
  opensModal: "Opens a modal",
  noActiveVersion: "No active version",
  writeText: "Write",
  readText: "Read only",
  apexType: "Apex",
  flowType: "Autolaunched flow",
  screenFlowType: "Screen flow",
  activeVersion: "active v",
  userFinishes: "the user finishes it themselves",
  emptyDataSourcesTitle: "No data sources",
  emptyDataSourcesText: "This agent can only use what the conversation and the open record give it. Add a data source to let it read more.",
  emptyActionsTitle: "No workflow actions",
  emptyActionsText: "This agent is read-only: it can answer questions and draft text, but it can't create or change records.",
  emptyActionsNote: "Read-only agents are a safe first rollout. You can add actions later without rebuilding the agent.",
  noMatches: "Nothing matches that search.",
  summary: "Summary",
  readOnlyActions: "Read-only actions",
  writeActions: "Write actions",
  recordsItCanChange: "Records it can change",
  allAskFirst: ", all ask the user first",
  someAskFirst: " ask the user first",
  needLookOne: "1 thing needs a look.",
  needLookMany: " things need a look.",
  wontStopSaving: " They won't stop you saving.",
  blocker: "Blocker",
  warning: "Warning",
  openSettings: "Open Settings",
  noteDataSources: "Only existing data sources are linked here. New ones are built on the AI Tools tab, then show up in this list.",
  noteActions: "Only existing workflow actions are linked here. New ones are built on the AI Tools tab, then show up in this list."
};
