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
    // testScenario10: Shared history merges the scope-based rows with the directly shared ones -> no duplicates, Private agents left out, and a viewer on the narrowest scope (the default policy) sees only the direct ones.
    // testScenario11: A view says whether the viewer may share it and whether it is about a record -> true only for the starter of a Global-agent conversation, and only for a valid record Id.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            List<Id> badIds = new List<Id>{
                theirs.Id,
                agent.Id,
                null
            };

            Test.startTest();
                ownId = AIChatConversationService.getOwnedConversation(conversation.Id).Id;
                replyId = AIChatConversationService.getOwnedAgentMessage(reply.Id).Id;

                for (Id bad : badIds) {

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

            for (String refusal : messages) {

                Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusal, 'Each refusal should be the not found Custom Label.');
            }
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent that allows resume
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            agent.AllowConversationResume__c = true;
            update agent;

            // [2] Limit the user's concurrent conversations and fill the limit
            AIAssistTestDataFactory.createAIUsagePolicyForUser(UserInfo.getUserId(), 1, null, null, null);

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
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation, another user and a data source
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];

            User other = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            String sourceName = [SELECT DeveloperName__c FROM AIDataSource__c WHERE Id = :source.Id].DeveloperName__c;

            // [2] Define a trace step of each type
            AIExecutionStepRecorder.TraceStep providerStep = new AIExecutionStepRecorder.TraceStep();
            providerStep.stepType = AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL;
            providerStep.status = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
            providerStep.step = 2;
            providerStep.ms = 40;
            AIExecutionStepRecorder.TraceStep maskingStep = new AIExecutionStepRecorder.TraceStep();
            maskingStep.stepType = AIAssistApplicationConstants.STEP_TYPE_PII_MASKING;
            AIExecutionStepRecorder.TraceStep otherStep = new AIExecutionStepRecorder.TraceStep();
            otherStep.stepType = AIAssistApplicationConstants.STEP_TYPE_OTHER;
            AIExecutionStepRecorder.TraceStep detailStep = new AIExecutionStepRecorder.TraceStep();
            detailStep.stepDetail = 'Custom';

            // [3] Build an execution step of each type
            AIChatDataStructure.ExecutionStep provider;
            AIChatDataStructure.ExecutionStep masking;
            AIChatDataStructure.ExecutionStep anyOther;
            AIChatDataStructure.ExecutionStep detail;

            Test.startTest();
                provider = AIChatConversationService.buildExecutionStep(providerStep);
                masking = AIChatConversationService.buildExecutionStep(maskingStep);
                anyOther = AIChatConversationService.buildExecutionStep(otherStep);
                detail = AIChatConversationService.buildExecutionStep(detailStep);
            Test.stopTest();

            // [4] Check each step label
            Assert.areEqual(Label.AI_Step_Calling_Model, provider.label, 'A provider call should get the calling model label.');
            Assert.isTrue(provider.isSuccess && provider.durationMs == 40 && provider.stepOrder == 2, 'The step should carry its success, time and order.');

            Assert.areEqual(Label.AI_Step_Protecting_Data, masking.label, 'PII masking should get the protecting data label.');

            Assert.areEqual(Label.AI_Step_Finalising, anyOther.label, 'Any other step type should get the finalising label.');

            Assert.areEqual('Custom', detail.label, 'The stored step detail should win over the label.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global and a Private agent, an account and four users in a role hierarchy
            AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            globalAgent.ConversationVisibility__c = 'Global';
            insert globalAgent;

            AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            privateAgent.ConversationVisibility__c = 'Private';
            insert privateAgent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(4, true);

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {
                UserRole parentRole = new UserRole(Name = 'AI Assist Test Parent');
                insert parentRole;
                UserRole childRole = new UserRole(Name = 'AI Assist Test Child', ParentRoleId = parentRole.Id);
                insert childRole;
                users[0].UserRoleId = parentRole.Id;
                users[1].UserRoleId = childRole.Id;
                update users;
            }

            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            AIAssistTestDataFactory.createAIUsagePolicyForUser(users[0].Id, new AIUsagePolicy__c(ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES));

            // [2] Create a subordinate's conversation (also shared directly), a peer's shared directly, a subordinate's on the Private agent and an unshared peer's
            AIConversation__c subordinateAndShared = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, users[1].Id, 1, false)[0];
            AIConversation__c subordinateOnly = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, users[1].Id, 1, false)[0];
            AIConversation__c peerShared = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, users[2].Id, 1, false)[0];
            AIConversation__c peerNotShared = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, users[2].Id, 1, false)[0];
            AIConversation__c onPrivate = AIAssistTestDataFactory.createAIConversations(privateAgent.Id, users[2].Id, 1, false)[0];
            List<AIConversation__c> all = new List<AIConversation__c>{
                subordinateAndShared,
                subordinateOnly,
                peerShared,
                peerNotShared,
                onPrivate
            };

            for (AIConversation__c conversation : all) {

                conversation.RelatedRecordId__c = account.Id;
            }

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert all;
            }

            System.runAs(users[1]) {

                AIConversationShareService.shareConversation(subordinateAndShared.Id, users[0].Id);
                AIConversationShareService.shareConversation(subordinateAndShared.Id, users[3].Id);
            }

            System.runAs(users[2]) {

                AIConversationShareService.shareConversation(peerShared.Id, users[0].Id);
                AIConversationShareService.shareConversation(peerShared.Id, users[3].Id);
            }

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert new AIConversation__Share(ParentId = onPrivate.Id, UserOrGroupId = users[0].Id, AccessLevel = 'Read', RowCause = Schema.AIConversation__Share.RowCause.DirectShare__c);
            }

            List<AIChatDataStructure.ConversationSummary> managerHistory;
            List<AIChatDataStructure.ConversationSummary> narrowHistory;

            // [3] Read the shared history as the manager and as a viewer on the narrowest scope
            Test.startTest();
                System.runAs(users[0]) {

                    managerHistory = AIChatConversationService.getSharedConversationHistory();
                }

                System.runAs(users[3]) {

                    narrowHistory = AIChatConversationService.getSharedConversationHistory();
                }
            Test.stopTest();

            // [4] Check the merge, with no duplicates and no Private agent
            Set<Id> managerIds = new Set<Id>();

            for (AIChatDataStructure.ConversationSummary summary : managerHistory) {

                managerIds.add(summary.id);
            }

            Set<Id> narrowIds = new Set<Id>();

            for (AIChatDataStructure.ConversationSummary summary : narrowHistory) {

                narrowIds.add(summary.id);
            }

            AIConversation__c subordinateOnlyAfter = [SELECT OwnerId FROM AIConversation__c WHERE Id = :subordinateOnly.Id];

            Assert.areEqual(3, managerHistory.size(), 'A conversation in scope and shared directly should be listed once.');
            Assert.areEqual(new Set<Id>{ subordinateAndShared.Id, subordinateOnly.Id, peerShared.Id }, managerIds, 'The manager should see the subordinate\'s two and the peer\'s shared one.');
            Assert.areEqual(new Set<Id>{ subordinateAndShared.Id, peerShared.Id }, narrowIds, 'A viewer on the narrowest scope should see only what was shared with them.');
            Assert.areEqual(users[1].Id, subordinateOnlyAfter.OwnerId, 'The owner should be unchanged by sharing.');
            Assert.isNotNull(managerHistory[0].ownerName, 'Each shared row should name its owner.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global and a Private agent, an account, a user who is shared a conversation, and conversations to view
            AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            globalAgent.ConversationVisibility__c = 'Global';
            insert globalAgent;

            AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            privateAgent.ConversationVisibility__c = 'Private';
            insert privateAgent;

            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            User viewer = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ viewer }, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIConversation__c onGlobal = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, UserInfo.getUserId(), 1, false)[0];
            onGlobal.RelatedRecordId__c = account.Id;
            AIConversation__c onPrivate = AIAssistTestDataFactory.createAIConversations(privateAgent.Id, UserInfo.getUserId(), 1, false)[0];
            onPrivate.RelatedRecordId__c = account.Id;
            AIConversation__c noRecord = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, UserInfo.getUserId(), 1, false)[0];
            AIConversation__c badRecord = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, UserInfo.getUserId(), 1, false)[0];
            badRecord.RelatedRecordId__c = 'not-a-record-id';
            List<AIConversation__c> toInsert = new List<AIConversation__c>{
                onGlobal,
                onPrivate,
                noRecord,
                badRecord
            };
            insert toInsert;
            AIConversationShareService.shareConversation(onGlobal.Id, viewer.Id);

            AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
            AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
            ui.messagePageSize = 3;
            AIChatDataStructure.ConversationView globalView;
            AIChatDataStructure.ConversationView privateView;
            AIChatDataStructure.ConversationView noRecordView;
            AIChatDataStructure.ConversationView badRecordView;
            AIChatDataStructure.ConversationView sharedView;

            // [2] Build each view as the starter, and the shared one as the viewer
            Test.startTest();
                globalView = AIChatConversationService.buildConversationView(onGlobal.Id, 3, user, ui);
                privateView = AIChatConversationService.buildConversationView(onPrivate.Id, 3, user, ui);
                noRecordView = AIChatConversationService.buildConversationView(noRecord.Id, 3, user, ui);
                badRecordView = AIChatConversationService.buildConversationView(badRecord.Id, 3, user, ui);
                System.runAs(viewer) {

                    sharedView = AIChatConversationService.buildConversationView(onGlobal.Id, 3, user, ui);
                }
            Test.stopTest();

            // [3] Check the flags
            Assert.isTrue(globalView.canShare, 'The starter of a Global-agent conversation may share it.');
            Assert.isTrue(globalView.hasRelatedRecord, 'A conversation about a record should say so.');
            Assert.isFalse(privateView.canShare, 'A Private agent\'s conversation may not be shared.');
            Assert.isTrue(privateView.hasRelatedRecord, 'A Private agent\'s conversation can still be about a record.');
            Assert.isFalse(noRecordView.hasRelatedRecord, 'A conversation with no record should say so.');
            Assert.isFalse(badRecordView.hasRelatedRecord, 'A value that is not a record Id should not count.');
            Assert.isFalse(sharedView.canShare, 'A viewer it was shared with may not share it onward.');
        }
    }
}
