/*
Class Name: AIUsageLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageLimitService: the user's own limits, the organisation's plan limits and daily budget, and the shared queue ceiling.

=================================================================
=================================================================
Applicable Classes:

AIUsageLimitService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUsageLimitServiceTest {
  // testScenario1: With no limits set anywhere a message is allowed, for a new conversation and for an existing one.
  // testScenario2: The concurrent conversation limit refuses a new conversation once the user has that many active, and does not refuse a message in an existing one.
  // testScenario3: The daily conversation limit refuses a new conversation at the limit and allows one just under it.
  // testScenario4: The daily token limit counts the estimate for this message, so a message that would pass the limit is refused, and one that stays under is allowed.
  // testScenario5: Notify Only never refuses, an inactive settings row never refuses, and Block New Conversations Only lets messages in existing conversations through.
  // testScenario6: The plan's monthly message limit refuses once the month's messages reach it.
  // testScenario7: The plan's monthly token limit refuses once the month's tokens reach it.
  // testScenario8: The organisation's daily token budget refuses once today's tokens, from every user, reach it.
  // testScenario9: A full shared queue refuses the message as service busy, and room in the queue allows it.
  // testScenario10: A conversation idle for longer than its agent's timeout does not count towards the concurrent limit; one inside the timeout, and one on an agent with no timeout, do.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    Test.startTest();
    try {
      AIUsageLimitService.enforceUsageLimits(context, true, 100);
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
    } catch (AIMessagingException ex) {
      Assert.fail('No limit is set, so nothing should be refused: ' + ex.code);
    }
    Test.stopTest();

    Assert.isNull(context.userSettings, 'The user has no settings row.');
  }

  @IsTest
  static void testScenario2() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.MaxConcurrentConversations__c = 2;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    insert settings;
    context.userSettings = settings;
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      2,
      true
    );
    String code;

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, false, 100);
    try {
      AIUsageLimitService.enforceUsageLimits(context, true, 100);
      Assert.fail('A third active conversation should have been refused.');
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Concurrent_Limit,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
      code,
      'The concurrent limit.'
    );
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.MaxConversationsPer24Hours__c = 3;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    insert settings;
    context.userSettings = settings;
    AIUsageDaily__c usage = AIAssistTestDataFactory.createAIUsageDailies(
      chatUser.Id,
      agent.Id,
      model.Id,
      1,
      false
    )[0];
    usage.ConversationCount__c = 2;
    insert usage;
    String code;

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, true, 100);
    usage.ConversationCount__c = 3;
    update usage;
    try {
      AIUsageLimitService.enforceUsageLimits(context, true, 100);
      Assert.fail(
        'The third conversation of the day was already used, so a fourth should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Conversation_Limit_Daily,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_LIMIT_DAILY,
      code,
      'The daily conversation limit.'
    );
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.MaxTokensPer24Hours__c = 1000;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    insert settings;
    context.userSettings = settings;
    AIUsageDaily__c usage = AIAssistTestDataFactory.createAIUsageDailies(
      chatUser.Id,
      agent.Id,
      model.Id,
      1,
      false
    )[0];
    usage.InputTokens__c = 600;
    usage.OutputTokens__c = 300;
    insert usage;
    String code;

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, false, 50);
    try {
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
      Assert.fail(
        '900 used plus 100 estimated reaches the 1000 limit, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Daily_Usage_Limit,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
      code,
      'The daily usage limit.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    List<AIUserSettings__c> allSettings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    );
    AIUserSettings__c settings = allSettings[0];
    settings.MaxTokensPer24Hours__c = 1;
    settings.MaxConcurrentConversations__c = 1;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY;
    insert settings;
    context.userSettings = settings;
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    );

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, true, 1000);

    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    settings.IsActive__c = false;
    AIUsageLimitService.enforceUsageLimits(context, true, 1000);

    settings.IsActive__c = true;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    AIUsageLimitService.enforceUsageLimits(context, false, 1000);
    Test.stopTest();

    Assert.isTrue(
      settings.IsActive__c,
      'The last call ran with limits live; an existing conversation was still allowed.'
    );
  }

  @IsTest
  static void testScenario6() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIUsageDaily__c usage = AIAssistTestDataFactory.createAIUsageDailies(
      chatUser.Id,
      agent.Id,
      model.Id,
      1,
      false
    )[0];
    usage.MessageCount__c = 10;
    insert usage;
    String code;

    Test.startTest();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      11
    );
    AIUsageLimitService.enforceUsageLimits(context, false, 100);
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_MESSAGES,
      10
    );
    try {
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
      Assert.fail(
        'Ten of ten messages are used, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        AIUsageLimitService.planLimitMessage(
          Label.AI_Error_Plan_Limit_Messages,
          10,
          AIAssistGlobalUtility.getOrgToday()
        ),
        ex.getMessage(),
        'The text is the Custom Label, with the allowance and when it renews.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_MESSAGES,
      code,
      'The plan message limit.'
    );
  }

  @IsTest
  static void testScenario7() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIUsageDaily__c usage = AIAssistTestDataFactory.createAIUsageDailies(
      chatUser.Id,
      agent.Id,
      model.Id,
      1,
      false
    )[0];
    usage.InputTokens__c = 70;
    usage.OutputTokens__c = 30;
    insert usage;
    String code;

    Test.startTest();
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      101
    );
    AIUsageLimitService.enforceUsageLimits(context, false, 100);
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_MAX_MONTHLY_USAGE,
      100
    );
    try {
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
      Assert.fail(
        'The month\'s 100 tokens are used, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        AIUsageLimitService.planLimitMessage(
          Label.AI_Error_Plan_Limit_Tokens,
          100,
          AIAssistGlobalUtility.getOrgToday()
        ),
        ex.getMessage(),
        'The text is the Custom Label, with the allowance and when it renews.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_PLAN_LIMIT_USAGE,
      code,
      'The plan token limit.'
    );
  }

  @IsTest
  static void testScenario8() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIUsageDaily__c usage = AIAssistTestDataFactory.createAIUsageDailies(
      otherUser.Id,
      agent.Id,
      model.Id,
      1,
      false
    )[0];
    usage.InputTokens__c = 400;
    usage.OutputTokens__c = 100;
    insert usage;
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.GlobalTokenBudgetPerDay__c = 501;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    String code;

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, false, 100);
    settings.GlobalTokenBudgetPerDay__c = 500;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    try {
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
      Assert.fail(
        'The 500 token budget is used by another user, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Daily_Usage_Limit,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_DAILY_USAGE_LIMIT,
      code,
      'The daily budget.'
    );
  }

  @IsTest
  static void testScenario9() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    String code;

    Test.startTest();
    AIUsageLimitService.maxPendingJobsForTest = 1000;
    AIUsageLimitService.enforceUsageLimits(context, false, 100);
    AIUsageLimitService.maxPendingJobsForTest = 0;
    try {
      AIUsageLimitService.enforceUsageLimits(context, false, 100);
      Assert.fail(
        'A ceiling of zero is always full, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Service_Busy,
        ex.getMessage(),
        'The text says AI Assist is busy, not that the provider is unavailable.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_SERVICE_BUSY,
      code,
      'Service busy.'
    );
  }

  @IsTest
  static void testScenario10() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      false
    );
    agents[0].IdleTimeoutMinutes__c = 30;
    agents[1].IdleTimeoutMinutes__c = null;
    insert agents;
    List<AIConversation__c> timed = AIAssistTestDataFactory.createAIConversations(
      agents[0].Id,
      chatUser.Id,
      2,
      true
    );
    AIConversation__c untimed = AIAssistTestDataFactory.createAIConversations(
      agents[1].Id,
      chatUser.Id,
      1,
      true
    )[0];
    // One conversation on the timed agent went quiet two hours ago; the one with no timeout went quiet two days ago.
    timed[0].LastMessageTimestamp__c = System.now().addHours(-2);
    timed[1].LastMessageTimestamp__c = System.now().addMinutes(-5);
    untimed.LastMessageTimestamp__c = System.now().addDays(-2);
    update new List<AIConversation__c>{ timed[0], timed[1], untimed };
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      chatUser.Id,
      false
    )[0];
    settings.MaxConcurrentConversations__c = 3;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    insert settings;
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agents[0];
    context.userSettings = settings;
    String refusedCode;

    Test.startTest();
    Integer counted = AIMessagingSelector.countActiveConversations(chatUser.Id);
    try {
      AIUsageLimitService.enforceUsageLimits(context, true, 0);
    } catch (AIMessagingException ex) {
      Assert.fail('Two of three places are taken: ' + ex.code);
    }
    timed[0].LastMessageTimestamp__c = System.now();
    update timed[0];
    try {
      AIUsageLimitService.enforceUsageLimits(context, true, 0);
    } catch (AIMessagingException ex) {
      refusedCode = ex.code;
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      counted,
      'The idle conversation is not counted; the recent one and the one with no timeout are.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
      refusedCode,
      'Once it is active again all three places are taken.'
    );
  }
}
