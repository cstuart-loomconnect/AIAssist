/*
Component Name: aiAgentWizardStepSkills

=================================================================
=================================================================

Description: The settings of the Skills step of the AI Agent Wizard: the draft field it changes, the values it compares with, class names and the text shown to the admin.

Step 1: Name the draft field that holds the skill ids
Step 2: Hold the values that mirror AISkill__c and the finding severity
Step 3: Hold the class names and the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The draft field that holds the ids of the skills.
export const FIELD_SKILL_IDS = "skillIds";

// Values that mirror AISkill__c: OutputType__c and LastTestStatus__c.
export const OUTPUT_RECORD_CHANGE = "Record Change";
export const OUTPUT_REPORT = "Report";
export const TEST_STATUS_PASSED = "Passed";
export const TEST_STATUS_FAILED = "Failed";
export const TEST_STATUS_NOT_PICKED = "Not Picked";

// Values that mirror AIAgentWizardDataStructure.Finding.severity.
export const SEVERITY_BLOCKER = "Blocker";

// The classes of the pills in a row and of the severity pills of a finding.
export const PILL_CLASS = "aiawsk-pill";
export const PILL_WARNING_CLASS = "aiawsk-pill aiawsk-pill_warning";
export const PILL_DANGER_CLASS = "aiawsk-pill aiawsk-pill_danger";

// The text between the parts of a line of detail.
export const DETAIL_SEPARATOR = " · ";

// The text of a value that is empty.
export const NO_TEXT = "";

// Text shown to the user.
export const LABELS = {
  intro: "A skill is a job the agent can do, such as summarising an account or drafting a renewal email. It brings its own data sources and workflow actions, so they do not need adding on the next two steps.",
  search: "Search skills",
  given: "Given to this agent",
  others: "Other skills",
  add: "Add",
  remove: "Remove",
  noSkills: "No skills exist yet. Build them on the AI Tools tab, then they show up here.",
  noMatches: "Nothing matches that search.",
  emptyGiven: "No skills yet. The agent answers with its prompt template and the data sources and actions added directly.",
  dataSuffix: " data",
  actionsSuffix: " actions",
  anyPage: "Any page",
  needsPrefix: "Needs a ",
  outputRecordChange: "Changes records",
  outputReport: "Builds a report",
  inactive: "Switched off",
  testFailed: "Last test failed",
  notPicked: "Not picked in test",
  neverTested: "Never tested",
  agentsSuffix: " agents",
  needLookOne: "1 thing needs a look.",
  needLookMany: " things need a look.",
  wontStopSaving: " They won't stop you saving.",
  blocker: "Blocker",
  warning: "Warning",
  note: "Only existing skills are given here. New ones are built and tested on the AI Tools tab, then show up in this list."
};
