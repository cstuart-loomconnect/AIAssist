/*
Class Name: AIDataSourceTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new data source, derived from its required Source Name. The Developer Name is also the tool name the model calls, and both providers accept tool names of only 64 letters, numbers, underscores and hyphens, so it is cut to 64.

Safe in the subscriber's transactions: the trigger is on the package's own AIDataSource__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIDataSourceTriggerHandler {
  public class AIDataSourceTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeInsert(List<AIDataSource__c> newRecords) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIDataSourceTriggerHandlerException(
          'Test exception for AIDataSourceTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generateDeveloperName(newRecords);

      // The model calls the data source by this name; both providers reject a tool name longer than 64 characters.
      for (AIDataSource__c dataSource : newRecords) {
        if (
          dataSource.DeveloperName__c != null &&
          dataSource.DeveloperName__c.length() > 64
        )
          dataSource.DeveloperName__c = dataSource.DeveloperName__c.left(64);
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIDataSourceTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }
}
