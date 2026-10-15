/*
Class Name: AIUsageLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageLimitService: the per-minute rate limit, the user's concurrent conversations, the daily conversations and tokens limits (counted from the user's AIUsage__c record, which starts again each day), the shared queue ceiling and the cap on messages in flight.

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
    // testScenario3: Notify Only never refuses, no limits at all never refuses, and Block New Conversations Only lets messages in existing conversations through -> nothing is refused.
    // testScenario4: isInFlightCapReached with no cap, room under the cap and the cap reached -> false, false, true.
    // testScenario5: A full shared queue refuses the message as service busy, and room in the queue allows it -> only the full queue is refused with the service busy label.
    // testScenario6: A conversation idle for longer than its agent's timeout does not count towards the concurrent limit; one inside the timeout, and one on an agent with no timeout, do -> two are counted and the new conversation is only refused once all three places are taken.
    // testScenario7: A daily token limit that is used up, with Block New Conversations Only-> a new conversation is refused with the daily usage label and a message in an existing one is allowed.
    // testScenario8: A daily token limit that is used up, with Block New Messages -> both a new conversation and a message in an existing one are refused, while a user still under the limit is allowed.
    // testScenario9: Tokens spent on an earlier day do not count and the day's total starts again from the next tokens, and Notify Only never refuses -> nothing is refused.
    // testScenario10: A daily conversations limit counts only conversations started today, refuses only a new conversation, and never refuses under Notify Only -> one refusal, with the daily conversation label.
    // testScenario11: getLimitState with no limits, and with limits not yet reached -> null both times.
    // testScenario12: The token limit reached under each behaviour -> Block New Messages blocks messages and new conversations, Block New Conversations Only blocks only new conversations, Notify Only blocks nothing.
    // testScenario13: A daily conversations limit and a concurrent limit reached under Block New Messages -> each reports its own type and blocks new conversations only, never messages.
    // testScenario14: Tokens and conversations both reached -> the token limit is the one reported.
    // testScenario15: getUsageMeters with no limits, with one limit set and with all three set -> always three meters in the order tokens, daily conversations, open conversations; a limit that is not set has what is used and no max.

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
            Assert.isNull(context.usagePolicy, 'No policy limits are set, so nothing should be refused.');
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

            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxConcurrentConversations__c = 2, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

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

            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxConcurrentConversations__c = 1, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY);

            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true);

            // [2] Enforce the limits under Notify Only, with no limits at all, and Block New Conversations Only
            Test.startTest();
                AIUsageLimitService.enforceUsageLimits(context, true);

                context.usagePolicy = null;
                AIUsageLimitService.enforceUsageLimits(context, true);

                context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxConcurrentConversations__c = 1, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);
                AIUsageLimitService.enforceUsageLimits(context, false);
            Test.stopTest();

            // [3] Check nothing was refused
            Assert.isNotNull(context.usagePolicy, 'The last call ran with limits live; an existing conversation should still have been allowed.');
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

            // [2] Make one timed conversation idle and one untimed conversation old
            timed[0].LastMessageTimestamp__c = System.now().addHours(-2);
            timed[1].LastMessageTimestamp__c = System.now().addMinutes(-5);
            untimed.LastMessageTimestamp__c = System.now().addDays(-2);
            update new List<AIConversation__c>{ timed[0], timed[1], untimed };

            // [3] Create a three conversation limit and the chat context
            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agents[0];
            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxConcurrentConversations__c = 3, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

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
            // [1] Create a chat context with a 100 token daily limit under Block New Conversations Only
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
            context.userId = chatUser.Id;
            context.agent = agent;
            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

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
            overContext.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

            AIMessageValidator.ChatContext underContext = new AIMessageValidator.ChatContext();
            underContext.userId = chatUsers[1].Id;
            underContext.agent = agent;
            underContext.usagePolicy = overContext.usagePolicy;

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
            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);

            // [2] Spend the whole limit, then move that usage back to yesterday
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 500, 1, true);
            AIUsage__c usage = [SELECT Id FROM AIUsage__c WHERE User__c = :chatUser.Id LIMIT 1];
            usage.UsageDate__c = AIUsageService.getToday().addDays(-1);
            update usage;

            // [3] Enforce the limits, then spend the limit just now and enforce them again under Notify Only
            Test.startTest();
                Decimal tokensCounted = AIUsageLimitService.sumUserTokensToday(chatUser.Id);
                AIUsageLimitService.enforceUsageLimits(context, true);

                AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 500, 1, true);
                context.usagePolicy.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
                AIUsageLimitService.enforceUsageLimits(context, true);
                Decimal tokensCountedNow = AIUsageLimitService.sumUserTokensToday(chatUser.Id);
            Test.stopTest();

            // [4] Check the earlier day was left out and the new tokens counted without refusing
            Assert.areEqual(0, tokensCounted, 'Tokens spent on an earlier day should not count towards the daily limit.');
            Assert.areEqual(500, tokensCountedNow, 'Tokens spent today should be counted from zero, not added to the earlier day, and Notify Only should not refuse them.');
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
            context.usagePolicy = new AIUsagePolicy__c(IsActive__c = true, MaxConversationsPer24Hours__c = 2, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

            // [2] Start one conversation and move that usage back to yesterday, then start two more today
            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true);
            AIUsage__c usage = [SELECT Id FROM AIUsage__c WHERE User__c = :chatUser.Id LIMIT 1];
            usage.UsageDate__c = AIUsageService.getToday().addDays(-1);
            update usage;
            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 2, true);

            String overLimitRefusal;
            String existingConversationRefusal;
            String notifyOnlyRefusal;

            // [3] Enforce the limits for a new conversation, then an existing one, then a new one under Notify Only
            Test.startTest();
                Integer conversationsCounted = AIUsageLimitService.countUserConversationsToday(chatUser.Id);
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

                context.usagePolicy.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
                try {
                    AIUsageLimitService.enforceUsageLimits(context, true);
                } catch (AIUsageLimitService.AIUsageLimitServiceException ex) {
                    notifyOnlyRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [4] Check the earlier day was left out and only the new conversation at the limit was refused
            Assert.areEqual(2, conversationsCounted, 'The conversation started on an earlier day should not count.');
            Assert.areEqual(Label.AI_Error_Daily_Conversation_Limit, overLimitRefusal, 'A new conversation should be refused with the daily conversation Custom Label once the limit is reached.');
            Assert.isNull(existingConversationRefusal, 'A message in an existing conversation should never be refused by the conversations limit.');
            Assert.isNull(notifyOnlyRefusal, 'Notify Only should never refuse.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with a conversation that spent 50 tokens
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 50, 1, true);

            // [2] Ask with no limits, and with limits above what was used
            Test.startTest();
                AIChatDataStructure.UsageLimitState noLimits = AIUsageLimitService.getLimitState(chatUser.Id, null);
                AIChatDataStructure.UsageLimitState underLimits = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 5, MaxConcurrentConversations__c = 5, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES));
            Test.stopTest();

            // [3] Check nothing is reported
            Assert.isNull(noLimits, 'With no limits there is nothing to report.');
            Assert.isNull(underLimits, 'A user under every limit has reached none.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who has spent 100 tokens
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 100, 1, true);

            // [2] Ask under each behaviour with a 100 token limit
            Test.startTest();
                AIChatDataStructure.UsageLimitState blockMessages = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES));
                AIChatDataStructure.UsageLimitState blockConversations = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY));
                AIChatDataStructure.UsageLimitState notifyOnly = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY));
            Test.stopTest();

            // [3] Check what each one blocks
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS, blockMessages.limitType, 'The token limit should be reported.');
            Assert.areEqual(100, blockMessages.used, 'The tokens used should be reported.');
            Assert.areEqual(100, blockMessages.max, 'The limit should be reported.');
            Assert.isTrue(blockMessages.blocksMessages && blockMessages.blocksNewConversations && !blockMessages.isNotifyOnly, 'Block New Messages should block messages and new conversations.');
            Assert.isTrue(!blockConversations.blocksMessages && blockConversations.blocksNewConversations && !blockConversations.isNotifyOnly, 'Block New Conversations Only should block only new conversations.');
            Assert.isTrue(!notifyOnly.blocksMessages && !notifyOnly.blocksNewConversations && notifyOnly.isNotifyOnly, 'Notify Only should block nothing.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with one open conversation, which also counts as one started today
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true);

            // [2] Reach the concurrent limit alone, then the daily conversations limit alone, both under Block New Messages
            Test.startTest();
                AIChatDataStructure.UsageLimitState openState = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxConcurrentConversations__c = 1, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES));
                AIChatDataStructure.UsageLimitState dailyState = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxConversationsPer24Hours__c = 1, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES));
            Test.stopTest();

            // [3] Check each reports its type and blocks only a new conversation
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_OPEN, openState.limitType, 'The concurrent limit should be reported.');
            Assert.isTrue(openState.blocksNewConversations && !openState.blocksMessages, 'A conversation count never blocks a message.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_CONVERSATIONS, dailyState.limitType, 'The daily conversations limit should be reported.');
            Assert.isTrue(dailyState.blocksNewConversations && !dailyState.blocksMessages, 'A conversation count never blocks a message.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who has spent 100 tokens and started one conversation
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 100, 1, true);

            // [2] Reach every limit at once
            Test.startTest();
                AIChatDataStructure.UsageLimitState limitState = AIUsageLimitService.getLimitState(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 1, MaxConcurrentConversations__c = 1, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY));
            Test.stopTest();

            // [3] Check the token limit is the one reported
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS, limitState.limitType, 'The token limit should win when every limit is reached.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who has spent 40 tokens and has one open conversation
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
            AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 40, 1, true);

            // [2] Ask with no limits, with one limit and with all three
            Test.startTest();
                List<AIChatDataStructure.UsageMeter> noMeters = AIUsageLimitService.getUsageMeters(chatUser.Id, null);
                List<AIChatDataStructure.UsageMeter> oneMeter = AIUsageLimitService.getUsageMeters(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100));
                List<AIChatDataStructure.UsageMeter> allMeters = AIUsageLimitService.getUsageMeters(chatUser.Id, new AIUsagePolicy__c(IsActive__c = true, MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 5, MaxConcurrentConversations__c = 3));
            Test.stopTest();

            // [3] Check what each reports
            Assert.areEqual(3, noMeters.size(), 'With no limits there should still be a meter for each limit.');
            Assert.isNull(noMeters[0].max, 'A limit that is not set should have no max.');
            Assert.areEqual(40, noMeters[0].used, 'What was used should be reported even with no limit.');
            Assert.areEqual(3, oneMeter.size(), 'There should always be three meters.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_TOKENS, oneMeter[0].limitType, 'Tokens should come first.');
            Assert.areEqual(100, oneMeter[0].max, 'The limit should be reported.');
            Assert.isNull(oneMeter[1].max, 'A limit that is not set should have no max.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_CONVERSATIONS, allMeters[1].limitType, 'Daily conversations should come second.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_TYPE_OPEN, allMeters[2].limitType, 'Open conversations should come third.');
            Assert.areEqual(3, allMeters[2].max, 'The concurrent limit should be reported.');
            Assert.areEqual(1, allMeters[2].used, 'The open conversation should be counted.');
            Assert.isNull(AIUsageLimitService.getLimitState(noMeters, null), 'Meters with no limits reach nothing.');
        }
    }
}
