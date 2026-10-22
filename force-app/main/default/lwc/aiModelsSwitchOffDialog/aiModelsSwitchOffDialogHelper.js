/*
Component Name: aiModelsSwitchOffDialog

=================================================================
=================================================================

Description: The extended methods of the switch off dialog: build the choices, the agent rows, the sentence under the title and the moves sent to Apex.

Step 1: Build the choices of a Move to box
Step 2: Build one row for each agent with the model it moves to
Step 3: Build the sentence, the button label and the moves

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, NO_TEXT } from "./aiModelsSwitchOffDialogSettings";

// Builds the choices of a Move to box: the other active models.
export function buildMoveOptions(options) {

  // [1] One choice for each model the agents can move to
  const modelOptions = options && options.modelOptions ? options.modelOptions : [];
  const moveOptions = modelOptions.map((modelOption) => ({ value: modelOption.modelId, label: modelOption.label }));

  return moveOptions;
}

// Builds one row for each agent, with the model it moves to now. An agent the admin has not changed moves to the first model.
export function buildAgentViews(options, choices) {

  // [1] The model an unchanged agent moves to
  const moveOptions = buildMoveOptions(options);
  const firstValue = moveOptions.length > 0 ? moveOptions[0].value : NO_TEXT;

  // [2] One row for each agent, with the choices marked for it
  const agentUses = options && options.agentUses ? options.agentUses : [];
  const agentViews = agentUses.map((agentUse) => {

    const value = choices[agentUse.agentId] || firstValue;
    const agentOptions = moveOptions.map((moveOption) => ({ ...moveOption, isSelected: moveOption.value === value }));

    return { key: agentUse.agentId, agentId: agentUse.agentId, agentName: agentUse.agentName, userCount: agentUse.userCount, agentOptions };
  });

  return agentViews;
}

// Builds the sentence parts under the title: the model name, then how many agents use it.
export function buildMessageParts(options, modelName) {

  // [1] Count the agents and pick the word
  const agentCount = options && options.agentUses ? options.agentUses.length : 0;
  const agentWord = agentCount === 1 ? LABELS.activeAgentOne : LABELS.activeAgentMany;
  const afterName = LABELS.isUsedBy + agentCount + agentWord + LABELS.stopAnswering;

  return { modelName, afterName, agentCount };
}

// Builds the label of the main button.
export function buildConfirmLabel(agentCount, isSaving) {

  // [1] The button says so while it works
  if (isSaving) return LABELS.saving;

  // [2] With no agents it is just Switch off
  if (agentCount === 0) return LABELS.switchOff;

  // [3] Otherwise say how many agents move
  const ending = agentCount === 1 ? LABELS.moveAgentOne : LABELS.moveAgentMany;

  return LABELS.movePrefix + agentCount + ending;
}

// Builds the moves for Apex: one { agentId, newModelId } for each agent.
export function buildMoves(options, choices) {

  // [1] One move for each agent, an unchanged agent going to the first model
  const moveOptions = buildMoveOptions(options);
  const firstValue = moveOptions.length > 0 ? moveOptions[0].value : null;
  const agentUses = options && options.agentUses ? options.agentUses : [];
  const moves = agentUses.map((agentUse) => ({ agentId: agentUse.agentId, newModelId: choices[agentUse.agentId] || firstValue }));

  return moves;
}
