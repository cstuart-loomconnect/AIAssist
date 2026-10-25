/*
Component Name: aiPromptTemplatesUsedBy

=================================================================
=================================================================

Description: The extended methods of the Used by tab: the rows and the error text.

Step 1: Build one view per agent
Step 2: Turn an error into text for the admin

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { PILL_ACTIVE_CLASS, PILL_INACTIVE_CLASS, LABELS } from "./aiPromptTemplatesUsedBySettings";

// Builds one view per agent: its counts, its status pill and a note when it uses the template as the default.
export function buildAgentViews(agentUses) {

  // [1] Nothing loaded yet means no rows
  const agentList = agentUses || [];

  // [2] One view for each agent
  const agentViews = agentList.map((agentUse) => {
    const statusLabel = agentUse.isActive ? LABELS.active : LABELS.inactive;
    const statusClass = agentUse.isActive ? PILL_ACTIVE_CLASS : PILL_INACTIVE_CLASS;
    const fallbackText = agentUse.usesFallback ? LABELS.usesDefault : "";

    return { key: agentUse.agentId, agentName: agentUse.agentName, fallbackText, userCount: agentUse.userCount || 0, openCount: agentUse.openConversationCount || 0, statusLabel, statusClass };
  });

  return agentViews;
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
