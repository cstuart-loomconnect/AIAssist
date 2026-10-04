/*
Class Name: AIAgentViolationRuleTrigger

=================================================================
=================================================================

Description: Trigger for AIAgentViolationRule__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================
Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          After insert and update warn when an agent has more AI evaluated rules than are used.
*/
trigger AIAgentViolationRuleTrigger on AIAgentViolationRule__c(
  before insert,
  before update,
  after insert,
  after update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIAgentViolationRuleTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIAgentViolationRuleTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
  }

  // After Context
  if (Trigger.isAfter) {
    AIAgentViolationRuleTriggerHandler.handleAfterSave(Trigger.new);
  }
}
