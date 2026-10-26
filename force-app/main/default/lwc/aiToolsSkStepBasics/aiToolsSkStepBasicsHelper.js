/*
Component Name: aiToolsSkStepBasics

=================================================================
=================================================================

Description: The extended methods of step 1 of the skill wizard: make an API name from the name, and build the When To Use It counter.

Step 1: Make an API name from the name the admin typed
Step 2: Count the When To Use It text and say whether it is too short or too long

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { DESCRIPTION_MIN_LENGTH, DESCRIPTION_MAX_LENGTH, COUNTER_CLASS, COUNTER_BAD_CLASS, NO_TEXT, LABELS } from "./aiToolsSkStepBasicsSettings";

// Makes an API name from the skill name: words joined with underscores, starting with a letter, such as Account_Summary.
export function buildDeveloperName(skillName) {

  // [1] Split the name into words and capitalise each
  const words = (skillName || NO_TEXT).split(/[^A-Za-z0-9]+/).filter((word) => word.length > 0);
  const joinedName = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join("_");

  // [2] A name must start with a letter
  const safeName = /^[A-Za-z]/.test(joinedName) || joinedName.length === 0 ? joinedName : "Skill_" + joinedName;

  return safeName;
}

// Builds the counter under When To Use It: how many characters of the most allowed, red while it is too short or too long.
export function buildCounterView(description) {

  // [1] Count the characters the trigger counts
  const descriptionLength = (description || NO_TEXT).trim().length;
  const isBad = descriptionLength < DESCRIPTION_MIN_LENGTH || descriptionLength > DESCRIPTION_MAX_LENGTH;

  // [2] Write the counter
  const shortNote = descriptionLength < DESCRIPTION_MIN_LENGTH ? LABELS.counterTooShort : NO_TEXT;
  const counterView = { text: descriptionLength + LABELS.counterSeparator + DESCRIPTION_MAX_LENGTH + shortNote, counterClass: isBad ? COUNTER_BAD_CLASS : COUNTER_CLASS };

  return counterView;
}
