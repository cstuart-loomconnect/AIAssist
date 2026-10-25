/*
Class Name: AIConversationTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIConversationTrigger and AIConversationTriggerHandler: retention expiry and the close timestamp, bulk-safe and quiet when the application is switched off.

=================================================================
=================================================================
Applicable Classes:

AIConversationTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIConversationTriggerHandlerTest {

    // testScenario1: Insert conversations whose agents count retention from creation, from the last message, from closing, and not at all -> the first two get an expiry date and the others do not.
    // testScenario2: Close a conversation whose agent counts retention from closing -> the close time is stamped and the expiry counts from it.
    // testScenario3: Update a conversation that is already closed -> its close time and expiry date are left alone.
    // testScenario4: Insert 201 conversations, across the 200-record chunk boundary -> all get an expiry date within a few queries.
    // testScenario5: Switch the application off and insert conversations -> no expiry date is set and the conversations still save.
    // testScenario6: Call the handler with null and empty input -> nothing happens and no log is written.
    // testScenario7: Insert a conversation while the handler is set to throw -> no expiry date is set and one platform log is written.

    private static final String HANDLER_CLASS_NAME = 'AIConversationTriggerHandler';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create four agents with different retention rules and a conversation for each
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(4, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false);
            agents[0].ConversationRetentionDays__c = 30;
            agents[0]
                .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
            agents[1].ConversationRetentionDays__c = 30;
            agents[1]
                .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
            agents[2].ConversationRetentionDays__c = 30;
            agents[2]
                .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
            insert agents;

            List<AIConversation__c> conversations = new List<AIConversation__c>();

            for (AIAgent__c agent : agents) {
                conversations.addAll(AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false));
            }

            // [2] Insert the conversations
            Test.startTest();
                insert conversations;
            Test.stopTest();

            // [3] Read the expiry dates back
            Map<Id, AIConversation__c> conversationsById = new Map<Id, AIConversation__c>([SELECT AIAgent__c, RetentionExpiryDate__c FROM AIConversation__c WHERE Id IN :conversations]);
            Date expected = Datetime.now().dateGmt().addDays(30);

            // [4] Check only creation and last-message retention set an expiry date
            Assert.areEqual(expected, conversationsById.get(conversations[0].Id).RetentionExpiryDate__c, 'Retention counted from creation should expire 30 days from today.');
            Assert.areEqual(expected, conversationsById.get(conversations[1].Id).RetentionExpiryDate__c, 'Last-message retention should start from creation until a message arrives.');
            Assert.isNull(conversationsById.get(conversations[2].Id).RetentionExpiryDate__c, 'Retention counted from closing should have no expiry until the conversation closes.');
            Assert.isNull(conversationsById.get(conversations[3].Id).RetentionExpiryDate__c, 'No retention days should mean keep indefinitely.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that counts retention from closing, and a conversation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationRetentionDays__c = 10;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

            // [2] Close the conversation
            Test.startTest();
                conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
                conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
                update conversation;
            Test.stopTest();

            // [3] Read the closed conversation back
            AIConversation__c closed = [SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c FROM AIConversation__c WHERE Id = :conversation.Id];

            // [4] Check the close time is stamped and the expiry counts from it
            Assert.isNotNull(closed.ConversationClosedTimestamp__c, 'The close time should be stamped when the conversation closes.');
            Assert.areEqual(closed.ConversationClosedTimestamp__c.dateGmt().addDays(10), closed.RetentionExpiryDate__c, 'The expiry should count from the close time.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that counts retention from closing, and a conversation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationRetentionDays__c = 10;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

            // [2] Close the conversation
            conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
            conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
            update conversation;

            // [3] Note the close time and expiry date before the update
            AIConversation__c conversationBefore = [SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c FROM AIConversation__c WHERE Id = :conversation.Id];

            // [4] Update an unrelated field on the closed conversation
            Test.startTest();
                conversation.Channel__c = AIAssistApplicationConstants.CHANNEL_MOBILE;
                update conversation;
            Test.stopTest();

            // [5] Read the close time and expiry date again
            AIConversation__c conversationAfter = [SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c FROM AIConversation__c WHERE Id = :conversation.Id];

            // [6] Check the close time and expiry date are unchanged
            Assert.areEqual(conversationBefore.ConversationClosedTimestamp__c, conversationAfter.ConversationClosedTimestamp__c, 'The close time should be unchanged by a later update.');
            Assert.areEqual(conversationBefore.RetentionExpiryDate__c, conversationAfter.RetentionExpiryDate__c, 'The expiry date should be unchanged by a later update.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that counts retention from creation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationRetentionDays__c = 5;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
            insert agent;

            // [2] Build 201 conversations
            List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 201, false);
            Integer queries;

            // [3] Insert them and note how many queries were used
            Test.startTest();
                insert conversations;
                queries = Limits.getQueries();
            Test.stopTest();

            // [4] Count the conversations that got an expiry date
            Integer stampedCount = [SELECT COUNT() FROM AIConversation__c WHERE RetentionExpiryDate__c != NULL];

            // [5] Check every conversation is stamped within the query budget
            Assert.areEqual(201, stampedCount, 'Every conversation should be stamped, in both chunks.');
            Assert.isTrue(queries <= 9, 'Queries should not grow with the number of records: ' + queries);
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Switch the application off
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsEnabled__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            // [2] Create an agent that counts retention from creation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationRetentionDays__c = 5;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
            insert agent;

            // [3] Build three conversations
            List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 3, false);

            // [4] Insert the conversations
            Test.startTest();
                insert conversations;
            Test.stopTest();

            // [5] Count the conversations with no expiry date
            Integer unstampedCount = [SELECT COUNT() FROM AIConversation__c WHERE RetentionExpiryDate__c = NULL];

            // [6] Check nothing was stamped
            Assert.areEqual(3, unstampedCount, 'Nothing should be added while the application is switched off.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Call the handler with null and empty input
            Test.startTest();
                AIConversationTriggerHandler.handleBeforeInsert(null);
                AIConversationTriggerHandler.handleBeforeInsert(new List<AIConversation__c>());
                AIConversationTriggerHandler.handleBeforeUpdate(null, null);
                AIConversationTriggerHandler.handleBeforeUpdate(new Map<Id, AIConversation__c>(), null);
            Test.stopTest();

            // [2] Count the platform logs
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [3] Check nothing was logged
            Assert.areEqual(0, logCount, 'Nothing to do should not be logged as a fault.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that counts retention from creation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationRetentionDays__c = 5;
            agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
            insert agent;

            // [2] Build a conversation and set the handler to throw
            List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false);
            AIConversationTriggerHandler.isTestCustomExceptionThrown = true;

            // [3] Insert the conversation
            Test.startTest();
                insert conversations;
            Test.stopTest();

            // [4] Count the unstamped conversations and the platform logs
            Integer unstampedCount = [SELECT COUNT() FROM AIConversation__c WHERE RetentionExpiryDate__c = NULL];
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = :HANDLER_CLASS_NAME AND MethodName__c = 'handleBeforeInsert'];

            // [5] Check no expiry date was set and the failure was logged once
            Assert.areEqual(1, unstampedCount, 'The expiry date should not be set when the handler fails.');
            Assert.areEqual(1, logCount, 'The failure should be logged once.');
        }
    }
}
