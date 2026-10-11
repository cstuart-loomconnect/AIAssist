/*
Component Name: aiChatUsageBanner

=================================================================
=================================================================

Description: Tells the user they have reached a usage limit, how far they are, and what it stops, as soon as the window opens.

Step 1: The parent (aiAssistChat) passes in the usage limit the user has reached (AIChatDataStructure.UsageLimitState)
Step 2: The component shows the limit, what it stops and a meter of how much has been used
Step 3: For the open conversations limit it offers a button to open the history, so the user can end one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, EVENT_OPEN_HISTORY } from "./aiChatUsageBannerSettings";
import { buildView } from "./aiChatUsageBannerHelper";

// Shown under the header while the user is at a usage limit. Mirrors what AIUsageLimitService would refuse on Send.
export default class AiChatUsageBanner extends LightningElement {
  // Values passed in by the parent component
  @api limitState; // { limitType, used, max, isNotifyOnly, blocksNewConversations, blocksMessages }, or empty when no limit is reached

  // Values the template reads
  labels = LABELS;

  // Everything the template shows, or nothing when no limit is reached.
  get view() {
    // [1] Hand the work to the helper
    return buildView(this.limitState);
  }

  // The banner colour: a warning when nothing is blocked, an error when something is.
  get bannerClass() {
    // [1] Pick the colour from what the limit stops
    return this.view && this.view.isNotifyOnly
      ? "banner banner_warning slds-grid slds-grid_vertical"
      : "banner banner_blocked slds-grid slds-grid_vertical";
  }

  // The meter's width.
  get meterStyle() {
    return `width:${this.view.percent}%`;
  }

  // Tells the parent the user wants the history, to end a conversation.
  handleOpenHistory() {
    this.dispatchEvent(new CustomEvent(EVENT_OPEN_HISTORY));
  }
}
