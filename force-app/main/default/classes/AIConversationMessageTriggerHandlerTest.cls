/*
Class Name: AIConversationMessageTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for the AI Conversation Message Trigger Handler: the roll-up onto the conversation is bulk-safe.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageTrigger: Coverage TBC
AIConversationMessageTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIConversationMessageTriggerHandlerTest {

    // testScenario1: Inserting User and AI Agent messages adds their tokens to the conversation and moves the last message time -> tokens total, timestamp is set and the native count matches.
    // testScenario2: Inserting a System message adds its tokens but does not move the last message time -> tokens counted, timestamp stays null.
    // testScenario3: Inserting a message for an agent whose retention counts from the last message moves the expiry -> expiry is 20 days from the message.
    // testScenario4: Bulk: inserting 201 messages across several conversations rolls up with one update per conversation -> each conversation counted once and queries stay small.
    // testScenario5: With AIAssistSettings__c.IsEnabled__c off, inserting a message does not roll up -> no tokens and no timestamp, and the message still saves.
    // testScenario6: Calling AIConversationMessageTriggerHandler.handleAfterInsert with null or empty input does nothing -> nothing is counted again.
    // testScenario7: Inserting messages where one has no TokenCount__c adds only the tokens that are set -> the message with no tokens contributes nothing.
    // testScenario8: Inserting messages for a conversation that already has a ConversationTokenUsage__c adds onto it -> the existing total plus the new tokens.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent and a conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        // [2] Insert a User message and an AI Agent message
        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 100, 2, true);
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 50, 1, true);
        Test.stopTest();

        // [3] Read the conversation roll-up
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c, LastMessageTimestamp__c, MessageCount__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the tokens, last message time and message count
        Assert.areEqual(250, rolledUp.ConversationTokenUsage__c, 'Tokens should add up across inserts.');
        Assert.isNotNull(rolledUp.LastMessageTimestamp__c, 'The last message time should have moved.');
        Assert.areEqual(3, rolledUp.MessageCount__c, 'The native roll-up should count all three messages.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent and a conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        // [2] Insert a System message
        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 40, 1, true);
        Test.stopTest();

        // [3] Read the conversation roll-up
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c, LastMessageTimestamp__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the tokens count and the last message time stays null
        Assert.areEqual(40, rolledUp.ConversationTokenUsage__c, 'The failed turn\'s tokens should still count.');
        Assert.isNull(rolledUp.LastMessageTimestamp__c, 'A System message is not a conversation event so the last message time should not move.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an agent whose retention counts from the last message, and a conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
        agent.ConversationRetentionDays__c = 20;
        agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
        insert agent;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        // [2] Insert a User message
        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true);
        Test.stopTest();

        // [3] Read the conversation roll-up
        AIConversation__c rolledUp = [SELECT LastMessageTimestamp__c, RetentionExpiryDate__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the expiry is twenty days from the message
        Assert.areEqual(rolledUp.LastMessageTimestamp__c.dateGmt().addDays(20), rolledUp.RetentionExpiryDate__c, 'The expiry should be twenty days from the message.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent, three conversations and 201 messages across them
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 3, true);
        List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();

        for (AIConversation__c conversation : conversations) {
            messages.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 67, false));
        }

        // [2] Insert all the messages in one go
        Integer queries;

        Test.startTest();
            insert messages;
            queries = Limits.getQueries();
        Test.stopTest();

        // [3] Read the first conversation roll-up
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversations[0].Id];

        // [4] Check the roll-up and that queries stayed small
        Assert.areEqual(201, messages.size(), 'The insert should be past the trigger chunk size.');
        Assert.areEqual(67, rolledUp.ConversationTokenUsage__c, 'Each conversation should count its own messages once.');
        Assert.isTrue(queries <= 6, 'Queries should not grow with the number of messages: ' + queries);
    }

    @IsTest static void testScenario5() {

        // [1] Switch the application off and clear the settings cache
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = false;
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        // [2] Create an agent and a conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];

        // [3] Insert a User message
        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 100, 1, true);
        Test.stopTest();

        // [4] Read the conversation and count its messages
        AIConversation__c untouched = [SELECT ConversationTokenUsage__c, LastMessageTimestamp__c FROM AIConversation__c WHERE Id = :conversation.Id];
        Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id];

        // [5] Check nothing was rolled up and the message still saved
        Assert.isTrue(untouched.ConversationTokenUsage__c == null || untouched.ConversationTokenUsage__c == 0, 'No tokens should be rolled up when the application is switched off.');
        Assert.isNull(untouched.LastMessageTimestamp__c, 'No last message time should be set when the application is switched off.');
        Assert.areEqual(1, messageCount, 'The message should still save when the application is switched off.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an agent, a conversation and a message that is already counted
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 10, 1, true);

        // [2] Call the handler with null and empty input
        Test.startTest();
            AIConversationMessageTriggerHandler.handleAfterInsert(null);
            AIConversationMessageTriggerHandler.handleAfterInsert(new List<AIConversationMessage__c>());
        Test.stopTest();

        // [3] Read the roll-up and count the platform logs
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversation.Id];
        Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [4] Check nothing was counted again or logged
        Assert.areEqual(10, rolledUp.ConversationTokenUsage__c, 'Nothing was passed in, so nothing should be counted again.');
        Assert.areEqual(0, platformLogCount, 'Nothing to process should not be logged as a fault.');
    }

    @IsTest static void testScenario7() {

        // [1] Create an agent, a conversation and messages where one has no tokens
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();
        messages.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 50, 2, false));
        messages.addAll(AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false));

        // [2] Insert the messages
        Test.startTest();
            insert messages;
        Test.stopTest();

        // [3] Read the conversation roll-up
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check only the tokens that are set were added
        Assert.areEqual(100, rolledUp.ConversationTokenUsage__c, 'The message with no TokenCount__c should contribute nothing.');
    }

    @IsTest static void testScenario8() {

        // [1] Create an agent and a conversation that already has token usage
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
        conversation.ConversationTokenUsage__c = 300;
        update conversation;

        // [2] Insert four User messages
        Test.startTest();
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 25, 4, true);
        Test.stopTest();

        // [3] Read the conversation roll-up
        AIConversation__c rolledUp = [SELECT ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the new tokens were added onto the existing total
        Assert.areEqual(400, rolledUp.ConversationTokenUsage__c, 'The new tokens should add onto the existing total.');
    }
}
