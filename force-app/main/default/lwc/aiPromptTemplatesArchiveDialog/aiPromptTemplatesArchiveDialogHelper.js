/*
Component Name: aiPromptTemplatesArchiveDialog

=================================================================
=================================================================

Description: The extended methods of the archive dialog: the title, the explanation, the choices and the moves.

Step 1: Build the title and the explanation
Step 2: Build the choices of each agent and the button label
Step 3: Build the list of moves to send to the parent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS } from "./aiPromptTemplatesArchiveDialogSettings";

// Builds the list of choices for a Move to box: the default first, then the other templates.
export function buildMoveOptions(options, templateId) {

  // [1] The default (fallback) comes first and has a blank value
  const moveOptions = [{ label: LABELS.defaultOption, value: "" }];

  // [2] Add each template, leaving out the one being archived
  const templateOptions = options && options.templateOptions ? options.templateOptions : [];
  templateOptions.forEach((templateOption) => {
    if (templateOption.templateId === templateId) return;
    moveOptions.push({ label: templateOption.label, value: templateOption.templateId });
  });

  return moveOptions;
}

// Builds one view per agent with the choice it has now.
export function buildAgentViews(options, choices) {

  // [1] One row for each agent
  const agentUses = options && options.agentUses ? options.agentUses : [];
  const agentViews = agentUses.map((agentUse) => ({ key: agentUse.agentId, agentId: agentUse.agentId, agentName: agentUse.agentName, value: choices[agentUse.agentId] || "" }));

  return agentViews;
}

// Builds the sentence under the title: the name, how many agents use it and where they go.
export function buildMessageParts(options, templateName) {

  // [1] Count the agents
  const agentCount = options && options.agentUses ? options.agentUses.length : 0;
  const agentWord = agentCount === 1 ? "agent" : "agents";
  const defaultName = options && options.defaultName ? options.defaultName : LABELS.defaultOption;

  // [2] Say what happens to them
  const beforeName = " is used by " + agentCount + " active " + agentWord + ". Pick where each one moves to. Agents moved to the default use ";

  return { templateName, beforeName, defaultName, agentCount };
}

// Builds the label of the main button.
export function buildConfirmLabel(agentCount) {

  // [1] With no agents it is just Archive
  if (agentCount === 0) return LABELS.archive;

  // [2] Otherwise say how many agents move
  const ending = agentCount === 1 ? LABELS.moveAgentOne : LABELS.moveAgentMany;

  return LABELS.movePrefix + agentCount + ending;
}

// Builds the moves for Apex: one { agentId, newTemplateId } for each agent.
export function buildMoves(options, choices) {

  // [1] One move for each agent, a blank choice meaning the default
  const agentUses = options && options.agentUses ? options.agentUses : [];
  const moves = agentUses.map((agentUse) => ({ agentId: agentUse.agentId, newTemplateId: choices[agentUse.agentId] || null }));

  return moves;
}
