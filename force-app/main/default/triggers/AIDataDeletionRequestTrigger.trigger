/*
Class Name: AIDataDeletionRequestTrigger

=================================================================
=================================================================

Description: Trigger for AIDataDeletionRequest__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Routes by context to the handler's handle methods.
*/
trigger AIDataDeletionRequestTrigger on AIDataDeletionRequest__c(
  before insert,
  before update,
  after update
) {
  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIDataDeletionRequestTriggerHandler.handleBeforeInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
      AIDataDeletionRequestTriggerHandler.handleBeforeUpdate(
        Trigger.oldMap,
        Trigger.new
      );
    }
  }

  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isUpdate) {
      AIDataDeletionRequestTriggerHandler.handleAfterUpdate(
        Trigger.oldMap,
        Trigger.new
      );
    }
  }

}
