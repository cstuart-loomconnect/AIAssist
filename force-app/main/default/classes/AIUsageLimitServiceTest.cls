/*
Class Name: AIUsageLimitServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsageLimitService: the per-minute rate limit, the user's concurrent conversations, the shared queue ceiling and the cap on messages in flight.

=================================================================
=================================================================
Applicable Classes:

AIUsageLimitService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIUsageLimitServiceTest {
  // testScenario1: With no limits set anywhere a message is allowed, for a new conversation and for an existing one -> nothing is refused.
  // testScenario2: The concurrent conversation limit refuses a new conversation once the user has that many active, and does not refuse a message in an existing one -> only the new conversation is refused with the concurrent limit label.
  // testScenario3: Notify Only never refuses, an inactive settings row never refuses, and Block New Conversations Only lets messages in existing conversations through -> nothing is refused.
  // testScenario4: isInFlightCapReached with no cap, room under the cap and the cap reached -> false, false, true.
  // testScenario5: A full shared queue refuses the message as service busy, and room in the queue allows it -> only the full queue is refused with the service busy label.
  // testScenario6: A conversation idle for longer than its agent's timeout does not count towards the concurrent limit; one inside the timeout, and one on an agent with no timeout, do -> two are counted and the new conversation is only refused once all three places are taken.

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
    // [1] Create a user, an agent and a chat context with no limits
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

    // [2] Enforce the limits for a new and an existing conversation
    Test.startTest();
    AIUsageLimitService.enforceUsageLimits(context, true);
    AIUsageLimitService.enforceUsageLimits(context, false);
    Test.stopTest();

    // [3] Check nothing was refused
    Assert.isNull(
      context.userSettings,
      'The user has no settings row, and no limit is set, so nothing should be refused.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a chat context, a two conversation limit and two active conversations
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
    Assert.areEqual(
      Label.AI_Error_Concurrent_Limit,
      refusalMessage,
      'A third active conversation should be refused with the concurrent limit Custom Label.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create a chat context, a one conversation limit and one active conversation
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
    Assert.isTrue(
      settings.IsActive__c,
      'The last call ran with limits live; an existing conversation should still have been allowed.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Prepare the settings and the results to capture
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    Boolean noCap;
    Boolean belowCap;
    Boolean atCap;

    // [2] Check the in-flight cap with no cap, room under the cap and the cap reached
    Test.startTest();
    settings.MaxMessagesInFlight__c = null;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIUsageLimitService.inFlightForTest = 100;
    noCap = AIUsageLimitService.isInFlightCapReached();

    settings.MaxMessagesInFlight__c = 3;
    update settings;
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

  @IsTest
  static void testScenario5() {
    // [1] Create a chat context
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
    Assert.areEqual(
      Label.AI_Error_Service_Busy,
      refusalMessage,
      'A ceiling of zero is always full, so the message should be refused as service busy, not as the provider being unavailable.'
    );
  }

  @IsTest
  static void testScenario6() {
    // [1] Create a timed agent and an untimed one, with conversations on each
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

    // [2] Make one timed conversation idle and one untimed conversation old
    timed[0].LastMessageTimestamp__c = System.now().addHours(-2);
    timed[1].LastMessageTimestamp__c = System.now().addMinutes(-5);
    untimed.LastMessageTimestamp__c = System.now().addDays(-2);
    update new List<AIConversation__c>{ timed[0], timed[1], untimed };

    // [3] Create a three conversation limit and the chat context
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
    Assert.areEqual(
      2,
      counted,
      'The idle conversation is not counted; the recent one and the one with no timeout are.'
    );
    Assert.isNull(
      firstRefusal,
      'Two of three places are taken, so the new conversation should be allowed.'
    );
    Assert.areEqual(
      Label.AI_Error_Concurrent_Limit,
      secondRefusal,
      'Once the idle conversation is active again all three places are taken.'
    );
  }
}
