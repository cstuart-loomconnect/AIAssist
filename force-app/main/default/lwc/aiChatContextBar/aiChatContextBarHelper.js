/*
Component Name: aiChatContextBar

=================================================================
=================================================================

Description: Helper functions for aiChatContextBar that build the record label.

Step 1: Keep only the parts of the label that have a value
Step 2: Join those parts with the separator

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { RECORD_LABEL_SEPARATOR } from "./aiChatContextBarSettings";

// Joins the object label and the record name into one label, leaving out any part that is empty.
export function buildRecordLabel(objectLabel, recordName) {

  // [1] Put the parts in the order they are shown
  const labelParts = [objectLabel, recordName];

  // [2] Drop the parts the parent has not set
  const filledParts = labelParts.filter(Boolean);

  // [3] Join what is left
  const recordLabel = filledParts.join(RECORD_LABEL_SEPARATOR);

  return recordLabel;
}
