/*
Class Name: AISkillTrigger

=================================================================
=================================================================

Description: Trigger for AISkill__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AISkillTrigger on AISkill__c(before insert, before update) {
  if (!AIAssistSettingsService.isEnabled())
    return;

  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AISkillTriggerHandler.handleBeforeSave(Trigger.new, null);
    }
    if (Trigger.isUpdate) {
      AISkillTriggerHandler.handleBeforeSave(Trigger.new, Trigger.oldMap);
    }
  }

}
