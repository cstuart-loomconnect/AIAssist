/*
Class Name: AIAgentWorkflowActionTrigger

=================================================================
=================================================================

Description: Trigger for AIAgentWorkflowAction__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAgentWorkflowActionTrigger on AIAgentWorkflowAction__c(
  before insert,
  before update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIAgentWorkflowActionTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIAgentWorkflowActionTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
  }
}
