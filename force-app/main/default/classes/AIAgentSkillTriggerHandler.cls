/*
Class Name: AIAgentSkillTriggerHandler

=================================================================
=================================================================

Description: Keeps the skills given to an agent tidy: an agent has each skill once.

Step 1: Set the unique key of each link from its agent and its skill

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentSkillTriggerHandler {

    public class AIAgentSkillTriggerHandlerException extends Exception {}

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Runs before an agent skill is inserted or updated and sets its unique key, so the same skill cannot be given to an agent twice.
    public static void handleBeforeSave(List<AIAgentSkill__c> newAgentSkills) {

        try {

            // [1] Nothing to set - no links
            if (newAgentSkills == null || newAgentSkills.isEmpty()) return;

            // [2] Throw the test exception when a test asks for it
            if (isTestCustomExceptionThrown) throw new AIAgentSkillTriggerHandlerException('Test exception for AIAgentSkillTriggerHandler.handleBeforeSave');

            // [3] Build the key from the agent and the skill
            for (AIAgentSkill__c agentSkill : newAgentSkills) {

                agentSkill.UniqueKey__c = agentSkill.AIAgent__c + ':' + agentSkill.AISkill__c;
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIAgentSkillTriggerHandler', 'handleBeforeSave');
        }
    }
}
