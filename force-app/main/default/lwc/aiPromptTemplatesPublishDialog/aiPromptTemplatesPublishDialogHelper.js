/*
Component Name: aiPromptTemplatesPublishDialog

=================================================================
=================================================================

Description: The extended methods of the publish dialog: the title and the lines of text.

Step 1: Build the title and the sentence under it
Step 2: Build the Changed and Tested lines

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS } from "./aiPromptTemplatesPublishDialogSettings";

// Answers true when the wording changes, so the save makes a new version.
export function isNewVersion(impact) {

  // [1] Changed sections mean a new version
  const changedSections = impact && impact.changedSections ? impact.changedSections : [];
  const hasChanges = changedSections.length > 0;

  return hasChanges;
}

// Builds the title, such as: Publish v4 of "Mortgage adviser"?
export function buildTitle(impact, templateName) {

  // [1] A new version is published, and anything else is just saved
  if (isNewVersion(impact)) return "Publish v" + impact.nextVersion + ' of "' + templateName + '"?';

  return 'Save changes to "' + templateName + '"?';
}

// Builds the sentence under the title, such as "v4 replaces v3 for every agent using this template."
export function buildIntro(impact) {

  // [1] Only a new version replaces an older one
  if (!isNewVersion(impact)) return "";

  const intro = "v" + impact.nextVersion + " replaces v" + impact.currentVersion + " for every agent using this template.";

  return intro;
}

// Builds the Changed line: the headings joined with commas, or "Nothing".
export function buildChangedText(impact) {

  // [1] Join the headings
  const changedSections = impact && impact.changedSections ? impact.changedSections : [];
  const changedText = changedSections.length > 0 ? changedSections.join(", ") : LABELS.nothing;

  return changedText;
}

// Builds the Tested line.
export function buildTestedText(impact) {

  // [1] Say so when no saved message was run
  const testCount = impact && impact.testMessageCount ? impact.testMessageCount : 0;
  if (testCount === 0) return LABELS.notTested;

  // [2] Say how many were run and how many passed
  const passedCount = impact.testPassedCount || 0;
  const messageWord = testCount === 1 ? "message" : "messages";
  const testedText = "Try it run on " + testCount + " saved " + messageWord + " · " + passedCount + " passed";

  return testedText;
}

// Builds one view per agent for the table.
export function buildAgentViews(impact) {

  // [1] One row for each agent
  const agentUses = impact && impact.agentUses ? impact.agentUses : [];
  const agentViews = agentUses.map((agentUse) => ({ key: agentUse.agentId, agentName: agentUse.agentName, userCount: agentUse.userCount || 0, openCount: agentUse.openConversationCount || 0 }));

  return agentViews;
}
