/*
Class Name: AIUsageLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageLimitService: the per-minute rate limit, the user's concurrent conversations, the daily conversations and tokens limits, the shared queue ceiling and the cap on messages in flight.

=================================================================
=================================================================
Applicable Classes:

AIUsageLimitService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIUsageLimitServiceTest {

    // testScenario1: With no limits set anywhere a message is allowed, for a new conversation and for an existing one -> nothing is refused.
    // testScenario2: The concurrent conversation limit refuses a new conversation once the user has that many active, and does not refuse a message in an existing one -> only the new conversation is refused with the concurrent limit label.
    // testScenario3: Notify Only never refuses, an inactive settings row never refuses, and Block New Conversations Only lets messages in existing conversations through -> nothing is refused.
    // testScenario4: isInFlightCapReached with no cap, room under the cap and the cap reached -> false, false, true.
    // testScenario5: A full shared queue refuses the message as service busy, and room in the queue allows it -> only the full queue is refused with the service busy label.
    // testScenario6: A conversation idle for longer than its agent's timeout does not count towards the concurrent limit; one inside the timeout, and one on an agent with no timeout, do -> two are counted and the new conversation is only refused once all three places are taken.

    // testScenario7: A daily token limit that is used up, with Block New Conversations Only and a limit that came from a policy rather than a saved row -> a new conversation is refused with the daily usage label and a message in an existing one is allowed.
    // testScenario8: A daily token limit that is used up, with Block New Messages -> both a new conversation and a message in an existing one are refused, while a user still under the limit is allowed.
    // testScenario9: Tokens spent more than 24 hours ago do not count, and Notify Only never refuses -> nothing is refused.
    // testScenario10: A daily conversations limit counts only conversations started in the last 24 hours, refuses only a new conversation, and never refuses under Notify Only -> one refusal, with the daily conversation label.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user, an agent and a chat context with no limits
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;

            // [2] Enforce the limits for a new and an existing conversation
            Test.startTest();
                AIUsageLimitService.enforceUsageLimits(context, true);
                AIUsageLimitService.enforceUsageLimits(context, false);
            Test.stopTest();

            // [3] Check nothing was refused
            Assert.isNull(context.userSettings, 'The user has no settings row, and no limit is set, so nothing should be refused.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context, a two conversation limit and two active conversations
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;

            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            settings.MaxConcurrentConversations__c = 2;
            settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert settings; }
            context.userSettings = settings;

            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 2, true);

            String refusalMessage;

            // [2] Enforce the limits for an existing conversation, then a new one
            Test.startTest();
                AIUsageLimitService.enforceUsageLimits(context, false);
                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    refusalMessage = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check only the new conversation was refused
            Assert.areEqual(Label.AI_Error_Concurrent_Limit, refusalMessage, 'A third active conversation should be refused with the concurrent limit Custom Label.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context, a one conversation limit and one active conversation
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;

            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            settings.MaxConcurrentConversations__c = 1;
            settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert settings; }
            context.userSettings = settings;

            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true);

            // [2] Enforce the limits under Notify Only, an inactive row and Block New Conversations Only
            Test.startTest();
                AIUsageLimitService.enforceUsageLimits(context, true);

                settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
                settings.IsActive__c = false;
                AIUsageLimitService.enforceUsageLimits(context, true);

                settings.IsActive__c = true;
                settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
                AIUsageLimitService.enforceUsageLimits(context, false);
            Test.stopTest();

            // [3] Check nothing was refused
            Assert.isTrue(settings.IsActive__c, 'The last call ran with limits live; an existing conversation should still have been allowed.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Prepare the settings and the results to capture
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            Boolean noCap;
            Boolean belowCap;
            Boolean atCap;

            // [2] Check the in-flight cap with no cap, room under the cap and the cap reached
            Test.startTest();
                settings.MaxMessagesInFlight__c = null;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
                AIAssistSettingsService.cachedSettings = null;
                AIUsageLimitService.inFlightForTest = 100;
                noCap = AIUsageLimitService.isInFlightCapReached();

                settings.MaxMessagesInFlight__c = 3;
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
                AIAssistSettingsService.cachedSettings = null;
                AIUsageLimitService.inFlightForTest = 2;
                belowCap = AIUsageLimitService.isInFlightCapReached();

                AIUsageLimitService.inFlightForTest = 3;
                atCap = AIUsageLimitService.isInFlightCapReached();
            Test.stopTest();

            // [3] Check the cap is only reached when it is set and full
            Assert.isFalse(noCap, 'With no cap set nothing is held back.');
            Assert.isFalse(belowCap, 'A place is still free.');
            Assert.isTrue(atCap, 'The cap is reached.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;

            String refusalMessage;

            // [2] Enforce the limits with room in the queue, then with a full queue
            Test.startTest();
                AIUsageLimitService.maxPendingJobsForTest = 1000;
                AIUsageLimitService.enforceUsageLimits(context, false);

                AIUsageLimitService.maxPendingJobsForTest = 0;
                try {
                    AIUsageLimitService.enforceUsageLimits(context, false);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    refusalMessage = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check only the full queue was refused as service busy
            Assert.areEqual(Label.AI_Error_Service_Busy, refusalMessage, 'A ceiling of zero is always full, so the message should be refused as service busy, not as the provider being unavailable.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a timed agent and an untimed one, with conversations on each
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, false);
            agents[0].IdleTimeoutMinutes__c = 30;
            agents[1].IdleTimeoutMinutes__c = null;
            insert agents;

            List<AIConversation__c> timed = AIAssistTestDataFactory.createAIConversations(agents[0].Id, chatUser.Id, 2, true);
            AIConversation__c untimed = AIAssistTestDataFactory.createAIConversations(agents[1].Id, chatUser.Id, 1, true)[0];
            // One conversation on the timed agent went quiet two hours ago; the one with no timeout went quiet two days ago.

            // [2] Make one timed conversation idle and one untimed conversation old
            timed[0].LastMessageTimestamp__c = System.now().addHours(-2);
            timed[1].LastMessageTimestamp__c = System.now().addMinutes(-5);
            untimed.LastMessageTimestamp__c = System.now().addDays(-2);
            update new List<AIConversation__c>{ timed[0], timed[1], untimed };

            // [3] Create a three conversation limit and the chat context
            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            settings.MaxConcurrentConversations__c = 3;
            settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert settings; }

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agents[0];
            context.userSettings = settings;

            String firstRefusal;
            String secondRefusal;

            // [4] Count the active conversations and enforce the limits before and after the idle one is active again
            Test.startTest();
                Integer counted = AIUsageLimitService.countActiveConversations(chatUser.Id);

                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    firstRefusal = ex.getMessage();
                }

                timed[0].LastMessageTimestamp__c = System.now();
                update timed[0];

                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    secondRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [5] Check the idle one was not counted and the new conversation was refused only once all three places were taken
            Assert.areEqual(2, counted, 'The idle conversation is not counted; the recent one and the one with no timeout are.');
            Assert.isNull(firstRefusal, 'Two of three places are taken, so the new conversation should be allowed.');
            Assert.areEqual(Label.AI_Error_Concurrent_Limit, secondRefusal, 'Once the idle conversation is active again all three places are taken.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context whose daily token limit came from a policy, so the settings are not saved
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;
            context.userSettings = new AIUserSettings__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

            // [2] Spend exactly the limit in one of the user's conversations
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 100, 1, true);

            String refusalMessage;

            // [3] Enforce the limits for an existing conversation, then a new one
            Test.startTest();
                AIUsageLimitService.enforceUsageLimits(context, false);
                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    refusalMessage = ex.getMessage();
                }
            Test.stopTest();

            // [4] Check only the new conversation was refused
            Assert.areEqual(Label.AI_Error_Daily_Usage_Limit, refusalMessage, 'A new conversation should be refused with the daily usage Custom Label once the daily tokens are used up.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users, each with a 100 token Block New Messages limit
            List<User> chatUsers = AIAssistTestDataFactory.createUsers(2, true);

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext overContext = new AIMessageValidator.ChatContext();
            overContext.userId = chatUsers[0].Id;
            overContext.agent = agent;
            overContext.userSettings = new AIUserSettings__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

            AIMessageValidator.ChatContext underContext = new AIMessageValidator.ChatContext();
            underContext.userId = chatUsers[1].Id;
            underContext.agent = agent;
            underContext.userSettings = overContext.userSettings;

            // [2] Spend the limit for the first user and one token less for the second
            AIConversation__c overConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUsers[0].Id, 1, true)[0];
            AIConversation__c underConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUsers[1].Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(overConversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 60, 2, true);
            AIAssistTestDataFactory.createAIConversationMessages(underConversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 99, 1, true);

            String newConversationRefusal;
            String existingConversationRefusal;
            String underLimitRefusal;

            // [3] Enforce the limits for the first user twice and the second user once
            Test.startTest();
                try {
                    AIUsageLimitService.enforceUsageLimits(overContext, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    newConversationRefusal = ex.getMessage();
                }
                try {
                    AIUsageLimitService.enforceUsageLimits(overContext, false);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    existingConversationRefusal = ex.getMessage();
                }
                try {
                    AIUsageLimitService.enforceUsageLimits(underContext, false);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    underLimitRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [4] Check the user over the limit was refused both times and the user under it was not
            Assert.areEqual(Label.AI_Error_Daily_Usage_Limit, newConversationRefusal, 'Block New Messages should refuse a new conversation once the tokens are used up.');
            Assert.areEqual(Label.AI_Error_Daily_Usage_Limit, existingConversationRefusal, 'Block New Messages should also refuse a message in an existing conversation.');
            Assert.isNull(underLimitRefusal, 'A user who is one token under the limit should not be refused.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context with a 100 token Block New Messages limit
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;
            context.userSettings = new AIUserSettings__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

            // [2] Spend the whole limit, but more than 24 hours ago
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            List<AIConversationMessage__c> oldMessages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 500, 1, true);
            Test.setCreatedDate(oldMessages[0].Id, System.now().addHours(-25));

            // [3] Enforce the limits, then spend the limit just now and enforce them again under Notify Only
            Test.startTest();
                Decimal tokensCounted = AIUsageLimitService.sumUserTokensLast24Hours(chatUser.Id);
                AIUsageLimitService.enforceUsageLimits(context, true);

                AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 500, 1, true);
                context.userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
                AIUsageLimitService.enforceUsageLimits(context, true);
                Decimal tokensCountedNow = AIUsageLimitService.sumUserTokensLast24Hours(chatUser.Id);
            Test.stopTest();

            // [4] Check the old tokens were left out and the new ones counted without refusing
            Assert.areEqual(0, tokensCounted, 'Tokens spent 25 hours ago should not count towards the daily limit.');
            Assert.areEqual(500, tokensCountedNow, 'Tokens spent just now should be counted, and Notify Only should not refuse them.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat context with a two conversations a day limit
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;
            context.userSettings = new AIUserSettings__c(IsActive__c = true, MaxConversationsPer24Hours__c = 2, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

            // [2] Create three conversations, one of them started 25 hours ago
            List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 3, true);
            Test.setCreatedDate(conversations[0].Id, System.now().addHours(-25));

            String overLimitRefusal;
            String existingConversationRefusal;
            String notifyOnlyRefusal;

            // [3] Enforce the limits for a new conversation, then an existing one, then a new one under Notify Only
            Test.startTest();
                Integer conversationsCounted = AIUsageLimitService.countUserConversationsLast24Hours(chatUser.Id);
                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    overLimitRefusal = ex.getMessage();
                }

                try {
                    AIUsageLimitService.enforceUsageLimits(context, false);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    existingConversationRefusal = ex.getMessage();
                }

                context.userSettings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    notifyOnlyRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [4] Check the old conversation was left out and only the new conversation at the limit was refused
            Assert.areEqual(2, conversationsCounted, 'The conversation started 25 hours ago should not count.');
            Assert.areEqual(Label.AI_Error_Daily_Conversation_Limit, overLimitRefusal, 'A new conversation should be refused with the daily conversation Custom Label once the limit is reached.');
            Assert.isNull(existingConversationRefusal, 'A message in an existing conversation should never be refused by the conversations limit.');
            Assert.isNull(notifyOnlyRefusal, 'Notify Only should never refuse.');
        }
    }
}
