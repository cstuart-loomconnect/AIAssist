/*
Component Name: aiPromptTemplatesDetail

=================================================================
=================================================================

Description: The extended methods of the template detail card: the pills and the tab label.

Step 1: Build the pills shown beside the name
Step 2: Build the label of the Used by tab

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { PILL_LIVE_CLASS, PILL_NEUTRAL_CLASS, LABELS } from "./aiPromptTemplatesDetailSettings";

// Builds the pills beside the template name: "vN live", "Inactive" and "Default".
export function buildPillViews(savedTemplate) {

  // [1] A template that is not saved yet has no pills
  const pillViews = [];
  const isSaved = Boolean(savedTemplate && savedTemplate.templateId);
  if (!isSaved) return pillViews;

  // [2] Live or inactive
  if (savedTemplate.isActive) pillViews.push({ key: "live", label: "v" + savedTemplate.version + LABELS.live, pillClass: PILL_LIVE_CLASS });
  if (!savedTemplate.isActive) pillViews.push({ key: "inactive", label: LABELS.inactive, pillClass: PILL_NEUTRAL_CLASS });

  // [3] The fallback
  if (savedTemplate.isDefault) pillViews.push({ key: "default", label: LABELS.default, pillClass: PILL_LIVE_CLASS });

  return pillViews;
}

// Builds the label of the Used by tab, such as "Used by (2)".
export function buildUsedByLabel(savedTemplate) {

  // [1] Use the count Apex gave, or none
  const agentCount = savedTemplate && savedTemplate.agentCount ? savedTemplate.agentCount : 0;
  const usedByLabel = LABELS.tabUsedBy + " (" + agentCount + ")";

  return usedByLabel;
}
