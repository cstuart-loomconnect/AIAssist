/*
Component Name: aiChatStatePanel

=================================================================
=================================================================

Description: Shows a centred full-window message for every state where the chat itself cannot be used.

Step 1: The parent (aiAssistChat) passes in the variant, the heading and the body text
Step 2: The panel picks an icon that matches the variant
Step 3: When the parent passes an action label, the panel shows a button and tells the parent when it is clicked
Step 4: When the parent passes a footer, the panel shows it along the bottom

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

import { LightningElement, api } from "lwc";
import { VARIANT_INACTIVE, VARIANT_MAINTENANCE, ICONS, ICON_DEFAULT } from "./aiChatStatePanelSettings";

// A centred full-window message for every state where the chat itself can't be used - app off, maintenance, channel not allowed, no Agent, not enough room, failed to load.
export default class AiChatStatePanel extends LightningElement {

  // Values passed in by the parent component
  @api variant; // 'inactive' | 'maintenance' | 'channel' | 'noaccess' | 'noagent' | 'space' | 'error'
  @api heading; // The large line of text
  @api body; // The text under the heading
  @api actionLabel; // Text on the button; no button shows when this is empty
  @api footer; // Small text along the bottom; no footer shows when this is empty

  // True when the variant is the app-off state, which has its own drawn icon.
  get isInactive() {

    // [1] Compare the variant the parent passed in with the inactive variant
    const isInactiveVariant = this.variant === VARIANT_INACTIVE;

    return isInactiveVariant;
  }

  // True when the variant is the maintenance state, which has its own drawn icon.
  get isMaintenance() {

    // [1] Compare the variant the parent passed in with the maintenance variant
    const isMaintenanceVariant = this.variant === VARIANT_MAINTENANCE;

    return isMaintenanceVariant;
  }

  // The lightning-icon name for the current variant.
  get iconName() {

    // [1] Look the icon up by variant, and fall back to the default icon
    const variantIcon = ICONS[this.variant];
    const iconName = variantIcon || ICON_DEFAULT;

    return iconName;
  }

  // Tells the parent that the button was clicked.
  handleAction() {

    // [1] Send the action event to the parent
    this.dispatchEvent(new CustomEvent("action"));
  }
}
