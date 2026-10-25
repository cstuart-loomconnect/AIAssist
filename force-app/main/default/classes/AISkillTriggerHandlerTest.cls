/*
Class Name: AISkillTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Skill Trigger Handler: the When To Use It length, the activation checks (tools, @ names, one bound object) and the locked API name.

=================================================================
=================================================================
Applicable Classes:

AISkillTrigger: Coverage TBC
AISkillTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AISkillTriggerHandlerTest {

    // testScenario1: Inserting a skill whose When To Use It text is under 40 characters -> the save is refused with the length error.
    // testScenario2: Activating a skill with no tools -> the save is refused with the no tools error.
    // testScenario3: Activating a skill whose instructions name a tool that is not in it -> the save is refused naming the missing tool.
    // testScenario4: Activating a skill whose instructions name only its own tools -> the skill is saved active.
    // testScenario5: Activating a skill whose bound data sources are on two objects -> the save is refused with the mixed objects error.
    // testScenario6: Changing the API name of a skill an agent has -> the save is refused with the locked name error.
    // testScenario7: Calling AISkillTriggerHandler.handleBeforeSave with null or empty input -> nothing happens and nothing is logged.
    // testScenario8: AISkillTriggerHandler.isTestCustomExceptionThrown forces an exception -> it is logged once and the save goes ahead.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Account WHERE Id = :recordId';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a skill with a When To Use It text that is too short
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, false)[0];
            skill.Description__c = 'Too short.';

            // [2] Try to insert it
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(skill, false);
            Test.stopTest();

            // [3] Check the save was refused with the length error
            Assert.areEqual(false, saveResult.isSuccess(), 'A When To Use It text under 40 characters should be refused.');
            Assert.areEqual(Label.AI_Error_Skill_Description_Length, saveResult.getErrors()[0].getMessage(), 'The length error should be shown.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an inactive skill with no tools
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];

            // [2] Try to activate it
            Test.startTest();
                skill.IsActive__c = true;
                Database.SaveResult saveResult = Database.update(skill, false);
            Test.stopTest();

            // [3] Check the save was refused with the no tools error
            Assert.areEqual(false, saveResult.isSuccess(), 'A skill with no tools should not be activated.');
            Assert.areEqual(Label.AI_Error_Skill_No_Tools, saveResult.getErrors()[0].getMessage(), 'The no tools error should be shown.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with one data source
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);

            // [2] Try to activate it with instructions naming its tool and one it does not have
            Test.startTest();
                skill.Instructions__c = '1. Call @' + dataSource.DeveloperName__c + '.\n2. Call @Missing_Tool.';
                skill.IsActive__c = true;
                Database.SaveResult saveResult = Database.update(skill, false);
            Test.stopTest();

            // [3] Check the save was refused naming the missing tool only
            Assert.areEqual(false, saveResult.isSuccess(), 'A skill naming a tool it does not have should not be activated.');
            Assert.areEqual(String.format(Label.AI_Error_Skill_Unknown_Tool, new List<String>{ 'Missing_Tool' }), saveResult.getErrors()[0].getMessage(), 'The error should name only the missing tool.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with one data source and one workflow action
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, new List<AIWorkflowAction__c>{ action }, true);

            // [2] Activate it with instructions naming both tools
            Test.startTest();
                skill.Instructions__c = '1. Call @' + dataSource.DeveloperName__c + '.\n2. Suggest @' + action.DeveloperName__c + '.';
                skill.IsActive__c = true;
                Database.SaveResult saveResult = Database.update(skill, false);
            Test.stopTest();

            // [3] Read the skill back
            AISkill__c savedSkill = [SELECT IsActive__c FROM AISkill__c WHERE Id = :skill.Id];

            // [4] Check it was saved active
            Assert.areEqual(true, saveResult.isSuccess(), 'A skill naming only its own tools should be activated.');
            Assert.areEqual(true, savedSkill.IsActive__c, 'The skill should be active.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill with two bound data sources on different objects
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false);
            dataSources[0].BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSources[0].TargetObject__c = 'Account';
            dataSources[1].BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSources[1].TargetObject__c = 'Contact';
            insert dataSources;
            AIAssistTestDataFactory.createAISkillTools(skill.Id, dataSources, null, true);

            // [2] Try to activate it
            Test.startTest();
                skill.IsActive__c = true;
                Database.SaveResult saveResult = Database.update(skill, false);
            Test.stopTest();

            // [3] Check the save was refused with the mixed objects error
            Assert.areEqual(false, saveResult.isSuccess(), 'A skill with bound tools on two objects should not be activated.');
            Assert.areEqual(Label.AI_Error_Skill_Mixed_Objects, saveResult.getErrors()[0].getMessage(), 'The mixed objects error should be shown.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill and give it to an agent
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIAssistTestDataFactory.createAIAgentSkills(agent.Id, new List<AISkill__c>{ skill }, true);

            // [2] Try to change its API name
            Test.startTest();
                skill.DeveloperName__c = 'Renamed_Skill';
                Database.SaveResult saveResult = Database.update(skill, false);
            Test.stopTest();

            // [3] Check the save was refused with the locked name error
            Assert.areEqual(false, saveResult.isSuccess(), 'The API name of a skill an agent has should not change.');
            Assert.areEqual(Label.AI_Error_Skill_Developer_Name_Locked, saveResult.getErrors()[0].getMessage(), 'The locked name error should be shown.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Call the handler with null and empty input
            Test.startTest();
                AISkillTriggerHandler.handleBeforeSave(null, null);
                AISkillTriggerHandler.handleBeforeSave(new List<AISkill__c>(), null);
            Test.stopTest();

            // [2] Count the logs
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [3] Check nothing was logged
            Assert.areEqual(0, platformLogCount, 'Null or empty input should log nothing.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Ask the handler to throw, and build a skill
            AISkillTriggerHandler.isTestCustomExceptionThrown = true;
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, false)[0];

            // [2] Insert it
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(skill, false);
            Test.stopTest();

            // [3] Count the logs for the handler
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AISkillTriggerHandler' AND MethodName__c = 'handleBeforeSave'];

            // [4] Check the save went ahead and the exception was logged once
            Assert.areEqual(true, saveResult.isSuccess(), 'The exception should not block the save.');
            Assert.areEqual(1, platformLogCount, 'The exception should be logged once.');
        }
    }
}
