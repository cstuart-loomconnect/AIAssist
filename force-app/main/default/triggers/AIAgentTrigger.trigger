/*
Class Name: AIAgentTrigger

=================================================================
=================================================================

Description: Trigger for AIAgent__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
4.0          Chandler Stuart          After update, for a change to the retention settings.
5.0          Chandler Stuart          Before update removed with the plan checks.
*/
trigger AIAgentTrigger on AIAgent__c(before insert, after update) {
  // Before Context
  if (Trigger.isBefore && Trigger.isInsert) {
    AIAgentTriggerHandler.handleBeforeInsert(Trigger.new);
  }

  // After Context
  if (Trigger.isAfter && Trigger.isUpdate) {
    AIAgentTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.new);
  }
}
