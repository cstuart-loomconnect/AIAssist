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

// Text shown to the user. The {0} in messagesCount is replaced with the number of messages.
export const LABELS = {
  newChatsPausedHeading: "New conversations are paused",
  newChatsPausedBody: "Your admin has stopped new chats for now. You can still carry on with a conversation that’s already open.",
  openOnRecord: "Open on this record",
  continueLabel: "Continue",
  noOpenConversation: "No open conversation? Contact your Salesforce admin.",
  lastMessage: "Last message",
  messagesCount: "{0} messages"
};

// The text inside messagesCount that is replaced with the number of messages.
export const COUNT_PLACEHOLDER = "{0}";

// The text between the last message time and the message count.
export const META_SEPARATOR = " · ";

// How the time of the last message is written: hours and minutes in the user's own locale.
export const TIME_FORMAT_OPTIONS = { hour: "2-digit", minute: "2-digit" };

// The name of the event sent to the parent.
export const EVENT_CONTINUE = "continue";
