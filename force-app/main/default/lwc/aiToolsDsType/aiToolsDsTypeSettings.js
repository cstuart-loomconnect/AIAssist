/*
Component Name: aiToolsDsType

=================================================================
=================================================================

Description: The settings of the Type step: the two questions, their choices, class names and label text.

Step 1: Name the source types and binding types the choices set
Step 2: Hold the text of each choice
Step 3: Name the classes of a choice and of the chosen choice

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// The source types. Mirror AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL and DATA_SOURCE_TYPE_APEX.
export const SOURCE_TYPE_SOQL = "SOQL";
export const SOURCE_TYPE_APEX = "Apex";

// The binding types. Mirror AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND and DATA_SOURCE_BINDING_UNBOUND.
export const BINDING_BOUND = "Bound";
export const BINDING_UNBOUND = "Unbound";

// The classes of a choice, and of the choice that is on.
export const CHOICE_CLASS = "aiadt-choice";
export const CHOICE_SELECTED_CLASS = "aiadt-choice aiadt-choice_selected";

// Text shown to the user.
export const LABELS = {
  typeQuestion: "How does it read data?",
  bindingQuestion: "Is it about the record the user has open?",
  soqlTitle: "SOQL query",
  soqlText: "Build it visually or write it. No code to deploy. Runs in user mode.",
  apexTitle: "Apex class",
  apexText: "Pick a class that implements IAIDataSourceExecutor, for logic a query can't do.",
  boundTitle: "Bound to the open record",
  boundText: ":recordId is filled in from the page. It needs a record open to run.",
  unboundTitle: "Unbound",
  unboundText: "Offered anywhere. The agent supplies every input."
};

// The choices of each question.
export const TYPE_CHOICES = [
  { value: SOURCE_TYPE_SOQL, title: LABELS.soqlTitle, text: LABELS.soqlText },
  { value: SOURCE_TYPE_APEX, title: LABELS.apexTitle, text: LABELS.apexText }
];
export const BINDING_CHOICES = [
  { value: BINDING_BOUND, title: LABELS.boundTitle, text: LABELS.boundText },
  { value: BINDING_UNBOUND, title: LABELS.unboundTitle, text: LABELS.unboundText }
];
