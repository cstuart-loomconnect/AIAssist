/*
Class Name: AIConversationMessageTrigger

=================================================================
=================================================================

Description: Trigger for AIConversationMessage__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
*/
trigger AIConversationMessageTrigger on AIConversationMessage__c(
  before insert,
  after insert
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIConversationMessageTriggerHandler.handleBeforeInsert(Trigger.new);
    }
  }

  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      AIConversationMessageTriggerHandler.handleAfterInsert(Trigger.new);
    }
  }

}
