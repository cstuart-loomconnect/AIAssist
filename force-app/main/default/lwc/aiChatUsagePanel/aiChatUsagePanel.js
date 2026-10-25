/*
Component Name: aiChatUsagePanel

=================================================================
=================================================================

Description: Shows the user how much of each usage limit they have used today, in a panel that opens from the chat header.

Step 1: The parent (aiAssistChat) passes in a meter for each of the three usage limits
Step 2: The component shows a row for each, with the amount used and when it resets
Step 3: A limit the policy sets also gets a bar, amber when nearly used up and red when used up
Step 4: The close button, or the Escape key, tells the parent to close the panel; inside a menu it has no heading or close button

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { LABELS, KEY_ESCAPE, CLOSE_BUTTON_SELECTOR, PANEL_CLASS, PANEL_CLASS_EMBEDDED, EVENT_CLOSE } from "./aiChatUsagePanelSettings";
import { buildRows } from "./aiChatUsagePanelHelper";

// Opens from the chat header. Shows each of the three usage limits and how much of it the user has used today.
export default class AiChatUsagePanel extends LightningElement {

  // Values passed in by the parent component
  @api meters; // [{ limitType: 'TOKENS' | 'CONVERSATIONS' | 'OPEN', used, max }]; max is empty when the policy sets no limit
  @api idleTimeoutMinutes; // Minutes without activity before a conversation stops counting as open; empty for never
  @api embedded = false; // True when the panel sits inside another menu, so it drops its own heading, close button, footer and box

  // Values the template reads
  labels = LABELS;

  // The rows the template shows.
  get rows() {

    // [1] Hand the work to the helper
    return buildRows(this.meters, this.idleTimeoutMinutes);
  }

  // True when the panel shows its own heading, close button and footer.
  get showHeading() {

    return !this.embedded;
  }

  // The classes of the panel, plain when it sits inside a menu.
  get panelClass() {

    return this.embedded ? PANEL_CLASS_EMBEDDED : PANEL_CLASS;
  }

  // Moves focus into the panel when it opens, so Escape works from the keyboard.
  @api
  focus() {

    // [1] Find the close button, the first thing in the panel
    const closeButton = this.template.querySelector(CLOSE_BUTTON_SELECTOR);

    // [2] Focus it when it has drawn
    if (closeButton) closeButton.focus();
  }

  // The user pressed a key in the panel.
  handleKeyDown(event) {

    // [1] Close on Escape only
    if (event.key === KEY_ESCAPE) this.handleClose();
  }

  // Tells the parent the user wants the panel closed.
  handleClose() {

    this.dispatchEvent(new CustomEvent(EVENT_CLOSE));
  }
}
