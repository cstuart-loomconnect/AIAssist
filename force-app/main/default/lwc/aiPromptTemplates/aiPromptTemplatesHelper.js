/*
Component Name: aiPromptTemplates

=================================================================
=================================================================

Description: The extended methods of the AI Prompt Templates tab: the blank template, the moves list and error text.

Step 1: Build a blank template for the New template button
Step 2: Build the list of moves Apex needs to archive a template
Step 3: Turn an error into text for the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, NEW_TEMPLATE } from "./aiPromptTemplatesSettings";

// Builds a fresh copy of the blank template, so the editor never changes the shared one.
export function buildNewTemplate() {

  // [1] Copy the blank values
  const newTemplate = { ...NEW_TEMPLATE };

  return newTemplate;
}

// Builds the moves Apex expects: one { agentId, newTemplateId } for each agent, a blank id meaning the default template.
export function buildMoves(moves) {

  // [1] The dialog may send nothing when no agent uses the template
  const moveList = moves || [];
  const apexMoves = [];

  // [2] Turn a blank choice into null
  moveList.forEach((move) => {
    const newTemplateId = move.newTemplateId ? move.newTemplateId : null;
    apexMoves.push({ agentId: move.agentId, newTemplateId });
  });

  return apexMoves;
}

// Turns an error from Apex or JavaScript into text that is safe to show.
export function formatErrorMessage(error) {

  // [1] An Apex refusal carries its message in the body
  const errorBody = error && error.body;
  const bodyMessage = errorBody && errorBody.message;
  if (bodyMessage) return bodyMessage;

  // [2] A plain error has a message
  const plainMessage = error && error.message;
  if (plainMessage) return plainMessage;

  return LABELS.fallbackError;
}
