/*
Class Name: AIUsagePolicyTrigger

=================================================================
=================================================================

Description: Trigger for AIUsagePolicy__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIUsagePolicyTrigger on AIUsagePolicy__c(before insert) {
  // Before Context
  if (Trigger.isBefore && Trigger.isInsert) {
    AIUsagePolicyTriggerHandler.handleBeforeInsert(Trigger.new);
  }
}
