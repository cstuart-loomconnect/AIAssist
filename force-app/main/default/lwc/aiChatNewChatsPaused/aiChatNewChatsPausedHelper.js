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

import { LABELS, COUNT_PLACEHOLDER, META_SEPARATOR, TIME_FORMAT_OPTIONS } from "./aiChatNewChatsPausedSettings";

// Turns a date and time into the time of day, in the user's own locale. A blank value gives a blank label.
export function formatTime(value) {

  // [1] Nothing to show when there is no value
  if (!value) return "";

  // [2] Write the time of day
  const date = new Date(value);
  const timeLabel = date.toLocaleTimeString([], TIME_FORMAT_OPTIONS);

  return timeLabel;
}

// Builds the small line under the conversation title, for example "Last message 09:41 · 6 messages".
export function buildMetaLabel(conversation) {

  // [1] Write the message count
  const messageCount = String(conversation.messageCount);
  const countLabel = LABELS.messagesCount.replace(COUNT_PLACEHOLDER, messageCount);

  // [2] Write the time of the last message
  const timeLabel = formatTime(conversation.lastActivity);

  // [3] Join the pieces
  const metaLabel = `${LABELS.lastMessage} ${timeLabel}${META_SEPARATOR}${countLabel}`;

  return metaLabel;
}
