/*
Class Name: AIUsagePolicyTriggerHandler

=================================================================
=================================================================

Description: Stamps the Public Id and Developer Name on a new usage policy, derived from its Name, before insert. Identifiers are stamped once and never again, so a later rename cannot break an export that keys on the Developer Name.

Safe in the subscriber's transactions: the trigger is on the package's own AIUsagePolicy__c object, does no DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off. A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public inherited sharing class AIUsagePolicyTriggerHandler {
  public class AIUsagePolicyTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIUsagePolicy__c> newRecords) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIUsagePolicyTriggerHandlerException(
          'Test exception for AIUsagePolicyTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generatePublicId(newRecords);
      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIUsagePolicyTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }
}
