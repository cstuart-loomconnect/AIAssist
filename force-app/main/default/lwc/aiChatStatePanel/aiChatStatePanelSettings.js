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

// The variants that have a hand-drawn icon in the template. The parent passes one of these (or one of the ICONS keys) in the variant property.
export const VARIANT_INACTIVE = "inactive";
export const VARIANT_MAINTENANCE = "maintenance";

// The icon shown for each variant that uses a lightning-icon.
export const ICONS = {
  channel: "utility:ban",
  noagent: "utility:info",
  space: "utility:expand_alt",
  error: "utility:error"
};

// The icon shown when the variant has none of its own.
export const ICON_DEFAULT = "utility:info";
