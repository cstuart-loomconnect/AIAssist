/*
Class Name: AIAgentTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Agent Trigger Handler: the retention recalculation batch started when an agent's retention days or retention trigger change.

=================================================================
=================================================================
Applicable Classes:

AIAgentTrigger: Coverage TBC
AIAgentTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentTriggerHandlerTest {

    // testScenario1: Updating an AIAgent__c's ConversationRetentionDays__c starts the retention recalculation batch.
    // testScenario2: Updating an AIAgent__c's RetentionTrigger__c starts the retention recalculation batch.
    // testScenario3: Updating an AIAgent__c without changing its retention settings does not start the batch.
    // testScenario4: Calling AIAgentTriggerHandler.handleAfterUpdate with null or empty inputs does nothing and logs nothing.
    // testScenario5: When AIAgentTriggerHandler.isTestCustomExceptionThrown forces an exception, it's caught and logged rather than blocking the save, and no batch is started.

    private static final String BATCH_NAME = 'AIConversationRetentionRecalcBatch';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent with retention settings
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        // [2] Check that no batch has run yet
        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME], 'No batch should run before the retention change.');

        // [3] Change the retention days and update the agent
        Test.startTest();
            agent.ConversationRetentionDays__c = 60;
            update agent;
        Test.stopTest();

        // [4] Count the retention batches that ran
        Integer batchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];

        // [5] Check that one batch ran
        Assert.areEqual(1, batchCount, 'The retention recalculation batch should run once when ConversationRetentionDays__c changes.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent with retention settings
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        // [2] Change the retention trigger and update the agent
        Test.startTest();
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
            update agent;
        Test.stopTest();

        // [3] Count the retention batches that ran
        Integer batchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];

        // [4] Check that one batch ran
        Assert.areEqual(1, batchCount, 'The retention recalculation batch should run once when RetentionTrigger__c changes.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an agent with retention settings
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        // [2] Change only the agent name and update the agent
        Test.startTest();
            agent.Name = 'A completely new name';
            update agent;
        Test.stopTest();

        // [3] Count the retention batches that ran
        Integer batchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];

        // [4] Check that no batch ran
        Assert.areEqual(0, batchCount, 'No batch should run when the retention settings did not change.');
    }

    @IsTest static void testScenario4() {

        // [1] Call the handler with null and empty inputs
        Test.startTest();
            AIAgentTriggerHandler.handleAfterUpdate(null, null);
            AIAgentTriggerHandler.handleAfterUpdate(new Map<Id, AIAgent__c>(), new List<AIAgent__c>());
        Test.stopTest();

        // [2] Count the batches and platform logs
        Integer batchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];
        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [3] Check that nothing ran and nothing was logged
        Assert.areEqual(0, batchCount, 'No batch should run when there is nothing to process.');
        Assert.areEqual(0, platformLogCount, 'Nothing to process should not be logged as a fault.');
    }

    @IsTest static void testScenario5() {

        // [1] Force the handler to throw an exception
        AIAgentTriggerHandler.isTestCustomExceptionThrown = true;

        // [2] Create an agent with retention settings
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        // [3] Change the retention days and update the agent
        Test.startTest();
            agent.ConversationRetentionDays__c = 60;
            update agent;
        Test.stopTest();

        // [4] Count the batches and the matching platform logs
        Integer batchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];
        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIAgentTriggerHandler' AND MethodName__c = 'handleAfterUpdate'];

        // [5] Check that no batch ran and the exception was logged
        Assert.areEqual(0, batchCount, 'No batch should run when the handler throws.');
        Assert.areEqual(1, platformLogCount, 'The forced exception should be logged to AIPlatformLog__c.');
    }
}
