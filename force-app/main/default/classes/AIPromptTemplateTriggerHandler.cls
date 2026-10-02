/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new prompt template, and raises Version__c whenever the wording the model is given changes (the prompt, system context, tone or exclusion rules).

Safe in the subscriber's transactions: the trigger is on the package's own AIPromptTemplate__c object, does no
DML of its own and cannot recurse. It does nothing while AIAssistSettings__c.IsEnabled__c is off.
A failure is logged and the record still saves.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIPromptTemplateTriggerHandler {
  public class AIPromptTemplateTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  private static Set<Id> versionedIds = new Set<Id>();

  public static void handleBeforeInsert(List<AIPromptTemplate__c> newRecords) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIPromptTemplateTriggerHandlerException(
          'Test exception for AIPromptTemplateTriggerHandler.handleBeforeInsert'
        );
      }

      if (newRecords == null || newRecords.isEmpty())
        return;

      AIAssistGlobalUtility.generateDeveloperName(newRecords);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPromptTemplateTriggerHandler',
        'handleBeforeInsert'
      );
    }
  }

  // Version__c goes up by one whenever the wording the model is given changes, so every reply can say which version produced it. A change to anything else leaves it alone, and a template is versioned once per transaction.
  public static void handleBeforeUpdate(
    Map<Id, AIPromptTemplate__c> oldRecordsById,
    Map<Id, AIPromptTemplate__c> newRecordsById
  ) {
    try {
      if (!AIAssistSettingsService.isEnabled())
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIPromptTemplateTriggerHandlerException(
          'Test exception for AIPromptTemplateTriggerHandler.handleBeforeUpdate'
        );
      }

      if (oldRecordsById == null || newRecordsById == null)
        return;

      for (AIPromptTemplate__c template : newRecordsById.values()) {
        AIPromptTemplate__c previous = oldRecordsById.get(template.Id);

        if (previous == null || versionedIds.contains(template.Id))
          continue;

        if (
          template.AIPrompt__c != previous.AIPrompt__c ||
          template.AISystemContext__c != previous.AISystemContext__c ||
          template.AITone__c != previous.AITone__c ||
          template.AIExclusionRules__c != previous.AIExclusionRules__c
        ) {
          template.Version__c =
            (previous.Version__c == null ? 1 : previous.Version__c) + 1;
          versionedIds.add(template.Id);
        }
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPromptTemplateTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }
}
