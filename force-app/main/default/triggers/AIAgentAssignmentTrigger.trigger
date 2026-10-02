/*
Class Name: AIAgentAssignmentTrigger

=================================================================
=================================================================

Description: Trigger for AIAgentAssignment__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAgentAssignmentTrigger on AIAgentAssignment__c(
  before insert,
  before update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIAgentAssignmentTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIAgentAssignmentTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
  }
}
