/*
Class Name: AIAgentTrigger

=================================================================
=================================================================

Description: Trigger for AIAgent__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAgentTrigger on AIAgent__c(after update) {
  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isUpdate) {
      AIAgentTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.new);
    }
  }

}
