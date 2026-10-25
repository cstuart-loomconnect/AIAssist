/*
Class Name: AISkillToolTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Skill Tool Trigger Handler: the unique key that stops a tool being added to a skill twice, and the skill's Bound Object following its bound data sources.

=================================================================
=================================================================
Applicable Classes:

AISkillToolTrigger: Coverage TBC
AISkillToolTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AISkillToolTriggerHandlerTest {

    // testScenario1: Inserting a skill tool -> its unique key is the skill Id and the tool Id.
    // testScenario2: Adding the same data source to a skill twice -> the second save is refused.
    // testScenario3: Adding a bound data source to a skill -> the skill's Bound Object is set to its object.
    // testScenario4: Deleting the skill's only bound data source -> the skill's Bound Object is cleared.
    // testScenario5: Calling the handler with null or empty input -> nothing happens and nothing is logged.
    // testScenario6: AISkillToolTriggerHandler.isTestCustomExceptionThrown forces an exception -> it is logged and the save goes ahead.

    private static final String SOQL_TEMPLATE = 'SELECT Id, Name FROM Account WHERE Id = :recordId';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill and a data source
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];

            // [2] Put the data source into the skill
            Test.startTest();
                AISkillTool__c skillTool = AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true)[0];
            Test.stopTest();

            // [3] Read the tool back
            AISkillTool__c savedTool = [SELECT UniqueKey__c FROM AISkillTool__c WHERE Id = :skillTool.Id];

            // [4] Check the key
            Assert.areEqual(skill.Id + ':' + dataSource.Id, savedTool.UniqueKey__c, 'The key should be the skill Id and the data source Id.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill that already holds a data source
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);

            // [2] Try to add the same data source again
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, false)[0], false);
            Test.stopTest();

            // [3] Check the second save was refused
            Assert.areEqual(false, saveResult.isSuccess(), 'The same data source should not be in a skill twice.');
            Assert.areEqual(1, [SELECT COUNT() FROM AISkillTool__c WHERE AISkill__c = :skill.Id], 'The skill should still hold one tool.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill and a bound data source on Account
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Account';
            insert dataSource;

            // [2] Put the data source into the skill
            Test.startTest();
                AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true);
            Test.stopTest();

            // [3] Read the skill back
            AISkill__c savedSkill = [SELECT BoundObjectApiName__c FROM AISkill__c WHERE Id = :skill.Id];

            // [4] Check the Bound Object
            Assert.areEqual('Account', savedSkill.BoundObjectApiName__c, 'The skill should be bound to the object of its bound data source.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill bound to Account through its only data source
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, false)[0];
            dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            dataSource.TargetObject__c = 'Account';
            insert dataSource;
            AISkillTool__c skillTool = AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, true)[0];

            // [2] Remove the data source from the skill
            Test.startTest();
                delete skillTool;
            Test.stopTest();

            // [3] Read the skill back
            AISkill__c savedSkill = [SELECT BoundObjectApiName__c FROM AISkill__c WHERE Id = :skill.Id];

            // [4] Check the Bound Object was cleared
            Assert.isNull(savedSkill.BoundObjectApiName__c, 'A skill with no bound data source should be unbound.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Call the handler with null and empty input
            Test.startTest();
                AISkillToolTriggerHandler.handleBeforeSave(null);
                AISkillToolTriggerHandler.handleAfterChange(new List<AISkillTool__c>());
            Test.stopTest();

            // [2] Count the logs
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [3] Check nothing was logged
            Assert.areEqual(0, platformLogCount, 'Null or empty input should log nothing.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a skill and a data source, and ask the handler to throw
            AISkill__c skill = AIAssistTestDataFactory.createAISkills(1, true)[0];
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, SOQL_TEMPLATE, true)[0];
            AISkillToolTriggerHandler.isTestCustomExceptionThrown = true;

            // [2] Put the data source into the skill
            Test.startTest();
                Database.SaveResult saveResult = Database.insert(AIAssistTestDataFactory.createAISkillTools(skill.Id, new List<AIDataSource__c>{ dataSource }, null, false)[0], false);
            Test.stopTest();

            // [3] Count the logs for each handler method
            Integer beforeSaveLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AISkillToolTriggerHandler' AND MethodName__c = 'handleBeforeSave'];
            Integer afterChangeLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AISkillToolTriggerHandler' AND MethodName__c = 'handleAfterChange'];

            // [4] Check the save went ahead and each exception was logged once
            Assert.areEqual(true, saveResult.isSuccess(), 'The exception should not block the save.');
            Assert.areEqual(1, beforeSaveLogCount, 'The before save exception should be logged once.');
            Assert.areEqual(1, afterChangeLogCount, 'The after change exception should be logged once.');
        }
    }
}
