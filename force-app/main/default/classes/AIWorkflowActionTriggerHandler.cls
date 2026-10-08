/*
Class Name: AIWorkflowActionTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new workflow action, derived from its required Action Name. The model names an action it suggests by this name.

Safe in the subscriber's transactions: the trigger is on the package's own AIWorkflowAction__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIWorkflowActionTriggerHandler {
  public class AIWorkflowActionTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIWorkflowAction__c> newRecords) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIWorkflowActionTriggerHandlerException(
          'Test exception for AIWorkflowActionTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIWorkflowActionTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }
}
