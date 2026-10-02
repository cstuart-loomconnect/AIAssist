/*
Class Name: AIModelConfigurationTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new model configuration: its unique External Id, derived from its name so the configuration can move between orgs.

Safe in the subscriber's transactions: the trigger is on the package's own AIModelConfiguration__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

An active configuration of a second provider is refused with the plan label when the plan allows one provider; see AIPlanActivationService.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
4.0          Chandler Stuart          Plan check added, before insert and before update. It is not behind the application switch and it does stop the save.
*/

public inherited sharing class AIModelConfigurationTriggerHandler {
  public class AIModelConfigurationTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(
    List<AIModelConfiguration__c> newRecords
  ) {
    AIPlanActivationService.checkModelConfigurations(newRecords, null);

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

  // Only the plan check: identifiers are stamped once, on insert.
  public static void handleBeforeUpdate(
    Map<Id, AIModelConfiguration__c> oldRecordsById,
    List<AIModelConfiguration__c> newRecords
  ) {
    AIPlanActivationService.checkModelConfigurations(
      newRecords,
      oldRecordsById
    );
  }
}
