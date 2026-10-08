/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Handler for managing AI Prompt Template events related to AI Assist,
performing the business logic that runs on the AI Prompt Template trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {
  public class AIPromptTemplateTriggerHandlerException extends Exception {
  }

  private static Boolean isBeforeUpdateHandlerRunning = false;

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  public static void handleBeforeUpdate(
    Map<Id, AIPromptTemplate__c> oldTemplatesById,
    Map<Id, AIPromptTemplate__c> newTemplatesById
  ) {
    try {
      if (!isBeforeUpdateHandlerRunning) {
        isBeforeUpdateHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIPromptTemplateTriggerHandlerException(
            'Test exception for AIPromptTemplateTriggerHandler.handleBeforeUpdate'
          );
        }

        Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById = getTemplatesWithChangedWording(
          oldTemplatesById,
          newTemplatesById
        );

        if (!templatesWithChangedWordingById.isEmpty()) {
          raiseVersionOfChangedTemplates(
            oldTemplatesById,
            templatesWithChangedWordingById
          );
        }

        isBeforeUpdateHandlerRunning = false;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIPromptTemplateTriggerHandler',
        'handleBeforeUpdate'
      );
    }
  }

  // The templates whose prompt, system context, tone or exclusion rules just changed.
  private static Map<Id, AIPromptTemplate__c> getTemplatesWithChangedWording(
    Map<Id, AIPromptTemplate__c> oldTemplatesById,
    Map<Id, AIPromptTemplate__c> newTemplatesById
  ) {
    Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById = new Map<Id, AIPromptTemplate__c>();

    if (oldTemplatesById == null || newTemplatesById == null)
      return templatesWithChangedWordingById;

    for (AIPromptTemplate__c newTemplate : newTemplatesById.values()) {
      AIPromptTemplate__c oldTemplate = oldTemplatesById.get(newTemplate.Id);
      if (oldTemplate == null)
        continue;

      Boolean hasWordingChanged =
        newTemplate.AIPrompt__c != oldTemplate.AIPrompt__c ||
        newTemplate.AISystemContext__c != oldTemplate.AISystemContext__c ||
        newTemplate.AITone__c != oldTemplate.AITone__c ||
        newTemplate.AIExclusionRules__c != oldTemplate.AIExclusionRules__c;

      if (hasWordingChanged) {
        templatesWithChangedWordingById.put(newTemplate.Id, newTemplate);
      }
    }

    return templatesWithChangedWordingById;
  }

  // Version__c goes up by one whenever the wording the model is given changes, so every reply can say which version produced it. A change to anything else leaves it alone.
  private static void raiseVersionOfChangedTemplates(
    Map<Id, AIPromptTemplate__c> oldTemplatesById,
    Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById
  ) {
    try {
      for (
        AIPromptTemplate__c changedTemplate : templatesWithChangedWordingById.values()
      ) {
        AIPromptTemplate__c oldTemplate = oldTemplatesById.get(
          changedTemplate.Id
        );

        changedTemplate.Version__c =
          (oldTemplate.Version__c == null ? 1 : oldTemplate.Version__c) + 1;
      }
    } catch (Exception e) {
      AIPlatformLogManager.logException(
        e,
        'AIPromptTemplateTriggerHandler',
        'raiseVersionOfChangedTemplates'
      );
    }
  }
}
