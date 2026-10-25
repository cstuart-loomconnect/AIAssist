/*
Component Name: aiAgentWizardStepConversations

=================================================================
=================================================================

Description: The extended methods of the Conversations step: build the cards, the toggle rows and the form element classes.

Step 1: Build the cards and the visibility buttons, with the chosen one marked
Step 2: Build the text and state of the two toggles
Step 3: Turn the text of a number field into a number

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LOAD_CARDS, LOAD_MANUAL, VISIBILITY_CHOICES, CARD_CLASS, CARD_SELECTED_CLASS, SEG_CLASS, SEG_SELECTED_CLASS, FORM_ELEMENT_CLASS, FORM_ELEMENT_ERROR_CLASS, TOGGLE_ROW_CLASS, TOGGLE_ROW_DISABLED_CLASS, NO_TEXT, LABELS } from "./aiAgentWizardStepConversationsSettings";

// Builds the three cards, with the chosen one marked.
export function buildLoadCards(conversationLoadTrigger) {

  // [1] One view for each way of loading
  const loadCards = LOAD_CARDS.map((card) => ({ ...card, cardClass: card.value === conversationLoadTrigger ? CARD_SELECTED_CLASS : CARD_CLASS }));

  return loadCards;
}

// Builds the two visibility buttons, with the chosen one marked.
export function buildVisibilityButtons(conversationVisibility) {

  // [1] One button for each choice
  const visibilityButtons = VISIBILITY_CHOICES.map((choice) => ({ ...choice, buttonClass: choice.value === conversationVisibility ? SEG_SELECTED_CLASS : SEG_CLASS }));

  return visibilityButtons;
}

// Builds the text and the state of the resume toggle.
export function buildResumeToggle(conversationLoadTrigger, allowConversationResume) {

  // [1] Nothing loads automatically with Manual only, so there is nothing to resume
  const isDisabled = conversationLoadTrigger === LOAD_MANUAL;
  const isChecked = isDisabled ? false : Boolean(allowConversationResume);
  const hint = isDisabled ? LABELS.resumeDisabled : LABELS.resumeOn;
  const rowClass = isDisabled ? TOGGLE_ROW_DISABLED_CLASS : TOGGLE_ROW_CLASS;

  return { isDisabled, isChecked, hint, rowClass };
}

// Builds the text of the one-active-conversation toggle.
export function buildSingleHint(singleActiveConversationPerRecord, objectLabel) {

  // [1] On says what it keeps in one thread, off says what happens instead
  if (!singleActiveConversationPerRecord) return LABELS.singleOff;
  const recordName = objectLabel || LABELS.singleOnFallback;

  return LABELS.singleOnBefore + recordName + LABELS.singleOnAfter;
}

// Gives the class of a form element, with the SLDS problem look when it has a message.
export function buildFormElementClass(message) {

  // [1] A message means a problem
  const formElementClass = message ? FORM_ELEMENT_ERROR_CLASS : FORM_ELEMENT_CLASS;

  return formElementClass;
}

// Turns the text of a number field into a number, or null when it is blank.
export function parseNumberOrNull(value) {

  // [1] Blank stays blank
  if (value === null || value === undefined || value === NO_TEXT) return null;

  // [2] Text becomes a number
  const number = Number(value);
  const parsed = Number.isFinite(number) ? number : null;

  return parsed;
}
