/*
Class Name: AIPromptTemplateTrigger

=================================================================
=================================================================

Description: Trigger for AIPromptTemplate__c events related to AI Assist. Runs only on the package's own object, never on a subscriber's. It only routes by context; the logic, and the switch that turns it off, are in the handler.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIPromptTemplateTrigger on AIPromptTemplate__c(before insert, before update) {
  if (!AIAssistSettingsService.isEnabled())
    return;

  // Before Context
  if (Trigger.isBefore) {
    if (Trigger.isInsert) {
      AIPromptTemplateTriggerHandler.handleBeforeSave(Trigger.new, null);
    }
    if (Trigger.isUpdate) {
      AIPromptTemplateTriggerHandler.handleBeforeUpdate(
        Trigger.oldMap,
        Trigger.newMap
      );
      AIPromptTemplateTriggerHandler.handleBeforeSave(
        Trigger.new,
        Trigger.oldMap
      );
    }
  }

}
