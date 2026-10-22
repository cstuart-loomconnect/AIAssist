/*
Component Name: aiToolsDsSaveDialog

=================================================================
=================================================================

Description: The extended methods of the save dialog: write its title and its message.

Step 1: Write the title with the name of the data source
Step 2: Write the message with the number of agents

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LABELS } from "./aiToolsDsSaveDialogSettings";

// Writes the title, such as Save changes to "Client summary"?
export function buildTitle(sourceName) {

  // [1] Put the name between the two parts of the title
  const title = LABELS.titleStart + sourceName + LABELS.titleEnd;

  return title;
}

// Writes how many agents use the data source.
export function buildCountText(agentCount) {

  // [1] One agent is singular, any other number is plural
  const endText = agentCount === 1 ? LABELS.messageOne : LABELS.messageMany;
  const countText = String(agentCount) + endText;

  return countText;
}
