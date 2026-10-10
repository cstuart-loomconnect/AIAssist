/*
Class Name: AIUsageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageService and the triggers that feed it: one AIUsage__c record per user, added to through the day, started again on a new day, and linked to the user's settings when they have a row.

=================================================================
=================================================================
Applicable Classes:

AIUsageService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIUsageServiceTest {

    // testScenario1: Add usage for a user who has no record and a settings row -> one record is created for today with the totals and linked to the settings row.
    // testScenario2: Add usage twice on the same day -> the same record holds the sum of both.
    // testScenario3: Add usage when the record is from an earlier day -> the record starts again from zero, dated today, and the earlier day is not read back as today's.
    // testScenario4: Add usage for two users in one call, one with a record and one without -> each user has their own record with their own totals.
    // testScenario5: Insert conversations and messages through the triggers -> the owner's usage holds the conversations started and the tokens, with the input and output split.
    // testScenario6: Add usage with null and empty input, and read usage for a user with none -> nothing is created, nothing is logged and the reads are zero.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with a settings row
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIUserSettings__c userSettings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, true)[0];

            AIUsageService.UsageToAdd addition = new AIUsageService.UsageToAdd();
            addition.tokens = 100;
            addition.inputTokens = 60;
            addition.outputTokens = 40;
            addition.conversations = 1;

            // [2] Add the usage
            Test.startTest();
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>{chatUser.Id => addition});
            Test.stopTest();

            // [3] Query the usage
            List<AIUsage__c> usageRows = [SELECT UsageDate__c, TokensUsed__c, InputTokens__c, OutputTokens__c, ConversationsStarted__c, AIUserSettings__c FROM AIUsage__c WHERE User__c = :chatUser.Id];

            // [4] Check one record holds the totals for today and is linked to the settings
            Assert.areEqual(1, usageRows.size(), 'One usage record should be created for the user.');
            Assert.areEqual(AIUsageService.getToday(), usageRows[0].UsageDate__c, 'The record should be dated today.');
            Assert.areEqual(100, usageRows[0].TokensUsed__c, 'The tokens should be recorded.');
            Assert.areEqual(60, usageRows[0].InputTokens__c, 'The input tokens should be recorded.');
            Assert.areEqual(40, usageRows[0].OutputTokens__c, 'The output tokens should be recorded.');
            Assert.areEqual(1, usageRows[0].ConversationsStarted__c, 'The conversation should be recorded.');
            Assert.areEqual(userSettings.Id, usageRows[0].AIUserSettings__c, 'The record should be linked to the user\'s settings row.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user and the usage to add
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            AIUsageService.UsageToAdd addition = new AIUsageService.UsageToAdd();
            addition.tokens = 100;
            addition.conversations = 1;

            // [2] Add it twice
            Test.startTest();
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>{chatUser.Id => addition});
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>{chatUser.Id => addition});
            Test.stopTest();

            // [3] Query the usage
            List<AIUsage__c> usageRows = [SELECT TokensUsed__c, ConversationsStarted__c, AIUserSettings__c FROM AIUsage__c WHERE User__c = :chatUser.Id];

            // [4] Check one record holds both, with no settings link as the user has no settings row
            Assert.areEqual(1, usageRows.size(), 'The second addition should use the same record.');
            Assert.areEqual(200, usageRows[0].TokensUsed__c, 'The tokens of both additions should be summed.');
            Assert.areEqual(2, usageRows[0].ConversationsStarted__c, 'The conversations of both additions should be summed.');
            Assert.isNull(usageRows[0].AIUserSettings__c, 'A user with no settings row should have no settings link.');
            Assert.areEqual(200, AIUsageService.getTokensUsedToday(chatUser.Id), 'Today\'s tokens should be read back.');
            Assert.areEqual(2, AIUsageService.getConversationsStartedToday(chatUser.Id), 'Today\'s conversations should be read back.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with a record from yesterday
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            insert new AIUsage__c(User__c = chatUser.Id, UsageDate__c = AIUsageService.getToday().addDays(-1), TokensUsed__c = 900, InputTokens__c = 500, OutputTokens__c = 400, ConversationsStarted__c = 7);

            Decimal tokensBefore = AIUsageService.getTokensUsedToday(chatUser.Id);

            AIUsageService.UsageToAdd addition = new AIUsageService.UsageToAdd();
            addition.tokens = 100;
            addition.conversations = 1;

            // [2] Add usage today
            Test.startTest();
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>{chatUser.Id => addition});
            Test.stopTest();

            // [3] Query the usage
            List<AIUsage__c> usageRows = [SELECT UsageDate__c, TokensUsed__c, InputTokens__c, OutputTokens__c, ConversationsStarted__c FROM AIUsage__c WHERE User__c = :chatUser.Id];

            // [4] Check yesterday was not read as today's, and the record started again from zero
            Assert.areEqual(0, tokensBefore, 'Yesterday\'s tokens should not count as today\'s.');
            Assert.areEqual(1, usageRows.size(), 'The same record should be reused, not a second one made.');
            Assert.areEqual(AIUsageService.getToday(), usageRows[0].UsageDate__c, 'The record should now be dated today.');
            Assert.areEqual(100, usageRows[0].TokensUsed__c, 'The tokens should start again from zero.');
            Assert.areEqual(0, usageRows[0].InputTokens__c, 'The input tokens should start again from zero.');
            Assert.areEqual(0, usageRows[0].OutputTokens__c, 'The output tokens should start again from zero.');
            Assert.areEqual(1, usageRows[0].ConversationsStarted__c, 'The conversations should start again from zero.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users, one of them with a record already
            List<User> chatUsers = AIAssistTestDataFactory.createUsers(2, true);
            insert new AIUsage__c(User__c = chatUsers[0].Id, UsageDate__c = AIUsageService.getToday(), TokensUsed__c = 50);

            AIUsageService.UsageToAdd firstAddition = new AIUsageService.UsageToAdd();
            firstAddition.tokens = 10;

            AIUsageService.UsageToAdd secondAddition = new AIUsageService.UsageToAdd();
            secondAddition.tokens = 20;

            // [2] Add usage for both in one call
            Test.startTest();
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>{chatUsers[0].Id => firstAddition, chatUsers[1].Id => secondAddition});
            Test.stopTest();

            // [3] Read each user's tokens
            Decimal firstTokens = AIUsageService.getTokensUsedToday(chatUsers[0].Id);
            Decimal secondTokens = AIUsageService.getTokensUsedToday(chatUsers[1].Id);

            // [4] Check each user has their own total
            Assert.areEqual(60, firstTokens, 'The user with a record should have the addition added to it.');
            Assert.areEqual(20, secondTokens, 'The user without a record should get one with the addition.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user and an agent
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            // [2] Start two conversations, then add an AI reply with its split and a failed turn that spent tokens
            Test.startTest();
                List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 2, true);
                AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversations[0].Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 100, 1, false)[0];
                reply.InputTokenCount__c = 60;
                reply.OutputTokenCount__c = 40;
                AIConversationMessage__c failedTurn = AIAssistTestDataFactory.createAIConversationMessages(conversations[1].Id, AIAssistApplicationConstants.SENDER_SYSTEM, 20, 1, false)[0];
                insert new List<AIConversationMessage__c>{reply, failedTurn};
            Test.stopTest();

            // [3] Query the usage
            List<AIUsage__c> usageRows = [SELECT TokensUsed__c, InputTokens__c, OutputTokens__c, ConversationsStarted__c FROM AIUsage__c WHERE User__c = :chatUser.Id];

            // [4] Check the owner's usage holds the conversations and every token spent
            Assert.areEqual(1, usageRows.size(), 'The owner should have one usage record.');
            Assert.areEqual(2, usageRows[0].ConversationsStarted__c, 'Both conversations should be counted.');
            Assert.areEqual(120, usageRows[0].TokensUsed__c, 'The reply and the failed turn should both be counted.');
            Assert.areEqual(60, usageRows[0].InputTokens__c, 'The input tokens should be counted.');
            Assert.areEqual(40, usageRows[0].OutputTokens__c, 'The output tokens should be counted.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with no usage
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            // [2] Add usage with null and empty input, and read usage for a user with none and for no user
            Test.startTest();
                AIUsageService.addUsage(null);
                AIUsageService.addUsage(new Map<Id, AIUsageService.UsageToAdd>());
                Decimal tokens = AIUsageService.getTokensUsedToday(chatUser.Id);
                Integer conversations = AIUsageService.getConversationsStartedToday(null);
            Test.stopTest();

            // [3] Count the records and logs
            Integer usageCount = [SELECT COUNT() FROM AIUsage__c];
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIUsageService'];

            // [4] Check nothing was created or logged and the reads are zero
            Assert.areEqual(0, usageCount, 'Nothing should be created for empty input.');
            Assert.areEqual(0, logCount, 'Empty input should not be logged.');
            Assert.areEqual(0, tokens, 'A user with no usage should read zero tokens.');
            Assert.areEqual(0, conversations, 'No user should read zero conversations.');
        }
    }
}
