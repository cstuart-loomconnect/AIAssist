/*
Component Name: aiChatHeader

=================================================================
=================================================================

Description: The chat window's top bar: logo, title, agent picker and the New and More controls.

Step 1: The parent (aiAssistChat) passes in the title, the agents, the badge and the user's usage meters
Step 2: The header shows the logo, the title and, when there is more than one agent, a picker
Step 3: The New, End and More buttons follow; the More menu opens with the usage limits, then History and Export
Step 4: Every click is reported to the parent as an event; the header changes nothing itself

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS, BADGE, BADGE_CLASSES, BADGE_CLASS_DEFAULT, LOGO_STROKE, ARIA_TRUE, ARIA_FALSE, MENU_VALUE_END, MENU_VALUE_EXPORT, MENU_VALUE_SHARE, ROW_KEY_HISTORY, ROW_KEY_USAGE } from "./aiChatHeaderSettings";

// Picks the colour of the logo mark: dimmed when the window is off.
export function getLogoStroke(isMuted) {

  // [1] Pick the colour from whether the window is dimmed
  const logoStroke = isMuted ? LOGO_STROKE.MUTED : LOGO_STROKE.NORMAL;

  return logoStroke;
}

// Writes the text of the badge beside the title. Nothing when there is no badge.
export function getBadgeLabel(badge) {

  // [1] Pick the text from the badge
  if (badge === BADGE.DEBUG) return LABELS.debugBadge;
  if (badge === BADGE.MAINTENANCE) return LABELS.maintenanceBadge;
  if (badge === BADGE.OFF) return LABELS.inactiveBadge;

  return null;
}

// Picks the classes of the badge beside the title.
export function getBadgeClass(badge) {

  // [1] Use the classes for this badge, or the plain badge when it is not one we know
  const badgeClass = BADGE_CLASSES[badge] || BADGE_CLASS_DEFAULT;

  return badgeClass;
}

// Builds the agents for the picker, marking the one that is selected.
export function buildAgentOptions(agents, selectedAgentId) {

  // [1] The parent may not have set any agents yet
  const agentList = agents || [];
  const agentOptions = [];

  // [2] Build one option for each agent
  agentList.forEach((agent) => {

    const isSelected = agent.id === selectedAgentId;
    const checked = isSelected ? ARIA_TRUE : ARIA_FALSE;

    agentOptions.push({ ...agent, isSelected, checked });
  });

  return agentOptions;
}

// Answers whether the parent offered the End conversation item, which the header shows as its own button.
export function hasEndItem(menuItems) {

  // [1] The parent may not have set any items yet
  const itemList = menuItems || [];

  // [2] Look for the End item
  const hasEnd = itemList.some((item) => item.value === MENU_VALUE_END);

  return hasEnd;
}

// Builds the rows of the More menu: History, Usage, then each item the parent offered (Export, Share) except End.
export function buildMenuRows(menuItems, showHistory, showUsage) {

  // [1] The parent may not have set any items yet
  const itemList = menuItems || [];
  const rows = [];

  // [2] History is always the first row when the history is offered
  if (showHistory) rows.push({ key: ROW_KEY_HISTORY, value: ROW_KEY_HISTORY, label: LABELS.historyShort, hint: LABELS.historyHint, isHistory: true, isUsage: false, isExport: false, isShare: false });

  // [2b] Usage follows History when the user has usage limits to see
  if (showUsage) rows.push({ key: ROW_KEY_USAGE, value: ROW_KEY_USAGE, label: LABELS.usageShort, hint: LABELS.usageHint, isHistory: false, isUsage: true, isExport: false, isShare: false });

  // [3] Add the other items, leaving out End, which has its own button
  itemList.forEach((item) => {

    if (item.value === MENU_VALUE_END) return;

    rows.push({ key: item.value, value: item.value, label: item.label, hint: item.hint || LABELS.exportHint, isHistory: false, isUsage: false, isExport: item.value === MENU_VALUE_EXPORT, isShare: item.value === MENU_VALUE_SHARE });
  });

  return rows;
}
