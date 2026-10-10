/*
Class Name: AIConversationRetentionRecalcBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationRetentionRecalcBatch and the agent trigger that starts it: a change to an agent's retention settings is applied to the conversations it already has.

=================================================================
=================================================================
Applicable Classes:

AIConversationRetentionRecalcBatch: Coverage TBC
AIAgentTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIConversationRetentionRecalcBatchTest {

    private static final String BATCH_NAME = 'AIConversationRetentionRecalcBatch';

    // testScenario1: Changing an agent's retention days starts the batch, which moves the expiry date of its conversations, including one that had none, and leaves another agent's alone -> dates moved for the agent only.
    // testScenario2: Setting retention to blank -> the expiry dates are cleared.
    // testScenario3: Each retention trigger counts from its own date: creation, the last message, or the close (and no date while still open) -> each expiry date counts from its own date.
    // testScenario4: A change that is not to the retention settings starts no batch, and the batch still runs while the application is switched off -> no batch for the other field, dates recalculated.
    // testScenario5: A failure to start the batch is logged and the agent still saves -> the agent saves and no batch is started.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create two agents with 30 days retention and conversations for each, one without an expiry date
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        AIAgent__c otherAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        otherAgent.ConversationRetentionDays__c = 30;
        otherAgent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert otherAgent;

        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 2, true);

        AIConversation__c untouched = AIAssistTestDataFactory.createAIConversations(otherAgent.Id, null, 1, true)[0];
        conversations[1].RetentionExpiryDate__c = null;
        update conversations[1];

        Date today = Datetime.now().dateGmt();

        // [2] Change the first agent's retention days to 7
        Test.startTest();
            agent.ConversationRetentionDays__c = 7;
            update agent;
        Test.stopTest();

        // [3] Read every conversation's expiry date back
        Map<Id, Date> expiries = new Map<Id, Date>();
        for (AIConversation__c conversation : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
            expiries.put(conversation.Id, conversation.RetentionExpiryDate__c);

        // [4] Check only the first agent's conversations moved
        Assert.areEqual(today.addDays(7), expiries.get(conversations[0].Id), 'Moved from 30 days to 7.');
        Assert.areEqual(today.addDays(7), expiries.get(conversations[1].Id), 'A conversation with no date gets one.');
        Assert.areEqual(today.addDays(30), expiries.get(untouched.Id), 'Another agent\'s conversation is left alone.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent with 30 days retention and a conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        // [2] Check the conversation starts with an expiry date
        Map<Id, Date> expiriesBefore = new Map<Id, Date>();
        for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
            expiriesBefore.put(row.Id, row.RetentionExpiryDate__c);

        Date before = expiriesBefore.get(conversation.Id);

        Assert.isNotNull(before, 'It had a date.');

        // [3] Blank the agent's retention days
        Test.startTest();
            agent.ConversationRetentionDays__c = null;
            update agent;
        Test.stopTest();

        // [4] Read the conversation's expiry date back
        Map<Id, Date> expiriesAfter = new Map<Id, Date>();
        for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
            expiriesAfter.put(row.Id, row.RetentionExpiryDate__c);
        Date after = expiriesAfter.get(conversation.Id);

        // [5] Check the date was cleared
        Assert.isNull(after, 'Blank retention keeps the conversation indefinitely.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an agent with 10 days retention and two conversations created 20 days ago, one closed with a last message
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 10;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 2, true);

        Datetime created = System.now().addDays(-20);

        Datetime lastMessage = System.now().addDays(-5);

        Datetime closed = System.now().addDays(-2);
        for (AIConversation__c conversation : conversations)
            Test.setCreatedDate(conversation.Id, created);
        conversations[0].LastMessageTimestamp__c = lastMessage;
        conversations[0]
            .Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        conversations[0].ConversationClosedTimestamp__c = closed;
        conversations[0]
            .ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT;
        update conversations[0];

        Set<Id> agentIds = new Set<Id>{ agent.Id };

        Map<Id, Date> fromCreated = new Map<Id, Date>();
        Map<Id, Date> fromLastMessage = new Map<Id, Date>();
        Map<Id, Date> fromClosed = new Map<Id, Date>();

        // [2] Run the batch once for each retention trigger, reading the expiry dates after each pass
        Test.startTest();
            new AIConversationRetentionRecalcBatch(agentIds)
                .execute(null, [SELECT Id, CreatedDate, LastMessageTimestamp__c, ConversationClosedTimestamp__c, Status__c, RetentionExpiryDate__c, AIAgent__r.ConversationRetentionDays__c, AIAgent__r.RetentionTrigger__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id]);
            for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
                fromCreated.put(row.Id, row.RetentionExpiryDate__c);

            AIAgentTriggerHandler.isTestCustomExceptionThrown = true;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
            update agent;
            AIAgentTriggerHandler.isTestCustomExceptionThrown = false;
            new AIConversationRetentionRecalcBatch(agentIds)
                .execute(null, [SELECT Id, CreatedDate, LastMessageTimestamp__c, ConversationClosedTimestamp__c, Status__c, RetentionExpiryDate__c, AIAgent__r.ConversationRetentionDays__c, AIAgent__r.RetentionTrigger__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id]);
            for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
                fromLastMessage.put(row.Id, row.RetentionExpiryDate__c);

            AIAgentTriggerHandler.isTestCustomExceptionThrown = true;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
            update agent;
            AIAgentTriggerHandler.isTestCustomExceptionThrown = false;
            new AIConversationRetentionRecalcBatch(agentIds)
                .execute(null, [SELECT Id, CreatedDate, LastMessageTimestamp__c, ConversationClosedTimestamp__c, Status__c, RetentionExpiryDate__c, AIAgent__r.ConversationRetentionDays__c, AIAgent__r.RetentionTrigger__c FROM AIConversation__c WHERE AIAgent__c = :agent.Id]);
            for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
                fromClosed.put(row.Id, row.RetentionExpiryDate__c);

            new AIConversationRetentionRecalcBatch(null).finish(null);
        Test.stopTest();

        // [3] Check each expiry date counts from its own date
        Assert.areEqual(created.dateGmt().addDays(10), fromCreated.get(conversations[0].Id), 'From creation.');
        Assert.areEqual(lastMessage.dateGmt().addDays(10), fromLastMessage.get(conversations[0].Id), 'From the last message.');
        Assert.areEqual(created.dateGmt().addDays(10), fromLastMessage.get(conversations[1].Id), 'From creation when there is no message yet.');

        Assert.areEqual(closed.dateGmt().addDays(10), fromClosed.get(conversations[0].Id), 'From the close.');
        Assert.isNull(fromClosed.get(conversations[1].Id), 'An open conversation has no date until it closes.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent with 30 days retention and a conversation, and switch the application off
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = false;
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        Integer jobsAfterOtherChange;

        // [2] Change a field that is not retention, count the batches, then change the retention days
        Test.startTest();
            agent.Description__c = 'Not a retention change.';
            update agent;
            jobsAfterOtherChange = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];
            agent.ConversationRetentionDays__c = 5;
            update agent;
        Test.stopTest();

        // [3] Read the conversation's expiry date back
        Map<Id, Date> expiries = new Map<Id, Date>();
        for (AIConversation__c row : [SELECT RetentionExpiryDate__c FROM AIConversation__c])
            expiries.put(row.Id, row.RetentionExpiryDate__c);
        Date expiryDate = expiries.get(conversation.Id);

        // [4] Check no batch started for the other field and the date was recalculated
        Assert.areEqual(0, jobsAfterOtherChange, 'No batch for another field.');
        Assert.areEqual(Datetime.now().dateGmt().addDays(5), expiryDate, 'Recalculated although the application is off.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent with 30 days retention
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 30;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
        insert agent;

        Database.SaveResult saved;

        // [2] Force the handler to fail, change the retention days and call the handler directly
        Test.startTest();
            AIAgentTriggerHandler.isTestCustomExceptionThrown = true;
            agent.ConversationRetentionDays__c = 9;
            saved = Database.update(agent, false);
            AIAgentTriggerHandler.handleAfterUpdate(null, null);
        Test.stopTest();

        // [3] Count the batches that started
        Integer jobs = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :BATCH_NAME];

        // [4] Check the agent still saved and no batch started
        Assert.isTrue(saved.isSuccess(), 'The agent still saves.');
        Assert.areEqual(0, jobs, 'No batch was started.');
    }
}
