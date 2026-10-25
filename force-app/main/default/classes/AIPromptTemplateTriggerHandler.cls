/*
Class Name: AIPromptTemplateTriggerHandler

=================================================================
=================================================================

Description: Keeps AI Prompt Templates consistent: the version follows the wording, and there is one active default.

Step 1: Find the templates whose prompt, system context, tone, exclusion rules or response length changed
Step 2: Raise the version of each changed template by one
Step 3: Refuse a template that would make a second active default

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateTriggerHandler {

    public class AIPromptTemplateTriggerHandlerException extends Exception {}

    // The active defaults in one save: how many already were a default, and the ones becoming one.
    private class DefaultsInSave {

        Integer unchangedCount = 0;
        List<AIPromptTemplate__c> newDefaults = new List<AIPromptTemplate__c>();
    }

    private static Boolean isBeforeUpdateHandlerRunning = false;

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    @TestVisible
    private static Boolean isTestDefaultRuleExceptionThrown = false;

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

    // Runs before a template is inserted or updated and refuses one that would be a second active default. The one default is what answers for an agent with no template of its own, so two would make that answer depend on the order they were saved. The templates in the save are the final word on themselves, so moving the default (untick one, tick another) works in a single save. oldTemplatesById is null on insert.
    public static void handleBeforeSave(List<AIPromptTemplate__c> newTemplates, Map<Id, AIPromptTemplate__c> oldTemplatesById) {

        try {

            // [1] Nothing to check - no templates
            if (newTemplates == null || newTemplates.isEmpty()) return;

            // [2] Throw the test exception when a test asks for it
            if (isTestDefaultRuleExceptionThrown) throw new AIPromptTemplateTriggerHandlerException('Test exception for AIPromptTemplateTriggerHandler.handleBeforeSave');

            // [3] Sort the active defaults in this save into those that already were one and those that are becoming one, so a save that adds no default costs no query
            DefaultsInSave defaultsInSave = getDefaultsInSave(newTemplates, oldTemplatesById);

            if (defaultsInSave.newDefaults.isEmpty()) return;

            // [4] Within this save, refuse every new default once there is already one, keeping the first
            Integer defaultsKept = defaultsInSave.unchangedCount;
            AIPromptTemplate__c survivingDefault;

            for (AIPromptTemplate__c newDefault : defaultsInSave.newDefaults) {

                if (defaultsKept > 0) {

                    newDefault.addError(Label.AI_Error_Prompt_Template_Default_Exists);

                } else {

                    survivingDefault = newDefault;
                    defaultsKept++;
                }
            }

            // [5] Refuse the surviving new default when another active default was saved outside this save
            if (survivingDefault == null) return;

            Set<Id> savedIds = new Set<Id>();

            for (AIPromptTemplate__c newTemplate : newTemplates) {

                if (newTemplate.Id != null) savedIds.add(newTemplate.Id);
            }

            if (![SELECT Id FROM AIPromptTemplate__c WHERE IsDefault__c = TRUE AND IsActive__c = TRUE AND Id NOT IN :savedIds WITH SYSTEM_MODE LIMIT 1].isEmpty()) survivingDefault.addError(Label.AI_Error_Prompt_Template_Default_Exists);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIPromptTemplateTriggerHandler', 'handleBeforeSave');
        }
    }

    // Sorts the templates in the save that are an active default after it: those that already were one (counted), and those becoming one (new, newly ticked or newly activated).
    private static DefaultsInSave getDefaultsInSave(List<AIPromptTemplate__c> newTemplates, Map<Id, AIPromptTemplate__c> oldTemplatesById) {

        // [1] Start with empty results
        DefaultsInSave defaultsInSave = new DefaultsInSave();

        // [2] Sort each active default by whether it already was one
        for (AIPromptTemplate__c newTemplate : newTemplates) {

            if (newTemplate.IsDefault__c != true || newTemplate.IsActive__c != true) continue;

            AIPromptTemplate__c oldTemplate = oldTemplatesById == null || newTemplate.Id == null ? null : oldTemplatesById.get(newTemplate.Id);
            Boolean wasActiveDefault = oldTemplate != null && oldTemplate.IsDefault__c == true && oldTemplate.IsActive__c == true;

            if (wasActiveDefault) defaultsInSave.unchangedCount++;
            else defaultsInSave.newDefaults.add(newTemplate);
        }

        return defaultsInSave;
    }

    // Gets the templates whose prompt, system context, tone, exclusion rules or response length just changed.
    private static Map<Id, AIPromptTemplate__c> getTemplatesWithChangedWording(Map<Id, AIPromptTemplate__c> oldTemplatesById, Map<Id, AIPromptTemplate__c> newTemplatesById) {

        // [1] Start with an empty result
        Map<Id, AIPromptTemplate__c> templatesWithChangedWordingById = new Map<Id, AIPromptTemplate__c>();

        // [2] Nothing to compare - no old or new templates
        if (oldTemplatesById == null || newTemplatesById == null) return templatesWithChangedWordingById;

        // [3] Keep each template whose wording differs from the old copy
        for (AIPromptTemplate__c newTemplate : newTemplatesById.values()) {

            AIPromptTemplate__c oldTemplate = oldTemplatesById.get(newTemplate.Id);

            if (oldTemplate == null) continue;

            Boolean hasWordingChanged = newTemplate.AIPrompt__c != oldTemplate.AIPrompt__c || newTemplate.AISystemContext__c != oldTemplate.AISystemContext__c || newTemplate.AITone__c != oldTemplate.AITone__c || newTemplate.AIExclusionRules__c != oldTemplate.AIExclusionRules__c || newTemplate.MaxResponseLength__c != oldTemplate.MaxResponseLength__c;

            if (hasWordingChanged) {
                templatesWithChangedWordingById.put(newTemplate.Id, newTemplate);
            }
        }

        return templatesWithChangedWordingById;
    }

    // Raises Version__c by one whenever the wording the model is given (or the length it is asked to keep to) changes, so every reply can say which version produced it. A change to anything else leaves it alone.
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
