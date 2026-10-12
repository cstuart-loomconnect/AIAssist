/*
Component Name: aiChatMessageList

=================================================================
=================================================================

Description: Settings for aiChatMessageList: the near-bottom distance, class names, the scroll selector, event names and label text.

Step 1: Hold the distance that counts as near the bottom
Step 2: Hold the class names and the selector for the scroll area
Step 3: Hold the event names sent to the parent
Step 4: Hold the label text the template shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Scrolling
export const NEAR_BOTTOM_PX = 80; // Within this many pixels of the bottom counts as "reading the newest message"
export const SCROLL_SELECTOR = ".scroll"; // Finds the scrolling area in the template

// Class names for the scrolling area
export const CLASS_SCROLL = "scroll slds-grid slds-grid_vertical slds-grow";
export const CLASS_SCROLL_DIMMED = "scroll slds-grid slds-grid_vertical slds-grow scroll_dimmed";

// Events sent to the parent. Neither has a detail.
export const EVENT_LOAD_EARLIER = "loadearlier";
export const EVENT_RETRY = "retry";

// Label text shown in the template
export const LABELS = {
  showEarlier: "Show earlier messages"
};
