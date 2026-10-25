/*
Class Name: AIConversationMessageTrigger

=================================================================
=================================================================

Description: Trigger for AIConversationMessage__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIConversationMessageTrigger on AIConversationMessage__c(after insert) {
  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      if (!AIAssistSettingsService.isEnabled())
        return;
      AIConversationMessageTriggerHandler.handleAfterInsert(Trigger.new);
    }
  }

}
