/*
Component Name: aiChatErrorCard

=================================================================
=================================================================

Description: Settings for aiChatErrorCard: the label text and the retry event name.

Step 1: Hold the label text the template shows
Step 2: Hold the name of the event sent to the parent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Event sent to the parent
export const EVENT_RETRY = "retry"; // Sent when the user clicks Try again. No detail.

// Label text shown in the template
export const LABELS = {
  providerErrorHeading: "Couldn’t reach the AI service",
  providerErrorBody: "It didn’t respond in time. Nothing was lost — try again.",
  tryAgain: "Try again",
  ref: "Ref"
};
