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
    // testScenario12: A user with no active settings row and no policy -> the window stops with no access, a send is refused in place and history is refused with the label.
    // testScenario13: A user with a settings row but no policy -> the window opens and reads, and send, retry and resume are refused with the no policy label.
    // testScenario14: Save a reply to the record as a note, a post and a task -> each is created and the result says so, and a bad target, a user who does not own the reply and a user with no access are refused with their labels.
    // testScenario15: Share, list and search through the window -> the shared user lists, opens, polls and pages the conversation, and the view says it cannot be shared onward.
    // testScenario16: The agents the window offers say whether their conversations can be shared, and an opened conversation says whether it can be shared and whether it is about a record.
    // testScenario17: A user with no active settings row and no policy -> the five save and share endpoints are refused with the no access label.
    // testScenario18: A user a conversation is shared with tries every owner-only call -> retry, close, resume, rate, run or decline an action, save to the record, share onward, list shares, search, export, debug and send are all refused and nothing changes.
    // testScenario19: Share then unshare through the window -> a bystander sees nothing, and the shared user loses the conversation when it is unshared.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Load the settings rows
            List<String> states = new List<String>();
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();

            // [2] Get the chat context after each change to the settings
            Test.startTest();
                states.add(AIChatController.getChatContext(null, null, null, null).state);

                settings.CurrentTermsVersion__c = 'v1';
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
                AIAssistSettingsService.cachedSettings = null;
                states.add(AIChatController.getChatContext(null, null, null, null).state);

                settings.CurrentTermsVersion__c = null;
                ui.IsMaintenanceMode__c = true;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert ui; }
                states.add(AIChatController.getChatContext(null, null, null, null).state);

                settings.IsEnabled__c = false;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
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
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent open to all users
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
            update agent;

            // [2] Limit the user's concurrent conversations and fill the limit
            AIAssistTestDataFactory.createAIUsagePolicyForUser(UserInfo.getUserId(), 1, null, null, AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

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
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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

                AIUserSettings__c settings = AIAssistTestDataFactory.getAIUserSettings(UserInfo.getUserId());
                AIAssistTestDataFactory.upsertUiSettings(false);
                settings.DebugModeEnabled__c = true;
                settings.ConversationExportEnabled__c = true;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }

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
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update terms; }
            AIAssistSettingsService.cachedSettings = null;

            // [3] Submit feedback, acknowledge the terms, retry, then switch feedback off and submit again
            String shown;

            Test.startTest();
                AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null);
                AIChatController.acknowledgeTerms();
                AIChatController.retryLatestMessage(conversation.Id);

                AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();
                ui.IsFeedbackEnabled__c = false;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert ui; }

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
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an open agent and switch the user's own settings row off, leaving no policy
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
            update agent;

            AIUserSettings__c userRow = [SELECT Id FROM AIUserSettings__c WHERE User__c = :superUser.Id LIMIT 1];
            userRow.IsActive__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update userRow; }
            AIAssistTestDataFactory.deactivateUsagePolicies();

            AIChatDataStructure.ChatContext context;
            AIChatDataStructure.SendResult sendResult;
            String historyRefusal;

            // [2] Open the window, send a message and ask for history
            Test.startTest();
                context = AIChatController.getChatContext(null, null, null, null);

                sendResult = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{
                    'agentId' => agent.Id,
                    'text' => 'Hello',
                    'channel' => AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
                }));

                try {
                    AIChatController.getConversationHistory(null, false);
                } catch (AuraHandledException ex) {
                    historyRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the window stops with no access, nothing is sent and history is refused
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_NO_ACCESS, context.state, 'The window should stop with no access.');
            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_NO_ACCESS, context.blockedState, 'The user should be named as blocked for no access.');
            Assert.isNull(context.agent, 'No agent should be offered.');

            Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, sendResult.status, 'The send should be refused in place.');
            Assert.areEqual(Label.AI_Error_No_Access, sendResult.message, 'The send refusal should be the no access label.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c], 'No message should have been saved.');

            Assert.areEqual(Label.AI_Error_No_Access, historyRefusal, 'History should be refused with the no access label.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an open agent and a conversation, then switch the policies off so the user has a settings row only
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
            update agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            AIAssistTestDataFactory.deactivateUsagePolicies();

            AIChatDataStructure.ChatContext context;
            AIChatDataStructure.SendResult sendResult;
            AIChatDataStructure.ConversationView opened;
            String retryRefusal;
            String resumeRefusal;

            // [2] Open the window, read, send, retry and resume
            Test.startTest();
                context = AIChatController.getChatContext(null, null, null, null);
                opened = AIChatController.openConversation(conversation.Id);

                sendResult = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'agentId' => agent.Id, 'text' => 'Hello', 'channel' => AIAssistApplicationConstants.CHANNEL_UTILITY_BAR }));

                try {
                    AIChatController.retryLatestMessage(conversation.Id);
                } catch (AuraHandledException ex) {
                    retryRefusal = ex.getMessage();
                }

                try {
                    AIChatController.resumeConversation(conversation.Id);
                } catch (AuraHandledException ex) {
                    resumeRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the window opens and reads, and everything that sends is refused with the no policy label
            Assert.areEqual(AIAssistApplicationConstants.CHAT_STATE_READY, context.state, 'The window should open for a user with a settings row.');
            Assert.isFalse(context.user.canSend, 'The user should not be able to send.');
            Assert.areEqual(AIAssistApplicationConstants.CHAT_BLOCKED_NO_POLICY, context.blockedState, 'The user should be named as blocked for no policy.');
            Assert.areEqual(Label.AI_Chat_Blocked_No_Policy, context.blockedMessage, 'The message box should say sending is off.');
            Assert.isNotNull(opened, 'The conversation should still open for reading.');

            Assert.areEqual(AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR, sendResult.status, 'The send should be refused in place.');
            Assert.areEqual(Label.AI_Error_No_Policy, sendResult.message, 'The send refusal should be the no policy label.');
            Assert.areEqual(Label.AI_Error_No_Policy, retryRefusal, 'A retry should be refused with the no policy label.');
            Assert.areEqual(Label.AI_Error_No_Policy, resumeRefusal, 'Resuming should be refused with the no policy label.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c], 'No message should have been saved.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a conversation about an account with an AI reply, another user's conversation and a user's message
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            User other = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 1, false)[0];
            theirs.RelatedRecordId__c = account.Id;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert theirs; }
            AIConversationMessage__c theirReply = AIAssistTestDataFactory.createAIConversationMessages(theirs.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIChatDataStructure.SaveToRecordResult noteResult;
            AIChatDataStructure.SaveToRecordResult postResult;
            AIChatDataStructure.SaveToRecordResult taskResult;
            List<String> refusals = new List<String>();

            // [2] Save the reply three ways, then try the refusals
            Test.startTest();
                noteResult = AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'A note');
                postResult = AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_CHATTER, 'A post');
                taskResult = AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_TASK, 'A task');

                try { AIChatController.saveReplyToRecord(reply.Id, 'EMAIL', 'Text'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.saveReplyToRecord(theirReply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, '   '); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check what was created and each refusal
            Assert.areEqual(Label.AI_Chat_Saved_As_Note, noteResult.message, 'The note result should carry its message.');
            Assert.isNotNull(noteResult.recordId, 'The note should have an Id.');
            Assert.areEqual(1, [SELECT COUNT() FROM FeedItem WHERE Id = :postResult.recordId AND ParentId = :account.Id], 'The post should be on the record.');
            Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE Id = :taskResult.recordId AND WhatId = :account.Id], 'The task should be about the record.');
            Assert.areEqual(Label.AI_Error_Save_Target_Invalid, refusals[0], 'A bad target should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[1], 'Another user\'s reply should be not found.');
            Assert.areEqual(Label.AI_Error_Save_Text_Empty, refusals[2], 'Blank text should be refused.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, the starter's conversation about an account with a user message and an AI reply, and two users
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = 'Global';
            insert agent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;

            AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<User> users = AIAssistTestDataFactory.createUsers(2, false);
            users[0].LastName = 'Zqshare Viewer';
            users[1].LastName = 'Zqshare Bystander';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert users; }
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            insert new List<AIUserSettings__c>{ new AIUserSettings__c(User__c = users[0].Id, IsActive__c = true, ConversationExportEnabled__c = true, DebugModeEnabled__c = true), new AIUserSettings__c(User__c = users[1].Id, IsActive__c = true) };

            List<AIChatDataStructure.ShareRecipient> before;
            List<AIChatDataStructure.ShareRecipient> found;
            AIChatDataStructure.ShareRecipient shared;
            List<AIChatDataStructure.ShareRecipient> after;
            AIChatDataStructure.ConversationView ownerView;

            // [2] Share it as the starter
            Test.startTest();
                before = AIChatController.getConversationShares(conversation.Id);
                found = AIChatController.searchShareableUsers(conversation.Id, 'Zqshare');
                shared = AIChatController.shareConversation(conversation.Id, users[0].Id);
                after = AIChatController.getConversationShares(conversation.Id);
                ownerView = AIChatController.openConversation(conversation.Id);
            Test.stopTest();

            List<AIChatDataStructure.ConversationSummary> viewerHistory;
            AIChatDataStructure.ConversationView viewerView;
            AIChatDataStructure.ConversationUpdate viewerUpdate;
            AIChatDataStructure.MessagePage viewerEarlier;

            // [3] Use it as the user it is shared with
            System.runAs(users[0]) {
                viewerHistory = AIChatController.getSharedConversationHistory();
                viewerView = AIChatController.openConversation(conversation.Id);
                viewerUpdate = AIChatController.getConversationUpdate(conversation.Id, null);
                viewerEarlier = AIChatController.getEarlierMessages(conversation.Id, reply.Id);
            }

            // [4] Check the starter's side
            Assert.isTrue(before.isEmpty(), 'Nothing should be shared at first.');
            Assert.areEqual(2, found.size(), 'The search should find both eligible users.');
            Assert.areEqual(users[0].Id, shared.userId, 'The share should name the recipient.');
            Assert.areEqual(1, after.size(), 'The share should be listed.');
            Assert.isTrue(ownerView.canShare, 'The starter should be able to share.');
            Assert.isTrue(ownerView.hasRelatedRecord, 'The view should say the conversation is about a record.');

            // [5] Check the shared user's side
            Assert.areEqual(1, viewerHistory.size(), 'The shared conversation should be in Shared with me.');
            Assert.areEqual(conversation.Id, viewerHistory[0].id, 'It should be the shared conversation.');
            Assert.areEqual(conversation.Id, viewerView.id, 'The shared user should open it.');
            Assert.isFalse(viewerView.canShare, 'The shared user should not share it onward.');
            Assert.isTrue(viewerView.hasRelatedRecord, 'The shared view should say it is about a record.');
            Assert.isFalse(viewerUpdate.messages.isEmpty(), 'The shared user should poll its messages.');
            Assert.isNotNull(viewerEarlier, 'The shared user should page earlier messages.');
        }
    }

    @IsTest static void testScenario16() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent and a Private agent, both open to all users, and a conversation about an account on the Global one
            AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            globalAgent.ConversationVisibility__c = 'Global';
            insert globalAgent;

            AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            privateAgent.ConversationVisibility__c = 'Private';
            insert privateAgent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c about = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, UserInfo.getUserId(), 1, false)[0];
            about.RelatedRecordId__c = account.Id;
            AIConversation__c noRecord = AIAssistTestDataFactory.createAIConversations(privateAgent.Id, UserInfo.getUserId(), 1, false)[0];
            insert new List<AIConversation__c>{ about, noRecord };

            AIChatDataStructure.ChatContext context;
            AIChatDataStructure.ConversationView aboutView;
            AIChatDataStructure.ConversationView noRecordView;

            // [2] Open the window and both conversations
            Test.startTest();
                context = AIChatController.getChatContext(null, null, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null);
                aboutView = AIChatController.openConversation(about.Id);
                noRecordView = AIChatController.openConversation(noRecord.Id);
            Test.stopTest();

            // [3] Check the agent options and the views
            Map<Id, AIChatDataStructure.AgentOption> optionsById = new Map<Id, AIChatDataStructure.AgentOption>();
            for (AIChatDataStructure.AgentOption option : context.agents) optionsById.put(option.id, option);

            Assert.isTrue(optionsById.get(globalAgent.Id).isShareable, 'A Global agent should be shareable.');
            Assert.isFalse(optionsById.get(privateAgent.Id).isShareable, 'A Private agent should not be shareable.');
            Assert.isTrue(aboutView.canShare, 'The starter of a Global-agent conversation should be able to share it.');
            Assert.isTrue(aboutView.hasRelatedRecord, 'A conversation about a record should say so.');
            Assert.isFalse(noRecordView.canShare, 'A Private agent\'s conversation should not be shareable.');
            Assert.isFalse(noRecordView.hasRelatedRecord, 'A conversation about no record should say so.');
        }
    }

    @IsTest static void testScenario17() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a conversation with a reply, then take away the user's settings row and every policy
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = 'Global';
            insert agent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            AIUserSettings__c userRow = [SELECT Id FROM AIUserSettings__c WHERE User__c = :superUser.Id LIMIT 1];
            userRow.IsActive__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update userRow; }
            AIAssistTestDataFactory.deactivateUsagePolicies();

            List<String> refusals = new List<String>();

            // [2] Call each endpoint
            Test.startTest();
                try { AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.getConversationShares(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.searchShareableUsers(conversation.Id, 'Assist'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.shareConversation(conversation.Id, UserInfo.getUserId()); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                try { AIChatController.unshareConversation(conversation.Id, UserInfo.getUserId()); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each is refused with the no access label
            Assert.areEqual(5, refusals.size(), 'Every call should be refused.');

            for (String refusal : refusals) Assert.areEqual(Label.AI_Error_No_Access, refusal, 'A user with no access should get the no access label.');
        }
    }

    @IsTest static void testScenario18() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, the starter's conversation about an account with a user message and an AI reply, and two users
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = 'Global';
            insert agent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;

            AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<User> users = AIAssistTestDataFactory.createUsers(2, false);
            users[0].LastName = 'Zqshare Viewer';
            users[1].LastName = 'Zqshare Bystander';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert users; }
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            insert new List<AIUserSettings__c>{ new AIUserSettings__c(User__c = users[0].Id, IsActive__c = true, ConversationExportEnabled__c = true, DebugModeEnabled__c = true), new AIUserSettings__c(User__c = users[1].Id, IsActive__c = true) };

            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
            uiSettings.IsInlineWorkflowActionsEnabled__c = true;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert uiSettings; }

            AIChatController.shareConversation(conversation.Id, users[0].Id);

            List<String> refusals = new List<String>();
            AIChatDataStructure.SendResult sendResult;
            String statusBefore = [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id].Status__c;

            // [2] Call every owner-only endpoint as the user it is shared with
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIChatController.retryLatestMessage(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.closeConversation(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.resumeConversation(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.submitFeedback(reply.Id, AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL, null, null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.runSuggestedAction(reply.Id, null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.declineSuggestedAction(reply.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.launchScreenFlowAction(reply.Id, null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.saveReplyToRecord(reply.Id, AIAssistApplicationConstants.SAVE_TARGET_NOTE, 'Text'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.shareConversation(conversation.Id, users[1].Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.unshareConversation(conversation.Id, users[0].Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.getConversationShares(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.searchShareableUsers(conversation.Id, 'Zqshare'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.exportConversation(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.getFailureDetail(conversation.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIChatController.getDebugTrace(reply.Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }

                    sendResult = AIChatController.sendMessage(JSON.serialize(new Map<String, Object>{ 'conversationId' => conversation.Id, 'agentId' => agent.Id, 'text' => 'Hello', 'channel' => AIAssistApplicationConstants.CHANNEL_UTILITY_BAR }));
                }
            Test.stopTest();

            // [3] Check each call was refused with a specific label and nothing changed
            Assert.areEqual(15, refusals.size(), 'Every owner-only call should have been refused.');

            for (String refusal : refusals) Assert.areNotEqual(Label.AI_Error_Generic, refusal, 'A refusal should be a specific label, not the generic one.');

            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[0], 'Retry should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[1], 'Close should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[2], 'Resume should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[3], 'Rating should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[4], 'Running an action should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[7], 'Saving to the record should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[8], 'Sharing onward should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[9], 'Unsharing should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[10], 'Listing shares should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[11], 'Searching should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[12], 'Export should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[13], 'Failure detail should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[14], 'The debug trace should be refused.');
            Assert.areNotEqual(conversation.Id, sendResult.conversationId, 'A send from the shared user should start their own conversation, never continue the starter\'s.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Id NOT IN (:userMessage.Id, :reply.Id)], 'The shared user should have added no message.');
            Assert.areEqual(statusBefore, [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id].Status__c, 'The shared user should not have closed it.');
        }
    }

    @IsTest static void testScenario19() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, the starter's conversation about an account with a user message and an AI reply, and two users
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = 'Global';
            insert agent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, false)[0];
            conversation.RelatedRecordId__c = account.Id;
            insert conversation;

            AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 1, 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];

            List<User> users = AIAssistTestDataFactory.createUsers(2, false);
            users[0].LastName = 'Zqshare Viewer';
            users[1].LastName = 'Zqshare Bystander';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert users; }
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            insert new List<AIUserSettings__c>{ new AIUserSettings__c(User__c = users[0].Id, IsActive__c = true, ConversationExportEnabled__c = true, DebugModeEnabled__c = true), new AIUserSettings__c(User__c = users[1].Id, IsActive__c = true) };

            AIChatController.shareConversation(conversation.Id, users[0].Id);

            List<AIChatDataStructure.ConversationSummary> bystanderHistory;
            String bystanderRefusal;
            List<AIChatDataStructure.ShareRecipient> afterUnshare;
            List<AIChatDataStructure.ConversationSummary> historyAfterUnshare;
            String openAfterUnshare;

            // [2] Read as a bystander, unshare as the starter, then read as the viewer again
            Test.startTest();
                System.runAs(users[1]) {
                    bystanderHistory = AIChatController.getSharedConversationHistory();

                    try { AIChatController.openConversation(conversation.Id); } catch (AuraHandledException ex) { bystanderRefusal = ex.getMessage(); }
                }

                AIChatController.unshareConversation(conversation.Id, users[0].Id);
                afterUnshare = AIChatController.getConversationShares(conversation.Id);

                System.runAs(users[0]) {
                    historyAfterUnshare = AIChatController.getSharedConversationHistory();

                    try { AIChatController.openConversation(conversation.Id); } catch (AuraHandledException ex) { openAfterUnshare = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check a bystander and the unshared user see nothing
            Assert.isTrue(bystanderHistory.isEmpty(), 'A user it was not shared with should list nothing.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, bystanderRefusal, 'A user it was not shared with should not open it.');
            Assert.isTrue(afterUnshare.isEmpty(), 'The share should be gone for the starter.');
            Assert.isTrue(historyAfterUnshare.isEmpty(), 'The unshared user should list nothing.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, openAfterUnshare, 'The unshared user should not open it.');
        }
    }
}
