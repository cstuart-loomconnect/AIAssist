/*
Component Name: aiChatMessageList

=================================================================
=================================================================

Description: Settings for aiChatMessageList: the near-bottom distance, class names, the scroll selector, the scroll behaviour, event names and label text.

Step 1: Hold the distance that counts as near the bottom
Step 2: Hold the class names and the selector for the scroll area
Step 3: Hold the scroll behaviour used by the jump to latest button
Step 4: Hold the event names sent to the parent
Step 5: Hold the label text the template shows

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

// Class names for the jump to latest button: the quiet one, and the accent one shown when a new reply arrived out of view
export const CLASS_JUMP = "jump slds-grid slds-grid_vertical-align-center";
export const CLASS_JUMP_NEW = "jump jump_new slds-grid slds-grid_vertical-align-center";

// How the jump to latest button scrolls: smoothly, or at once when the user asks their device for less motion
export const SCROLL_BEHAVIOR_SMOOTH = "smooth";
export const SCROLL_BEHAVIOR_INSTANT = "auto";
export const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

// Events sent to the parent. Neither has a detail.
export const EVENT_LOAD_EARLIER = "loadearlier";
export const EVENT_RETRY = "retry";

// Label text shown in the template
export const LABELS = {
  showEarlier: "Show earlier messages",
  jumpToLatest: "Jump to latest",
  newReply: "New reply"
};
