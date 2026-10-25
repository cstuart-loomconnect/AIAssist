/*
Component Name: aiToolsWaStepType

=================================================================
=================================================================

Description: The settings of step 1 of the workflow action wizard: the types, class names and label text.

Step 1: Name the values the step reports
Step 2: Name the classes of a chosen card and a chosen button
Step 3: Hold the text shown to the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Values that mirror AIWorkflowAction__c: ActionType__c and ExecutionType__c.
export const ACTION_TYPE_APEX = "Apex";
export const ACTION_TYPE_FLOW = "Flow";
export const ACTION_TYPE_SCREEN_FLOW = "Screen Flow";
export const EXECUTION_READ_ONLY = "Read Only";
export const EXECUTION_WRITE = "Write";

// The classes of a card and a button, plain and chosen.
export const CARD_CLASS = "aitwa-card";
export const CARD_SELECTED_CLASS = "aitwa-card aitwa-card_selected";
export const CHOICE_CLASS = "aitwa-choice";
export const CHOICE_SELECTED_CLASS = "aitwa-choice aitwa-choice_selected";

// The text of a value that is empty.
export const NO_TEXT = "";

// The cards, in the order they are shown.
export const TYPE_CARDS = [
  { value: ACTION_TYPE_APEX, title: "Apex class", detail: "Implements IAIWorkflowActionExecutor." },
  { value: ACTION_TYPE_FLOW, title: "Autolaunched flow", detail: "Runs in the background with the inputs the agent fills in." },
  { value: ACTION_TYPE_SCREEN_FLOW, title: "Screen flow", detail: "Opens in a modal and the user finishes it." }
];

// Text shown to the user.
export const LABELS = {
  whatRuns: "What runs it?",
  doesChange: "Does it change data?",
  readOnly: "Read only",
  write: "Write",
  writeNote: "Write actions always ask the user to confirm. You'll set the message on step 4.",
  screenFlowNote: "A screen flow does not need a separate confirmation: the user pressing Finish in the window is the confirmation."
};
