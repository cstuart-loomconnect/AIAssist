/*
Class Name: AIAgentViolationRuleTrigger

=================================================================
=================================================================

Description: Trigger for AIAgentViolationRule__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================
Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAgentViolationRuleTrigger on AIAgentViolationRule__c(
  before insert,
  before update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIAgentViolationRuleTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIAgentViolationRuleTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
  }
}
