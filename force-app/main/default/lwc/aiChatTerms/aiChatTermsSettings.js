/*
Component Name: aiChatTerms

=================================================================
=================================================================

Description: Settings for aiChatTerms: the label text and the event name.

Step 1: LABELS holds every piece of text the first-run terms screen shows
Step 2: AGREE_EVENT_NAME is the event sent to the parent when the user agrees

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

// Text shown on the first-run terms screen
export const LABELS = {
  termsEyebrow: "Before you start",
  termsHeading: "A few things to know about AI Assist",
  termsPiiTitle: "Personal data is masked",
  termsPiiBody: "Names, emails and phone numbers are replaced with placeholders before they reach the AI model.",
  termsWrongTitle: "Answers can be wrong",
  termsWrongBody: "Check anything important against the record before you act on it.",
  termsLoggedTitle: "Conversations are logged",
  termsLoggedBody: "Your admin can review usage and messages that break company rules.",
  termsAgreePrefix: "I’ve read the ",
  termsPolicy: "AI usage policy",
  termsAgreeSuffix: " and agree to use AI Assist in line with it.",
  termsAgree: "Agree and continue"
};

// Name of the event sent to the parent when the user agrees (the parent records the acknowledgment)
export const AGREE_EVENT_NAME = "agree";
