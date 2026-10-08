/*
Trigger Name: AIModelConfigurationTrigger

=================================================================
=================================================================

Description: Trigger for AIModelConfiguration__c events related to AI Assist. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
TBC          TBC                      TBC
*/
trigger AIModelConfigurationTrigger on AIModelConfiguration__c(before insert) {
  AIModelConfigurationTriggerHandler.handleBeforeInsert(Trigger.new);
}
