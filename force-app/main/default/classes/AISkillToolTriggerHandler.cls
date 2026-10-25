/*
Class Name: AISkillToolTriggerHandler

=================================================================
=================================================================

Description: Keeps the tools of an AI Skill tidy: each tool is in a skill once, and the skill's Bound Object follows its bound data sources.

Step 1: Set the unique key of each tool from its skill and its data source or workflow action
Step 2: After tools change, set the Bound Object of each skill to the object of its bound data sources

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISkillToolTriggerHandler {

    public class AISkillToolTriggerHandlerException extends Exception {}

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Runs before a skill tool is inserted or updated and sets its unique key, so the same tool cannot be added to a skill twice.
    public static void handleBeforeSave(List<AISkillTool__c> newSkillTools) {

        try {

            // [1] Nothing to set - no tools
            if (newSkillTools == null || newSkillTools.isEmpty()) return;

            // [2] Throw the test exception when a test asks for it
            if (isTestCustomExceptionThrown) throw new AISkillToolTriggerHandlerException('Test exception for AISkillToolTriggerHandler.handleBeforeSave');

            // [3] Build the key from the skill and whichever tool is set
            for (AISkillTool__c skillTool : newSkillTools) {

                Id toolId = skillTool.AIDataSource__c != null ? skillTool.AIDataSource__c : skillTool.AIWorkflowAction__c;

                skillTool.UniqueKey__c = toolId == null ? null : skillTool.AISkill__c + ':' + toolId;
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AISkillToolTriggerHandler', 'handleBeforeSave');
        }
    }

    // Runs after skill tools are inserted, updated or deleted and sets the Bound Object of their skills. A skill with no bound data source is unbound and its Bound Object is blank.
    public static void handleAfterChange(List<AISkillTool__c> changedSkillTools) {

        try {

            // [1] Nothing to update - no tools
            if (changedSkillTools == null || changedSkillTools.isEmpty()) return;

            // [2] Throw the test exception when a test asks for it
            if (isTestCustomExceptionThrown) throw new AISkillToolTriggerHandlerException('Test exception for AISkillToolTriggerHandler.handleAfterChange');

            // [3] Collect the skills the tools belong to
            Set<Id> skillIds = new Set<Id>();

            for (AISkillTool__c skillTool : changedSkillTools) {

                if (skillTool.AISkill__c != null) skillIds.add(skillTool.AISkill__c);
            }

            // [4] Find the object of the bound data sources still in each skill
            Map<Id, String> boundObjectBySkillId = new Map<Id, String>();

            for (AISkillTool__c skillTool : [SELECT AISkill__c, AIDataSource__r.TargetObject__c FROM AISkillTool__c WHERE AISkill__c IN :skillIds AND AIDataSource__r.BindingType__c = 'Bound' WITH SYSTEM_MODE ORDER BY StepOrder__c ASC NULLS LAST]) {

                if (!boundObjectBySkillId.containsKey(skillTool.AISkill__c) && String.isNotBlank(skillTool.AIDataSource__r.TargetObject__c)) boundObjectBySkillId.put(skillTool.AISkill__c, skillTool.AIDataSource__r.TargetObject__c);
            }

            // [5] Update only the skills whose Bound Object changed
            List<AISkill__c> skillsToUpdate = new List<AISkill__c>();

            for (AISkill__c skill : [SELECT Id, BoundObjectApiName__c FROM AISkill__c WHERE Id IN :skillIds WITH SYSTEM_MODE]) {

                String boundObjectName = boundObjectBySkillId.get(skill.Id);

                if (skill.BoundObjectApiName__c != boundObjectName) skillsToUpdate.add(new AISkill__c(Id = skill.Id, BoundObjectApiName__c = boundObjectName));
            }

            if (!skillsToUpdate.isEmpty()) Database.update(skillsToUpdate, AccessLevel.SYSTEM_MODE);

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AISkillToolTriggerHandler', 'handleAfterChange');
        }
    }
}
