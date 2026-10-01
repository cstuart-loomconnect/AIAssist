/*
Class Name: AIViolationTrigger

=================================================================
=================================================================

Description: Trigger for AIViolation__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
*/
trigger AIViolationTrigger on AIViolation__c(before update, after insert) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isUpdate) {
      AIViolationTriggerHandler.handleBeforeUpdate(Trigger.oldMap, Trigger.new);
    }
  }

  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isInsert) {
      AIViolationTriggerHandler.handleAfterInsert(Trigger.new);
    }
  }

}
