/*
Component Name: aiToolsSkStepBasics

=================================================================
=================================================================

Description: The settings of step 1 of the skill wizard: the field lengths, the output choices and the text shown to the admin.

Step 1: Hold the longest name and API name, and the shortest and longest When To Use It
Step 2: Hold the output choices the admin can pick
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The field lengths. They mirror AISkill__c: Name, DeveloperName__c, and the length the AI Skill trigger allows for Description__c.
export const SKILL_NAME_MAX_LENGTH = 80;
export const API_NAME_MAX_LENGTH = 75;
export const DESCRIPTION_MIN_LENGTH = 40;
export const DESCRIPTION_MAX_LENGTH = 400;

// Values that mirror AISkill__c.OutputType__c. Record Change is set by Apex when the skill holds a write action, so it is not offered.
export const OUTPUT_CHAT_ANSWER = "Chat Answer";
export const OUTPUT_REPORT = "Report";
export const OUTPUT_RECORD_CHANGE = "Record Change";
export const OUTPUT_OPTIONS = [
  { label: "Chat answer", value: OUTPUT_CHAT_ANSWER },
  { label: "Report", value: OUTPUT_REPORT }
];

// The text of a value that is empty.
export const NO_TEXT = "";

// The classes of the When To Use It counter.
export const COUNTER_CLASS = "aitsk-counter";
export const COUNTER_BAD_CLASS = "aitsk-counter aitsk-counter_bad";

// Text shown to the user.
export const LABELS = {
  name: "Skill name",
  apiName: "API name",
  apiNameHelp: "The model picks the skill by this name. It cannot change once an agent has the skill.",
  description: "When To Use It",
  descriptionHelp: "This is all the model sees before it picks the skill. Say what it does, when to use it, and what it will not do.",
  counterSeparator: " / ",
  counterTooShort: " · at least 40",
  output: "Output",
  recordChangeNote: "This skill holds a workflow action that changes records, so it is saved as a Record change skill.",
  active: "Active",
  activeHelp: "Agents that have the skill can use it. It is only switched on when it has tools and every @ name in its instructions is one of them."
};
