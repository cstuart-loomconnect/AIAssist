/*
Class Name: AIConversationRetentionBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationRetentionBatch: expired conversations are deleted with their children, and anything on legal hold or not yet expired is kept.

=================================================================
=================================================================
Applicable Classes:

AIConversationRetentionBatch: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIConversationRetentionBatchTest {

    // testScenario1: An expired conversation is deleted together with its messages and its feedback -> conversation, messages and feedback are all gone.
    // testScenario2: A conversation on legal hold is kept however old it is -> the conversation still exists.
    // testScenario3: Expiring today, expiring tomorrow and no expiry date -> today's is deleted, the other two are kept.
    // testScenario4: 200 expired conversations are processed in one pass -> all are deleted.
    // testScenario5: The application is switched off and a conversation has expired -> the conversation is still deleted.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an expired conversation with a message and feedback
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 5, 1, true)[0];
        AIAssistTestDataFactory.createAIFeedback(conversation.Id, message.Id, 1, true);
        conversation.RetentionExpiryDate__c = Datetime.now().dateGmt().addDays(-1);
        update conversation;

        // [2] Run the retention batch
        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch(), 200);
        Test.stopTest();

        // [3] Count the conversation, message and feedback
        Integer conversationCount = [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id];
        Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE Id = :message.Id];
        Integer feedbackCount = [SELECT COUNT() FROM AIFeedback__c];

        // [4] Check all three are gone
        Assert.areEqual(0, conversationCount, 'The expired conversation should be deleted.');
        Assert.areEqual(0, messageCount, 'The conversation\'s messages should be deleted with it.');
        Assert.areEqual(0, feedbackCount, 'The conversation\'s feedback should be deleted, not left behind with a blank conversation.');
    }

    @IsTest static void testScenario2() {

        // [1] Create a conversation on legal hold that is long past its expiry
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        conversation.RetentionExpiryDate__c = Datetime.now()
            .dateGmt()
            .addDays(-400);
        conversation.IsOnLegalHold__c = true;
        update conversation;

        // [2] Run the retention batch
        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch(), 200);
        Test.stopTest();

        // [3] Count the conversation
        Integer conversationCount = [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the conversation is kept
        Assert.areEqual(1, conversationCount, 'A conversation on legal hold should be kept.');
    }

    @IsTest static void testScenario3() {

        // [1] Create conversations expiring today, expiring tomorrow and with no expiry date
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 3, true);
        Date today = Datetime.now().dateGmt();
        conversations[0].RetentionExpiryDate__c = today;
        conversations[1].RetentionExpiryDate__c = today.addDays(1);
        conversations[2].RetentionExpiryDate__c = null;
        update conversations;

        // [2] Run the retention batch
        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch(), 200);
        Test.stopTest();

        // [3] Read the conversations that remain
        Map<Id, AIConversation__c> remaining = new Map<Id, AIConversation__c>([SELECT Id FROM AIConversation__c WHERE Id IN :conversations]);

        // [4] Check only the one expiring today is deleted
        Assert.isFalse(remaining.containsKey(conversations[0].Id), 'A conversation expiring today should be deleted.');
        Assert.isTrue(remaining.containsKey(conversations[1].Id), 'A conversation expiring tomorrow should be kept.');
        Assert.isTrue(remaining.containsKey(conversations[2].Id), 'A conversation with no expiry date should be kept.');
    }

    @IsTest static void testScenario4() {

        // [1] Create 200 expired conversations
        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 200, true);

        for (AIConversation__c conversation : conversations) {
            conversation.RetentionExpiryDate__c = Datetime.now()
                .dateGmt()
                .addDays(-1);
        }

        update conversations;

        // [2] Run the retention batch
        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch(), 200);
        Test.stopTest();

        // [3] Count the conversations
        Integer conversationCount = [SELECT COUNT() FROM AIConversation__c];

        // [4] Check all are deleted
        Assert.areEqual(0, conversationCount, 'All 200 expired conversations should be deleted.');
    }

    @IsTest static void testScenario5() {

        // [1] Switch the application off, then create an expired conversation
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = false;
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        conversation.RetentionExpiryDate__c = Datetime.now().dateGmt().addDays(-1);
        update conversation;

        // [2] Run the retention batch
        Test.startTest();
            Database.executeBatch(new AIConversationRetentionBatch(), 200);
        Test.stopTest();

        // [3] Count the conversations
        Integer conversationCount = [SELECT COUNT() FROM AIConversation__c];

        // [4] Check the conversation is still deleted
        Assert.areEqual(0, conversationCount, 'The expired conversation should be deleted although the application is switched off.');
    }
}
