/*
Class Name: AIAssistUserTrigger

=================================================================
=================================================================

Description: Trigger for User events related to AI Assist. It only routes by context; the logic is in the handler. The switch that turns AI Assist off is checked here.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/
trigger AIAssistUserTrigger on User(after insert, after update) {

    if (!AIAssistSettingsService.isEnabled()) return;

    // After Context
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            AIAssistUserTriggerHandler.handleAfterInsert(Trigger.newMap);
        } else if (Trigger.isUpdate) {
            AIAssistUserTriggerHandler.handleAfterUpdate(Trigger.oldMap, Trigger.newMap);
        }
    }

}
