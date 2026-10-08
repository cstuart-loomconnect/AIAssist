/*
Class Name: AIUsageLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageLimitService: the per-minute rate limit, the user's concurrent conversations, the shared queue ceiling and the cap on messages in flight.

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
  // testScenario5: Notify Only never refuses, an inactive settings row never refuses, and Block New Conversations Only lets messages in existing conversations through.
  // testScenario6: The per-minute rate limit refuses a user who has already sent that many messages in the last minute.
  // testScenario7: isInFlightCapReached is false with no cap or room under it, and true once the messages in flight reach the cap.
  // testScenario8: A full shared queue refuses the message as service busy, and room in the queue allows it.
  // testScenario9: A conversation idle for longer than its agent's timeout does not count towards the concurrent limit; one inside the timeout, and one on an agent with no timeout, do.

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
      AIUsageLimitService.enforceUsageLimits(context, true);
      AIUsageLimitService.enforceUsageLimits(context, false);
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
    AIUsageLimitService.enforceUsageLimits(context, false);
    try {
      AIUsageLimitService.enforceUsageLimits(context, true);
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
    AIUsageLimitService.enforceUsageLimits(context, true);

    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    settings.IsActive__c = false;
    AIUsageLimitService.enforceUsageLimits(context, true);

    settings.IsActive__c = true;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY;
    AIUsageLimitService.enforceUsageLimits(context, false);
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
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIMessageValidator.ChatContext context = new AIMessageValidator.ChatContext();
    context.userId = chatUser.Id;
    context.agent = agent;

    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    System.runAs(chatUser) {
      AIAssistTestDataFactory.createAIConversationMessages(
        conversation.Id,
        0,
        2,
        true
      );
    }
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.MaxMessagesPerUserPerMinute__c = 3;
    update settings;
    AIAssistSettingsService.clearCache();
    String code;

    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, false);
    settings.MaxMessagesPerUserPerMinute__c = 2;
    update settings;
    AIAssistSettingsService.clearCache();
    try {
      AIUsageLimitService.enforceUsageLimits(context, false);
      Assert.fail(
        'Two messages in the last minute reach a limit of two, so this should have been refused.'
      );
    } catch (AIMessagingException ex) {
      code = ex.code;
      Assert.areEqual(
        Label.AI_Error_Rate_Limited,
        ex.getMessage(),
        'The text is the Custom Label.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_RATE_LIMITED,
      code,
      'The rate limit.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    Boolean noCap;
    Boolean belowCap;
    Boolean atCap;

    Test.startTest();
    settings.MaxMessagesInFlight__c = null;
    update settings;
    AIAssistSettingsService.clearCache();
    AIUsageLimitService.inFlightForTest = 100;
    noCap = AIUsageLimitService.isInFlightCapReached();

    settings.MaxMessagesInFlight__c = 3;
    update settings;
    AIAssistSettingsService.clearCache();
    AIUsageLimitService.inFlightForTest = 2;
    belowCap = AIUsageLimitService.isInFlightCapReached();
    AIUsageLimitService.inFlightForTest = 3;
    atCap = AIUsageLimitService.isInFlightCapReached();
    Test.stopTest();

    Assert.isFalse(noCap, 'With no cap set nothing is held back.');
    Assert.isFalse(belowCap, 'A place is still free.');
    Assert.isTrue(atCap, 'The cap is reached.');
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

    String code;

    Test.startTest();
    AIUsageLimitService.maxPendingJobsForTest = 1000;
    AIUsageLimitService.enforceUsageLimits(context, false);
    AIUsageLimitService.maxPendingJobsForTest = 0;
    try {
      AIUsageLimitService.enforceUsageLimits(context, false);
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
  static void testScenario9() {
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
      AIUsageLimitService.enforceUsageLimits(context, true);
    } catch (AIMessagingException ex) {
      Assert.fail('Two of three places are taken: ' + ex.code);
    }
    timed[0].LastMessageTimestamp__c = System.now();
    update timed[0];
    try {
      AIUsageLimitService.enforceUsageLimits(context, true);
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
