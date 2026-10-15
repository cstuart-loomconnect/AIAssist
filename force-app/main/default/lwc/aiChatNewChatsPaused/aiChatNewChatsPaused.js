/*
Component Name: aiChatNewChatsPaused

=================================================================
=================================================================

Description: Tells the user that new conversations are paused and offers the conversation that is already open on this record.

Step 1: The parent (aiAssistChat) passes in the open conversation for this record, or nothing when there is none
Step 2: The component shows the heading and the explanation
Step 3: When there is an open conversation, it shows a card with its title, last message time and message count
Step 4: When the user clicks the card, the component tells the parent which conversation to open

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_CONTINUE } from "./aiChatNewChatsPausedSettings";
import { buildMetaLabel } from "./aiChatNewChatsPausedHelper";

// Shown instead of a new conversation while the user's AIUsagePolicy__c.IsUserInitiatedChatEnabled__c is off - offers the Active conversation on this record, if there is one.
export default class AiChatNewChatsPaused extends LightningElement {

  // Values passed in by the parent component
  @api openConversation; // { id, title, lastActivity, messageCount }, or empty when no conversation is open on this record

  // Values the template reads
  labels = LABELS;

  // The small line under the conversation title.
  get metaLabel() {

    // [1] No conversation, no line
    const conversation = this.openConversation;

    if (!conversation) return "";

    // [2] Hand the work to the helper
    return buildMetaLabel(conversation);
  }

  // Tells the parent which conversation the user chose to carry on with.
  handleContinue() {

    // [1] Send the continue event with the id of the open conversation
    const detail = { conversationId: this.openConversation.id };

    this.dispatchEvent(new CustomEvent(EVENT_CONTINUE, { detail }));
  }
}
