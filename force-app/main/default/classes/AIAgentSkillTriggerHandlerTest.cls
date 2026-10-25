/*
Class Name: AIAgentSkillTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Agent Skill Trigger Handler: the unique key that stops a skill being given to an agent twice.

=================================================================
=================================================================
Applicable Classes:

AIAgentSkillTrigger: Coverage TBC
AIAgentSkillTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentSkillTriggerHandlerTest {

    // testScenario1: Giving a skill to an agent -> the link's unique key is the agent Id and the skill Id.
    // testScenario2: Giving the same skill to an agent twice -> the second save is refused.
    // testScenario3: Calling AIAgentSkillTriggerHandler.handleBeforeSave with null or empty input -> nothing happens and nothing is logged.
    // testScenario4: AIAgentSkillTriggerHandler.isTestCustomExceptionThrown forces an exception -> it is logged once and the save goes ahead.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and a skill
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];

            // [2] Give the skill to the agent
            Test.startTest();
                AIAgentSkill__c agentSkill = AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true)[0];
            Test.stopTest();

            // [3] Read the link back
            AIAgentSkill__c savedLink = [SELECT UniqueKey__c FROM AIAgentSkill__c WHERE Id = :agentSkill.Id];

            // [4] Check the key
            Assert.areEqual(agent.Id + ':' + skill.Id, savedLink.UniqueKey__c, 'The key should be the agent Id and the skill Id.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that already has a skill
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);

            // [2] Try to give the same skill again
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, false)[0], false);
            Test.stopTest();

            // [3] Check the second save was refused
            Assert.areEqual(false, saveResult.isSuccess(), 'An agent should not have the same skill twice.');
            Assert.areEqual(1, [SELECT COUNT() FROM AIAgentSkill__c WHERE AIAgent__c = :agent.Id], 'The agent should still have one skill.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Call the handler with null and empty input
            Test.startTest();
                AIAgentSkillTriggerHandler.handleBeforeSave(null);
                AIAgentSkillTriggerHandler.handleBeforeSave(new List<AIAgentSkill__c>());
            Test.stopTest();

            // [2] Count the logs
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [3] Check nothing was logged
            Assert.areEqual(0, platformLogCount, 'Null or empty input should log nothing.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and a skill, and ask the handler to throw
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAgentSkillTriggerHandler.isTestCustomExceptionThrown = true;

            // [2] Give the skill to the agent
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, false)[0], false);
            Test.stopTest();

            // [3] Count the logs for the handler
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentSkillTriggerHandler' AND MethodName__c = 'handleBeforeSave'];

            // [4] Check the save went ahead and the exception was logged once
            Assert.areEqual(true, saveResult.isSuccess(), 'The exception should not block the save.');
            Assert.areEqual(1, platformLogCount, 'The exception should be logged once.');
        }
    }
}
