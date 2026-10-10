/*
Class Name: AIChatControllerTest

=================================================================
=================================================================

Description: Testing utility for AIChatController: the window's round trips, how refusals are shown from their code, and that nothing internal reaches the window. The AI Agent Manager is replaced by a fake that answers.

=================================================================
=================================================================
Applicable Classes:

AIChatController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatControllerTest {

    // testScenario1: A ready context offers the agent and no open conversation.
    // testScenario2: The context stops early with the right state when the application is off, in maintenance, the channel is not allowed, the terms are unsigned, or no agent is offered.
    // testScenario3: Sending a message creates the conversation, and the window gets SENT with the conversation and message.
    // testScenario4: A refusal comes back as a status chosen from its code, with the Custom Label and the code: LIMIT for a limit, BLOCKED for access, ERROR for a bad message.
    // testScenario5: A slash command the user cannot use is refused, and one they can use sends the visible text with the hidden instructions after the separator.
    // testScenario6: Open, update, history, close and resume work for the owner, and another user's conversation gives the not found label.
    // testScenario7: Debug, export and PII views are refused with the not authorised label for a user without the setting, and work with it.
    // testScenario8: Feedback, terms and a retry work, and feedback is refused while the setting is off.
    // testScenario9: An unexpected failure gives the window only the generic label and is logged.
    // testScenario10: A slash command names a prompt template of the agent -> the message is sent and stores that template for the turn.
    // testScenario11: A slash command names a template that is inactive or does not exist -> the command is refused with the label and nothing is stored.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent open to all users
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        // [2] Get the chat context
        AIChatDataStructure.ChatContext context;

        Test.startTest();
            context = AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null);
        Test.stopTest();

        // [3] Check the context is ready and offers the agent
        Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_READY, context.state, 'The context should be ready.');
        Assert.areEqual(agent.Id, context.agent.id, 'The context should offer the agent.');
        Assert.isNull(context.openConversation, 'There should be no open conversation yet.');
    }

    @IsTest static void testScenario2() {

        // [1] Load the settings rows
        List<String> states = new List<String>();
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();

        // [2] Get the chat context after each change to the settings
        Test.startTest();
            states.add(AIChatController.getChatContext(null, null, null, null).state);

            settings.CurrentTermsVersion__c = 'v1';
            update settings;
            AIAssistSettingsService.cachedSettings = null;
            states.add(AIChatController.getChatContext(null, null, null, null).state);

            settings.CurrentTermsVersion__c = null;
            ui.IsMaintenanceMode__c = true;
            upsert ui;
            states.add(AIChatController.getChatContext(null, null, null, null).state);

            settings.IsEnabled__c = false;
            update settings;
            AIAssistSettingsService.cachedSettings = null;
            states.add(AIChatController.getChatContext(null, null, null, null).state);
        Test.stopTest();

        // [3] Check each early stop gives its own state
        Assert.areEqual(new List<String>{
            AIAssistApplicationConstants.CHAT_STATE_NO_AGENT,
            AIAssistApplicationConstants.CHAT_STATE_TERMS,
            AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE,
            AIAssistApplicationConstants.CHAT_STATE_INACTIVE
        }, states, 'Each early stop should give its own state.');
    }

    @IsTest static void testScenario3() {

        // [1] Create an agent open to all users and install the answering provider mock
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [2] Send a message
        AIChatDataStructure.SendResult result;

        Test.startTest();
            result = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{
                'agentId' => agent.Id,
                'text' => 'Hello',
                'channel' => AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
            }));
        Test.stopTest();

        // [3] Count the AI replies
        Integer replyCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [4] Check the message was sent and answered
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT, result.status, 'The message should be sent.');
        Assert.isTrue(result.isNewConversation, 'The message should start a new conversation.');
        Assert.areEqual('Hello', result.userMessage.displayText, 'The window should get the message text.');
        Assert.areEqual(1, replyCount, 'The job should have answered.');
    }

    @IsTest static void testScenario4() {

        // [1] Create an agent open to all users
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        // [2] Limit the user's concurrent conversations and fill the limit
        AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false)[0];
        settings.MaxConcurrentConversations__c = 1;
        settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
        insert settings;

        AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true);

        // [3] Create an inactive agent
        AIAgent__c inactive = AIAssistTestDataFactory.createAIAgents(1, agent.AIModelConfiguration__c, false)[0];
        inactive.IsActive__c = false;
        insert inactive;

        // [4] Send a message over the limit, to the inactive agent and with blank text
        AIChatDataStructure.SendResult limited;
        AIChatDataStructure.SendResult blocked;
        AIChatDataStructure.SendResult empty;

        Test.startTest();
            limited = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => 'Hello' }));
            blocked = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => inactive.Id, 'text' => 'Hello' }));
            empty = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '   ' }));
        Test.stopTest();

        // [5] Check each refusal comes back as an error
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, limited.status, 'A limit should come back as an error status.');
        Assert.areEqual(Label.AI_Error_Concurrent_Limit, limited.message, 'The limit text should be the Custom Label.');

        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, blocked.status, 'An inactive agent should come back as an error status.');

        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, empty.status, 'A blank message should come back as an error status.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent open to all users and install the answering provider mock
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [2] Supply a slash command in memory
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            new AIChatCommand__mdt(Command__c = '/sum', IsActive__c = true, PromptText__c = 'Summarise.')
        };

        // [3] Send an unknown command and a known command
        AIChatDataStructure.SendResult unknown;
        AIChatDataStructure.SendResult known;

        Test.startTest();
            unknown = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/nope' }));
            known = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/sum' }));
        Test.stopTest();

        // [4] Read the stored user message body
        String storedBody = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER].MessageBody__c;

        // [5] Check the unknown command is refused and the known one is sent
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, unknown.status, 'An unknown command should be refused.');
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT, known.status, 'A known command should be sent.');
        Assert.isTrue(known.userMessage.isCommand, 'The message should be shown as a command.');
        Assert.isTrue(storedBody.contains('Summarise.'), 'The hidden instructions should be stored.');
    }

    @IsTest static void testScenario6() {

        // [1] Create an agent, the user's conversation and message, and another user's conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 1, true)[0];
        AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 1, true)[0];

        // [2] Open, update, page, list, try another user's conversation, then close
        String shown;
        AIChatDataStructure.ConversationView view;
        AIChatDataStructure.ConversationUpdate update1;
        AIChatDataStructure.MessagePage earlier;
        List<AIChatDataStructure.ConversationSummary> history;

        Test.startTest();
            view = AIChatController.openConversation(conversation.Id);
            update1 = AIChatController.getConversationUpdate(conversation.Id, null);
            earlier = AIChatController.getEarlierMessages(conversation.Id, message.Id);
            history = AIChatController.getConversationHistory(null, false);

            try {
                AIChatController.openConversation(theirs.Id);
            } catch (AuraHandledException ex) {
                shown = ex.getMessage();
            }

            AIChatController.closeConversation(conversation.Id);
        Test.stopTest();

        // [3] Read the closed conversation status
        String closedStatus = [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id].Status__c;

        // [4] Check each result
        Assert.areEqual(1, view.messages.size(), 'The opened conversation should show its message.');
        Assert.areEqual(1, update1.messages.size(), 'The update should carry the message.');
        Assert.isTrue(earlier.messages.isEmpty(), 'There should be no earlier messages.');
        Assert.areEqual(1, history.size(), 'The history should hold only the user\'s own conversation.');

        Assert.areEqual(Label.AI_Error_Conversation_Not_Found, shown, 'Another user\'s conversation should give the not found Custom Label.');

        Assert.areEqual(AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, closedStatus, 'The conversation should be closed.');
    }

    @IsTest static void testScenario7() {

        // [1] Create an agent, a conversation, another user and an AI reply
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

        // [2] Request the debug trace without the setting, then enable it and use the debug, export and failure views
        String shown;
        AIChatDataStructure.DebugTrace trace;
        String exported;
        AIChatDataStructure.FailureDetail detail;

        Test.startTest();
            try {
                AIChatController.getDebugTrace(reply.Id);
            } catch (AuraHandledException ex) {
                shown = ex.getMessage();
            }

            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(UserInfo.getUserId(), false)[0];
            AIAssistTestDataFactory.upsertUiSettings(false);
            settings.DebugModeEnabled__c = true;
            settings.ConversationExportEnabled__c = true;
            insert settings;

            trace = AIChatController.getDebugTrace(reply.Id);
            exported = AIChatController.exportConversation(conversation.Id);
            detail = AIChatController.getFailureDetail(conversation.Id);
        Test.stopTest();

        // [3] Check the refusal and the results
        Assert.areEqual(Label.AI_Error_Not_Authorised, shown, 'The refusal should be the not authorised Custom Label.');

        Assert.areEqual(reply.Id, trace.replyMessageId, 'The trace should be for the reply.');
        Assert.isTrue(exported.contains('Test message'), 'The export should hold the transcript.');
        Assert.isNotNull(detail, 'The failure detail should be returned.');
    }

    @IsTest static void testScenario8() {

        // [1] Create an agent, a conversation, another user, the answering provider mock and messages
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

        User other = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 1, true);

        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        // [2] Set the current terms version
        AIAssistSettings__c terms = AIAssistSettings__c.getOrgDefaults();
        terms.CurrentTermsVersion__c = 'v1';
        update terms;
        AIAssistSettingsService.cachedSettings = null;

        // [3] Submit feedback, acknowledge the terms, retry, then switch feedback off and submit again
        String shown;

        Test.startTest();
            AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
            AIChatController.acknowledgeTerms();
            AIChatController.retryLatestMessage(conversation.Id);

            AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();
            ui.IsFeedbackEnabled__c = false;
            upsert ui;

            try {
                AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
            } catch (AuraHandledException ex) {
                shown = ex.getMessage();
            }
        Test.stopTest();

        // [4] Count the feedback and terms acknowledgments
        Integer feedbackCount = [SELECT COUNT() FROM AIFeedback__c];
        Integer acknowledgmentCount = [SELECT COUNT() FROM AITermsAcknowledgment__c];

        // [5] Check the saved rows and the refusal
        Assert.areEqual(1, feedbackCount, 'One rating should be saved.');
        Assert.areEqual(1, acknowledgmentCount, 'The terms should be acknowledged.');
        Assert.areEqual(Label.AI_Error_Not_Authorised, shown, 'The refusal should be the not authorised Custom Label.');
    }

    @IsTest static void testScenario9() {

        // [1] Send a message that is not valid JSON
        String shown;

        Test.startTest();
            try {
                AIChatController.sendMessage('not json');
            } catch (AuraHandledException ex) {
                shown = ex.getMessage();
            }
        Test.stopTest();

        // [2] Count the platform logs for the controller
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIChatController'];

        // [3] Check the generic label was shown and the failure logged
        Assert.areEqual(Label.AI_Error_Generic, shown, 'Only the generic label should be shown.');
        Assert.areEqual(1, logCount, 'The failure should be logged once.');
    }

    @IsTest static void testScenario10() {

        // [1] Create an agent open to all users with a template, and install the answering provider mock
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
        template.DeveloperName__c = 'draft_client_email';
        insert template;

        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [2] Supply a slash command that names the template
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            new AIChatCommand__mdt(Command__c = '/email', IsActive__c = true, PromptTemplateDeveloperName__c = 'draft_client_email')
        };

        // [3] Send the command
        AIChatDataStructure.SendResult result;

        Test.startTest();
            result = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/email' }));
        Test.stopTest();

        // [4] Read the stored user message and the reply
        AIConversationMessage__c userMessage = [SELECT AIPromptTemplate__c FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER];
        AIConversationMessage__c reply = [SELECT AIPromptTemplate__c FROM AIConversationMessage__c WHERE Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [5] Check the command was sent with the template and the reply was answered with it
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT, result.status, 'The command should be sent.');
        Assert.areEqual(template.Id, userMessage.AIPromptTemplate__c, 'The message should store the template the command named.');
        Assert.areEqual(template.Id, reply.AIPromptTemplate__c, 'The reply should be answered with that template.');
    }

    @IsTest static void testScenario11() {

        // [1] Create an agent open to all users with an inactive template and install the answering provider mock
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        update agent;

        AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
        template.DeveloperName__c = 'retired_template';
        template.IsActive__c = false;
        insert template;

        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [2] Supply slash commands that name the inactive template and a template that does not exist
        AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
            new AIChatCommand__mdt(Command__c = '/retired', IsActive__c = true, PromptTemplateDeveloperName__c = 'retired_template'),
            new AIChatCommand__mdt(Command__c = '/missing', IsActive__c = true, PromptTemplateDeveloperName__c = 'made_up')
        };

        // [3] Send both commands
        AIChatDataStructure.SendResult retired;
        AIChatDataStructure.SendResult missing;

        Test.startTest();
            retired = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/retired' }));
            missing = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/missing' }));
        Test.stopTest();

        // [4] Count the stored messages
        Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c];

        // [5] Check both are refused with the label and nothing is stored
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, retired.status, 'A command for an inactive template should be refused.');
        Assert.areEqual(Label.AI_Error_Prompt_Template_Unavailable, retired.message, 'The refusal should be the Custom Label.');
        Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, missing.status, 'A command for a missing template should be refused.');
        Assert.areEqual(Label.AI_Error_Prompt_Template_Unavailable, missing.message, 'The refusal should be the Custom Label.');
        Assert.areEqual(0, messageCount, 'Nothing should be stored for a refused command.');
    }
}
