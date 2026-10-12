/*
Component Name: aiChatContextBar

=================================================================
=================================================================

Description: The strip under the chat header naming the record the conversation is about.

Step 1: Take the object label and record name from the parent
Step 2: Join them into one label for the record chip
Step 3: Show the PII protected badge when the parent says a synced PII Registry covers the object

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS } from "./aiChatContextBarSettings";
import { buildRecordLabel } from "./aiChatContextBarHelper";

export default class AiChatContextBar extends LightningElement {

  // Values passed in by the parent component
  @api objectLabel; // Display name of the record's object, e.g. "Account"
  @api recordName; // Name of the record the conversation is about
  @api piiProtected = false; // true when a synced PII Registry covers the object

  // Values the template reads
  labels = LABELS;

  // The object label and record name joined into the one label shown in the chip.
  get recordLabel() {

    // [1] Hand the work to the helper
    return buildRecordLabel(this.objectLabel, this.recordName);
  }
}
