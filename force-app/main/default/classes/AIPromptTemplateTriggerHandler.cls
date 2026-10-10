/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Raises the version of an AI Prompt Template when the wording the model is given changes.

Step 1: Find the templates whose prompt, system context, tone or exclusion rules changed
Step 2: Raise the version of each changed template by one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {

    public class AIPromptTemplateTriggerHandlerException extends Exception {}

    private static Boolean isBeforeUpdateHandlerRunning = false;

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Runs before a template is updated and raises the version of any template whose wording changed.
    public static void handleBeforeUpdate(Map<Id, AIPromptTemplate__c> oldTemplatesById, Map<Id, AIPromptTemplate__c> newTemplatesById) {

        try {

            // [1] Stop if this handler is already running for the same save
            if (isBeforeUpdateHandlerRunning) return;
            isBeforeUpdateHandlerRunning = true;

            // [2] Throw the test exception when a test asks for it
            if (isTestCustomExceptionThrown) throw new AIPromptTemplateTriggerHandlerException('Test exception for AIPromptTemplateTriggerHandler.handleBeforeUpdate');

            // [3] Find the templates whose wording changed
            Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById = getTemplatesWithChangedWording(oldTemplatesById, newTemplatesById);

            // [4] Raise the version of each changed template
            if (!templatesWithChangedWordingById.isEmpty()) {

                raiseVersionOfChangedTemplates(oldTemplatesById, templatesWithChangedWordingById);
            }

            // [5] Allow the handler to run again on the next save
            isBeforeUpdateHandlerRunning = false;

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPromptTemplateTriggerHandler', 'handleBeforeUpdate');
        }
    }

    // Gets the templates whose prompt, system context, tone or exclusion rules just changed.
    private static Map<Id, AIPromptTemplate__c> getTemplatesWithChangedWording(Map<Id, AIPromptTemplate__c> oldTemplatesById, Map<Id, AIPromptTemplate__c> newTemplatesById) {

        // [1] Start with an empty result
        Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById = new Map<Id, AIPromptTemplate__c>();

        // [2] Nothing to compare - no old or new templates
        if (oldTemplatesById == null || newTemplatesById == null) return templatesWithChangedWordingById;

        // [3] Keep each template whose wording differs from the old copy
        for (AIPromptTemplate__c newTemplate : newTemplatesById.values()) {

            AIPromptTemplate__c oldTemplate = oldTemplatesById.get(newTemplate.Id);

            if (oldTemplate == null) continue;

            Boolean hasWordingChanged = newTemplate.AIPrompt__c != oldTemplate.AIPrompt__c || newTemplate.AISystemContext__c != oldTemplate.AISystemContext__c || newTemplate.AITone__c != oldTemplate.AITone__c || newTemplate.AIExclusionRules__c != oldTemplate.AIExclusionRules__c;

            if (hasWordingChanged) {
                templatesWithChangedWordingById.put(newTemplate.Id, newTemplate);
            }
        }

        return templatesWithChangedWordingById;
    }

    // Raises Version__c by one whenever the wording the model is given changes, so every reply can say which version produced it. A change to anything else leaves it alone.
    private static void raiseVersionOfChangedTemplates(Map<Id, AIPromptTemplate__c> oldTemplatesById, Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById) {

        try {

            // [1] Add one to the old version of each changed template, starting from 1 when it had none
            for (AIPromptTemplate__c changedTemplate : templatesWithChangedWordingById.values()) {

                AIPromptTemplate__c oldTemplate = oldTemplatesById.get(changedTemplate.Id);

                changedTemplate.Version__c = (oldTemplate.Version__c == null ? 1 : oldTemplate.Version__c) + 1;
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPromptTemplateTriggerHandler', 'raiseVersionOfChangedTemplates');
        }
    }
}
