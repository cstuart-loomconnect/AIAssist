/*
Component Name: aiPromptTemplatesList

=================================================================
=================================================================

Description: The extended methods of the template list: the row views and the search.

Step 1: Filter the rows by the search text
Step 2: Turn each row into the words and classes the template needs

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { ROW_CLASS, ROW_SELECTED_CLASS, PILL_LIVE_CLASS, PILL_INACTIVE_CLASS, LABELS } from "./aiPromptTemplatesListSettings";

// Builds the text of the second line of a row, such as "v3 · 2 agents".
export function formatDetailLine(row) {

  // [1] The version always comes first
  const versionText = "v" + row.version;

  // [2] Say how many agents use it
  const agentCount = row.agentCount || 0;
  const agentWord = agentCount === 1 ? LABELS.agentOne : LABELS.agentMany;
  const usedText = agentCount === 0 ? LABELS.notUsed : agentCount + " " + agentWord;

  return versionText + " · " + usedText;
}

// Builds one view per row that matches the search text.
export function buildRowViews(rows, searchText, selectedId) {

  // [1] The parent may not have loaded the rows yet
  const rowList = rows || [];
  const searchLower = (searchText || "").trim().toLowerCase();
  const rowViews = [];

  // [2] Keep the rows whose name holds the search text
  rowList.forEach((row) => {
    const nameLower = (row.templateName || "").toLowerCase();
    const isMatch = nameLower.includes(searchLower);
    if (!isMatch) return;

    // [3] Pick the status word and its colour
    const isSelected = row.templateId === selectedId;
    let statusLabel = LABELS.statusInactive;
    let statusClass = PILL_INACTIVE_CLASS;
    if (row.isActive) {
      statusLabel = LABELS.statusLive;
      statusClass = PILL_LIVE_CLASS;
    }
    if (row.isDefault) {
      statusLabel = LABELS.statusDefault;
      statusClass = PILL_LIVE_CLASS;
    }

    // [4] Build the view
    const rowClass = isSelected ? ROW_SELECTED_CLASS : ROW_CLASS;
    const detailLine = formatDetailLine(row);
    rowViews.push({ key: row.templateId, templateId: row.templateId, templateName: row.templateName, rowClass, statusLabel, statusClass, detailLine });
  });

  return rowViews;
}
