/*
Component Name: aiChatEmptyState

=================================================================
=================================================================

Description: Settings for aiChatEmptyState: the suggestion limit, the label text and the event and attribute values.

Step 1: Hold the number of suggested commands shown
Step 2: Hold the label text the template and the greeting use
Step 3: Hold the event name and the aria-expanded values

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Suggested commands
export const MAX_SUGGESTIONS = 3; // The most commands shown on the empty screen

// Event sent to the parent
export const EVENT_COMMAND_SELECT = "commandselect"; // detail: { command }

// aria-expanded values for the "How this works" button
export const ARIA_EXPANDED_TRUE = "true";
export const ARIA_EXPANDED_FALSE = "false";

// Label text shown in the template and used in the greeting
export const LABELS = {
  commands: "Commands",
  piiBanner: "Personal details on this record are swapped for placeholders before anything is sent to the AI model.",
  piiHowItWorks: "How this works",
  piiExplanation: "Names, emails, phone numbers and other personal fields are replaced with placeholders like ‹PERSON_1› before the request leaves Salesforce, and swapped back in the answer you see.",
  suggestedFor: "Suggested for",
  workingOn: "Working on",
  defaultGreeting: "What do you need on this",
  defaultGreetingNoRecord: "What can I help you with?"
};
