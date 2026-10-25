/*
Class Name: AISkillToolTrigger

=================================================================
=================================================================

Description: Trigger for AISkillTool__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic is in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AISkillToolTrigger on AISkillTool__c(before insert, before update, after insert, after update, after delete) {
  if (!AIAssistSettingsService.isEnabled())
    return;

  // Before Context
  if (Trigger.isBefore) {
    AISkillToolTriggerHandler.handleBeforeSave(Trigger.new);
  }

  // After Context
  if (Trigger.isAfter) {
    if (Trigger.isDelete) {
      AISkillToolTriggerHandler.handleAfterChange(Trigger.old);
    } else {
      AISkillToolTriggerHandler.handleAfterChange(Trigger.new);
    }
  }

}
