/*
Component Name: aiChatEmptyState

=================================================================
=================================================================

Description: The screen for a new conversation: the Agent's greeting, up to three suggested commands and the PII reassurance banner.

Step 1: Show the greeting and the record the user is working on
Step 2: Show the suggested commands for the record's object
Step 3: Tell the parent which command the user picked
Step 4: Show the PII banner, with a "How this works" explanation the user can open

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_COMMAND_SELECT, ARIA_EXPANDED_TRUE, ARIA_EXPANDED_FALSE } from "./aiChatEmptyStateSettings";
import { buildSuggestedCommands, buildGreeting, buildSuggestionsHeading } from "./aiChatEmptyStateHelper";

export default class AiChatEmptyState extends LightningElement {

  // Values passed in by the parent component
  @api greeting; // The Agent's greeting text. When empty, a greeting is built from objectLabel.
  @api recordName; // Name of the record the user is on. When empty, the "Working on" line is hidden.
  @api objectLabel; // Singular object label, e.g. "Account". Used in the default greeting.
  @api objectLabelPlural; // Plural object label, e.g. "Accounts". Used in the suggestions heading.
  @api commands = []; // [{ id, command, description, isRecordSpecific }]
  @api piiProtected = false; // true shows the PII banner
  @api disabled = false; // true turns the suggestion buttons off

  // Values the template reads
  labels = LABELS;

  // Tracked state
  isExplanationOpen = false; // true while the "How this works" text is open

  // The greeting shown at the top of the screen.
  get greetingText() {

    // [1] Hand the work to the helper
    return buildGreeting(this.greeting, this.objectLabel);
  }

  // The commands shown as suggestion buttons.
  get suggestions() {

    // [1] Hand the work to the helper
    return buildSuggestedCommands(this.commands);
  }

  // True when there is at least one suggestion to show.
  get hasSuggestions() {

    // [1] Count the suggestions
    const suggestionCount = this.suggestions.length;
    const hasSuggestions = suggestionCount > 0;

    return hasSuggestions;
  }

  // The heading above the suggestion buttons.
  get suggestionsHeading() {

    // [1] Hand the work to the helper
    return buildSuggestionsHeading(this.objectLabelPlural);
  }

  // The aria-expanded value for the "How this works" button.
  get explanationExpanded() {

    // [1] aria-expanded needs the text "true" or "false"
    const expandedValue = this.isExplanationOpen ? ARIA_EXPANDED_TRUE : ARIA_EXPANDED_FALSE;

    return expandedValue;
  }

  // Opens or closes the "How this works" text.
  handleToggleExplanation() {

    // [1] Flip the open state
    this.isExplanationOpen = !this.isExplanationOpen;
  }

  // Tells the parent which suggested command the user picked.
  handleSuggestion(event) {

    // [1] Read the command from the button that was clicked
    const command = event.currentTarget.dataset.command;

    // [2] Send it to the parent
    const commandSelectEvent = new CustomEvent(EVENT_COMMAND_SELECT, { detail: { command } });
    this.dispatchEvent(commandSelectEvent);
  }
}
