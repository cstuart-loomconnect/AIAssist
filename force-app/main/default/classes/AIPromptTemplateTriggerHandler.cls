/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Stamps the Developer Name on a new prompt template, raises Version__c whenever the wording the model is given changes (the prompt, system context, tone or exclusion rules), and allows an agent only one active template.

Safe in the subscriber's transactions: the trigger is on the package's own AIPromptTemplate__c object, does no
DML of its own and cannot recurse. It stamps and versions nothing while AIAssistSettings__c.IsEnabled__c is off; a failure there is logged and the
record still saves. The one-active-template check is an integrity rule, so it runs whatever the switch says
and fails closed. A validation rule cannot see other records, so the rule is a unique key
(ActiveAgentKey__c) plus a check here that names the template to deactivate.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
4.0          Chandler Stuart          One active template per agent: ActiveAgentKey__c and a readable refusal.
*/

public inherited sharing class AIPromptTemplateTriggerHandler {
  public class AIPromptTemplateTriggerHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  private static Set<Id> versionedIds = new Set<Id>();

  public static void handleBeforeInsert(List<AIPromptTemplate__c> newRecords) {
    stampActiveKey(newRecords, 'handleBeforeInsert');

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
    stampActiveKey(newRecordsById?.values(), 'handleBeforeUpdate');

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

  // One active template per agent. ActiveAgentKey__c is the agent's Id while the template is active and blank otherwise, and the field is unique, so the database refuses a second one even when two saves race. The check here gives the readable error, naming the template to deactivate. Runs whether or not the application is switched on, and fails closed: a record whose key could not be checked is not saved.
  private static void stampActiveKey(
    List<AIPromptTemplate__c> newRecords,
    String methodName
  ) {
    try {
      if (newRecords == null)
        return;

      Map<Id, AIPromptTemplate__c> activeByAgentId = new Map<Id, AIPromptTemplate__c>();
      Set<Id> savedIds = new Set<Id>();

      for (AIPromptTemplate__c template : newRecords) {
        if (template.Id != null)
          savedIds.add(template.Id);

        Boolean isActiveForAgent =
          template.IsActive__c == true &&
          template.AIAgent__c != null;
        template.ActiveAgentKey__c = isActiveForAgent
          ? String.valueOf(template.AIAgent__c)
          : null;
        if (!isActiveForAgent)
          continue;

        if (activeByAgentId.containsKey(template.AIAgent__c))
          template.addError(
            String.format(
              Label.AI_Error_Template_Already_Active,
              new List<String>{ activeByAgentId.get(template.AIAgent__c).Name }
            )
          );
        else
          activeByAgentId.put(template.AIAgent__c, template);
      }

      if (activeByAgentId.isEmpty())
        return;

      for (AIPromptTemplate__c existing : [
        SELECT Name, AIAgent__c
        FROM AIPromptTemplate__c
        WHERE
          AIAgent__c IN :activeByAgentId.keySet()
          AND IsActive__c = TRUE
          AND Id NOT IN :savedIds
        WITH SYSTEM_MODE
      ])
        activeByAgentId.get(existing.AIAgent__c)
          .addError(
            String.format(
              Label.AI_Error_Template_Already_Active,
              new List<String>{ existing.Name }
            )
          );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIPromptTemplateTriggerHandler',
        methodName
      );
    }
  }
}
