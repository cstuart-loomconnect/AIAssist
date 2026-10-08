/*
Class Name: AIModelConfigurationTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new model configuration: its unique External Id, derived from its name so the configuration can move between orgs.

It does nothing while AIAssistSettings__c.IsEnabled__c is off. A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
TBC          TBC                      TBC
*/

public inherited sharing class AIModelConfigurationTriggerHandler {
  public class AIModelConfigurationTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIModelConfiguration__c> newRecords
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIModelConfigurationTriggerHandlerException(
          'Test exception for AIModelConfigurationTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIModelConfigurationTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }
}
