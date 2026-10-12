/*
Component Name: aiChatEmptyState

=================================================================
=================================================================

Description: Helper for aiChatEmptyState: builds the suggested commands, the greeting and the suggestions heading.

Step 1: Pick the commands to suggest, record-specific ones first
Step 2: Choose the greeting text
Step 3: Choose the heading above the suggestions

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, MAX_SUGGESTIONS } from "./aiChatEmptyStateSettings";

// Picks the commands to suggest, with record-specific commands first, up to the limit.
export function buildSuggestedCommands(commands, maxSuggestions = MAX_SUGGESTIONS) {

  // [1] The parent may not have set any commands yet
  const commandList = commands || [];

  // [2] Split the commands into record-specific and general
  const specificCommands = commandList.filter((command) => command.isRecordSpecific);
  const generalCommands = commandList.filter((command) => !command.isRecordSpecific);

  // [3] Put the record-specific ones first and keep only the allowed number
  const orderedCommands = [...specificCommands, ...generalCommands];
  const suggestedCommands = orderedCommands.slice(0, maxSuggestions);

  return suggestedCommands;
}

// Chooses the greeting: the Agent's own greeting, else one built from the object label, else the plain default.
export function buildGreeting(greeting, objectLabel) {

  // [1] The Agent's own greeting wins
  if (greeting) {
    return greeting;
  }

  // [2] With an object label, ask what the user needs on that object
  if (objectLabel) {
    const lowerCaseLabel = objectLabel.toLowerCase();
    return `${LABELS.defaultGreeting} ${lowerCaseLabel}?`;
  }

  // [3] With no record, use the plain default
  return LABELS.defaultGreetingNoRecord;
}

// Chooses the heading above the suggested commands.
export function buildSuggestionsHeading(objectLabelPlural) {

  // [1] With a plural object label, name the object
  if (objectLabelPlural) {
    return `${LABELS.suggestedFor} ${objectLabelPlural}`;
  }

  // [2] With no object label, use the plain heading
  return LABELS.commands;
}
