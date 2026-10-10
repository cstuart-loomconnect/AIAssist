/*
Class Name: AIChatConversationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatConversationService: ownership, paging, history, resume, export and the shapes the window reads.

=================================================================
=================================================================
Applicable Classes:

AIChatConversationService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatConversationServiceTest {

    // testScenario1: A user owns their own conversation and reply, and another user's, a missing one and a wrong-type Id are all reported as not found.
    // testScenario2: The newest active conversation for the agent and record is found, and a closed one or another agent's is not.
    // testScenario3: A view shows title, agent, status and the messages oldest first, hides System messages, and pages with a more flag.
    // testScenario4: loadMessagesAfter returns only newer messages, and an unknown boundary returns all.
    // testScenario5: A reply shows its real values in place of the fake ones, both in the window and in the export, and the stored text is unchanged.
    // testScenario6: History lists only the user's own conversations, newest first, optionally for one record.
    // testScenario7: A closed conversation is resumed when the agent allows it, and refused otherwise, with the closed label.
    // testScenario8: Resume is refused at the user's concurrent conversation limit.
    // testScenario9: Execution steps get a Custom Label by what they did, with the data source or action name added.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent, the user's conversation, another user's conversation and two messages
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];
        AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 1, true)[0];

        AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
        AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 5, 1, true)[0];

        // [2] Get the user's own conversation and reply, then try each bad Id
        List<String> messages = new List<String>();
        Id ownId;
        Id replyId;

        Test.startTest();
            ownId = AIChatConversationService.getOwnedConversation(conversation.Id).Id;
            replyId = AIChatConversationService.getOwnedAgentMessage(reply.Id).Id;

            for (Id bad : new List<Id>{ theirs.Id, agent.Id, null }) {
                try {
                    AIChatConversationService.getOwnedConversation(bad);
                } catch (AIChatConversationService.AIChatConversationServiceException ex) {
                    messages.add(ex.getMessage());
                }
            }

            try {
                AIChatConversationService.getOwnedAgentMessage(userMessage.Id);
            } catch (AIChatConversationService.AIChatConversationServiceException ex) {
                messages.add(ex.getMessage());
            }
        Test.stopTest();

        // [3] Check the own records are returned and the bad Ids are refused
        Assert.areEqual(conversation.Id, ownId, 'The user\'s own conversation should be returned.');
        Assert.areEqual(reply.Id, replyId, 'The user\'s own reply should be returned.');

        Assert.areEqual(4, messages.size(), 'Each of the four bad Ids should be refused.');
        for (String refusal : messages)
        Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusal, 'Each refusal should be the not found Custom Label.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an agent, an active conversation and another user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [2] Create a closed conversation
        AIConversation__c closed = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
        closed.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        closed.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
        closed.ConversationClosedTimestamp__c = System.now();
        insert closed;

        // [3] Find the active conversation for the agent and for a wrong agent Id
        AIConversation__c found;
        AIConversation__c none;

        Test.startTest();
            found = AIChatConversationService.findActiveConversation(agent.Id, null);
            none = AIChatConversationService.findActiveConversation(UserInfo.getUserId(), null);
        Test.stopTest();

        // [4] Check only the active conversation is found
        Assert.areEqual(conversation.Id, found.Id, 'The active conversation should be found, not the closed one.');
        Assert.isNull(none, 'No conversation should be found for a wrong agent Id.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an agent, a conversation and another user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [2] Set a message page size of 3
        AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
        AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
        ui.messagePageSize = 3;

        // [3] Create user messages and System messages
        List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 5, true);
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 9, 2, true);

        // [4] Build the view and load the earlier page
        AIChatDataStructure.ConversationView view;
        AIChatDataStructure.MessagePage older;

        Test.startTest();
            view = AIChatConversationService.buildConversationView(conversation.Id, 3, user, ui);
            older = AIChatConversationService.loadMessagePage(conversation.Id, view.messages[0].id, 3, user, ui);
        Test.stopTest();

        // [5] Check the view and the earlier page
        Assert.areEqual('Test message 0', view.title, 'The view should be named after the first user message.');
        Assert.areEqual(3, view.messages.size(), 'The view should hold one page of messages.');
        Assert.isTrue(view.hasMoreMessages, 'The view should say there are more messages to load.');
        Assert.areEqual(messages[4].Id, view.messages[2].id, 'The newest message should come last.');

        Assert.areEqual(2, older.messages.size(), 'The earlier page should hold the rest, without the System messages.');
        Assert.isFalse(older.hasMore, 'The earlier page should say there is nothing more.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent, a conversation and another user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [2] Create four user messages
        AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
        AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
        List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 4, true);

        // [3] Load the messages after a boundary and with no boundary
        List<AIChatDataStructure.ChatMessage> after;
        List<AIChatDataStructure.ChatMessage> all;

        Test.startTest();
            after = AIChatConversationService.loadMessagesAfter(conversation.Id, messages[1].Id, user, ui);
            all = AIChatConversationService.loadMessagesAfter(conversation.Id, null, user, ui);
        Test.stopTest();

        // [4] Check the messages returned
        Assert.areEqual(2, after.size(), 'Only the two newer messages should be returned.');
        Assert.areEqual(4, all.size(), 'All the messages should be returned when there is no boundary.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent, a conversation and another user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        // [2] Map a real value to a fake value for the conversation
        AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
        AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
        AIAssistTestDataFactory.createAIPIIMappings(conversation.Id, new Map<String, String>{ 'Jane Smith' => 'Mary Jones' }, true);

        // [3] Create an AI reply that holds the fake value
        AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, false)[0];
        reply.MessageBody__c = 'Hello Mary Jones';
        AIMessagingDataService.insertOrThrow(new List<SObject>{ reply });

        // [4] Build the view and export the conversation
        String exported;
        AIChatDataStructure.ConversationView view;

        Test.startTest();
            view = AIChatConversationService.buildConversationView(conversation.Id, 10, user, ui);
            exported = AIChatConversationService.exportConversation(conversation.Id);
        Test.stopTest();

        // [5] Read the stored reply text
        String storedBody = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE Id = :reply.Id].MessageBody__c;

        // [6] Check the real value is shown and the stored text is unchanged
        Assert.areEqual('Hello Jane Smith', view.messages[0].displayText, 'The window should show the real value.');
        Assert.isTrue(exported.contains('Hello Jane Smith'), 'The export should hold the real value.');
        Assert.areEqual('Hello Mary Jones', storedBody, 'The stored text should be unchanged.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an agent, the user's conversation, another user and their conversations
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];
        AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 2, true);

        // [2] Create a conversation about an account
        AIConversation__c about = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];

        Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];

        about.RelatedRecordId__c = String.valueOf(record.Id);
        about.RelatedObjectAPIName__c = 'Account';
        insert about;

        // [3] Get the history for all conversations and for the record
        List<AIChatDataStructure.ConversationSummary> all;
        List<AIChatDataStructure.ConversationSummary> forRecord;

        Test.startTest();
            all = AIChatConversationService.getConversationHistory(null, false);
            forRecord = AIChatConversationService.getConversationHistory(String.valueOf(record.Id), true);
        Test.stopTest();

        // [4] Check the history lists
        Assert.areEqual(2, all.size(), 'The history should hold only the user\'s own conversations.');
        Assert.areEqual(1, forRecord.size(), 'One conversation should be about the record.');
        Assert.areEqual(about.Id, forRecord[0].id, 'It should be the conversation about the record.');
    }

    @IsTest static void testScenario7() {

        // [1] Create one agent that allows resume and one that does not
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AllowConversationResume__c = true;
        update agent;

        AIAgent__c noResume = AIAssistTestDataFactory.createAIAgents(1, agent.AIModelConfiguration__c, true)[0];

        // [2] Create a closed conversation for each agent
        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false);
        conversations.addAll(AIAssistTestDataFactory.createAIConversations(noResume.Id, UserInfo.getUserId(), 1, false));

        for (AIConversation__c each : conversations) {
            each.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
            each.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
            each.ConversationClosedTimestamp__c = System.now();
        }
        insert conversations;

        // [3] Resume both conversations
        String shown;

        Test.startTest();
            AIChatConversationService.resumeConversation(conversations[0].Id);
            try {
                AIChatConversationService.resumeConversation(conversations[1].Id);
            } catch (AIChatConversationService.AIChatConversationServiceException ex) {
                shown = ex.getMessage();
            }
        Test.stopTest();

        // [4] Read the reopened conversation status
        String reopenedStatus = [SELECT Status__c FROM AIConversation__c WHERE Id = :conversations[0].Id].Status__c;

        // [5] Check the first is reopened and the second is refused
        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, reopenedStatus, 'The conversation should be reopened.');
        Assert.areEqual(Label.AI_Error_Conversation_Closed, shown, 'The refusal should be the closed Custom Label.');
    }

    @IsTest static void testScenario8() {

        // [1] Create an agent that allows resume
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AllowConversationResume__c = true;
        update agent;

        // [2] Limit the user's concurrent conversations and fill the limit
        AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false)[0];
        settings.MaxConcurrentConversations__c = 1;
        insert settings;

        AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true);

        // [3] Create a closed conversation
        AIConversation__c closed = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
        closed.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
        closed.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
        closed.ConversationClosedTimestamp__c = System.now();
        insert closed;

        // [4] Try to resume the closed conversation
        String shown;

        Test.startTest();
            try {
                AIChatConversationService.resumeConversation(closed.Id);
            } catch (AIChatConversationService.AIChatConversationServiceException ex) {
                shown = ex.getMessage();
            }
        Test.stopTest();

        // [5] Check the refusal
        Assert.areEqual(Label.AI_Error_Concurrent_Limit, shown, 'The refusal should be the concurrent limit Custom Label.');
    }

    @IsTest static void testScenario9() {

        // [1] Create an agent, a conversation, another user and a data source
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
        String sourceName = [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id = :source.Id].DeveloperName__c;

        // [2] Build an execution step of each type
        AIChatDataStructure.ExecutionStep provider;
        AIChatDataStructure.ExecutionStep masking;
        AIChatDataStructure.ExecutionStep anyOther;
        AIChatDataStructure.ExecutionStep detail;

        Test.startTest();
            provider = AIChatConversationService.buildExecutionStep(new AIExecutionStep__c(StepType__c = AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL, Status__c = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, StepOrder__c = 2, DurationMilliseconds__c = 40));
            masking = AIChatConversationService.buildExecutionStep(new AIExecutionStep__c(StepType__c = AIAssistApplicationConstants.STEP_TYPE_PII_MASKING));
            anyOther = AIChatConversationService.buildExecutionStep(new AIExecutionStep__c(StepType__c = AIAssistApplicationConstants.STEP_TYPE_OTHER));
            detail = AIChatConversationService.buildExecutionStep(new AIExecutionStep__c(StepDetail__c = 'Custom'));
        Test.stopTest();

        // [3] Check each step label
        Assert.areEqual(Label.AI_Step_Calling_Model, provider.label, 'A provider call should get the calling model label.');
        Assert.isTrue(provider.isSuccess && provider.durationMs == 40 && provider.stepOrder == 2, 'The step should carry its success, time and order.');

        Assert.areEqual(Label.AI_Step_Protecting_Data, masking.label, 'PII masking should get the protecting data label.');

        Assert.areEqual(Label.AI_Step_Finalising, anyOther.label, 'Any other step type should get the finalising label.');

        Assert.areEqual('Custom', detail.label, 'The stored step detail should win over the label.');
    }
}
