/*
Class Name: AIModelConfigurationTrigger

=================================================================
=================================================================

Description: Trigger for AIModelConfiguration__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
*/
trigger AIModelConfigurationTrigger on AIModelConfiguration__c(
  before insert,
  before update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIModelConfigurationTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIModelConfigurationTriggerHandler.handleBeforeUpdate(
        Trigger.oldMap,
        Trigger.new
      );
    }
  }
}
