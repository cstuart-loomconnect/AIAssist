/*
Class Name: AIViolationRuleTrigger

=================================================================
=================================================================

Description: Trigger for AIViolationRule__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
3.0          Chandler Stuart          After insert and update warn when an agent has more AI evaluated rules than are used.
*/
trigger AIViolationRuleTrigger on AIViolationRule__c(
  before insert,
  before update,
  after insert,
  after update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIViolationRuleTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIViolationRuleTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
  }

  // After Context
  if (Trigger.isAfter) {
    AIViolationRuleTriggerHandler.handleAfterSave(Trigger.new);
  }
}
