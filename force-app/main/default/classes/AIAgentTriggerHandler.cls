/*
Class Name: AIAgentTriggerHandler

=================================================================
=================================================================

Description: Stamps the Public Id and Developer Name on a new agent. The Public Id is how an external system refers to the agent; the Developer Name is its unique External Id, derived from its name so it can move between orgs.

Safe in the subscriber's transactions: the trigger is on the package's own AIAgent__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIAgentTriggerHandler {
  public class AIAgentTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIAgent__c> newRecords) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIAgentTriggerHandlerException(
          'Test exception for AIAgentTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generatePublicId(newRecords);
      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }
}
