/*
Class Name: AIThroughputLimitsTest

=================================================================
=================================================================

Description: Testing utility for the org-wide throughput controls on AIAssistSettings__c: the cap on messages in flight (extra messages wait and are started when a place is free), the daily message budget, the per-user messages-per-minute limit and the maximum message length.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageService, AIUsageLimitService, AIMessageValidator

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIThroughputLimitsTest {
  // testScenario1: At the cap on messages in flight a new message is kept Queued and waiting, with no job and no lock; under the cap it is started.
  // testScenario2: A waiting message is started by its sender once a place is free, and not while the cap is still reached or by another user.
  // testScenario3: A user at the messages-per-minute limit is refused, and another user is not.
  // testScenario4: A message longer than the configured maximum is refused, and one at the maximum is accepted.
  // testScenario5: The daily message budget refuses once the day's messages reach it.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private class AnsweringExecutor implements AIMessageProcessingQueueable.IAIResponseExecutor {
    public AIAgentManager.AgentResult execute(
      AIMessageProcessingQueueable.AIResponseRequest responseRequest
    ) {
      AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
      result.isSuccessful = true;
      result.replyText = 'Answer';
      result.totalTokensUsed = 2;
      return result;
    }
  }

  private class World {
    List<User> users;
    AIAgent__c agent;
  }

  private static World createWorld() {
    World world = new World();
    world.users = AIAssistTestDataFactory.createUsers(2, true);
    AIAssistTestDataFactory.assignPermissionSet(
      world.users,
      AIAssistApplicationConstants.PERMISSION_SET_USER
    );
    world.agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();

    return world;
  }

  private static void configure(String fieldName, Object value) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.put(fieldName, value);
    update settings;
    AIAssistSettingsService.clearCache();
  }

  private static AIConversationMessage__c send(World world, String body) {
    return AIConversationMessageService.sendMessage(
      world.agent.Id,
      body,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
      null,
      null
    );
  }

  private static String refusalCode(World world, String body) {
    try {
      send(world, body);
    } catch (AIMessagingException refusal) {
      return refusal.code;
    }
    return null;
  }

  @IsTest
  static void testScenario1() {
    World world = createWorld();
    configure('MaxMessagesInFlight__c', 1);
    AIConversationMessage__c started;
    AIConversationMessage__c held;
    Integer jobs;

    System.runAs(world.users[0]) {
      Test.startTest();
      started = send(world, 'First');
      held = send(world, 'Second, in another conversation');
      jobs = AIMessagingSelector.countQueuedMessageJobs();
      started = [
        SELECT IsAwaitingCapacity__c, AIConversation__r.ProcessingLockedUntil__c
        FROM AIConversationMessage__c
        WHERE Id = :started.Id
        WITH SYSTEM_MODE
      ];
      held = [
        SELECT
          IsAwaitingCapacity__c,
          ProcessingStatus__c,
          AIConversation__r.ProcessingLockedUntil__c
        FROM AIConversationMessage__c
        WHERE Id = :held.Id
        WITH SYSTEM_MODE
      ];
      Test.stopTest();
    }

    Assert.areEqual(1, jobs, 'Only the first message has a job.');
    Assert.isFalse(started.IsAwaitingCapacity__c, 'The first was started.');
    Assert.isNotNull(
      started.AIConversation__r.ProcessingLockedUntil__c,
      'And holds its conversation.'
    );
    Assert.isTrue(held.IsAwaitingCapacity__c, 'The second waits for a place.');
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
      held.ProcessingStatus__c,
      'It is Queued, not refused.'
    );
    Assert.isNull(
      held.AIConversation__r.ProcessingLockedUntil__c,
      'Nothing is working on it, so its conversation is not locked.'
    );
  }

  @IsTest
  static void testScenario2() {
    World world = createWorld();
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      world.agent.Id,
      world.users[0].Id,
      1,
      true
    )[0];
    AIConversationMessage__c waiting;
    System.runAs(world.users[0]) {
      waiting = AIAssistTestDataFactory.createAIConversationMessages(
        conversation.Id,
        0,
        1,
        false
      )[0];
      waiting.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
      waiting.IsAwaitingCapacity__c = true;
      AIMessagingDataService.insertAsPackage(new List<SObject>{ waiting });
    }
    Boolean startedByAnother;
    Boolean startedAtTheCap;
    Boolean startedWithRoom;
    Boolean startedTwice;

    Test.startTest();
    configure('MaxMessagesInFlight__c', 5);
    System.runAs(world.users[1]) {
      startedByAnother = AIConversationMessageService.startHeldMessage();
    }
    System.runAs(world.users[0]) {
      AIUsageLimitService.inFlightForTest = 5;
      startedAtTheCap = AIConversationMessageService.startHeldMessage();
      AIUsageLimitService.inFlightForTest = null;
      startedWithRoom = AIConversationMessageService.startHeldMessage();
      startedTwice = AIConversationMessageService.startHeldMessage();
    }
    waiting = [
      SELECT IsAwaitingCapacity__c, AIConversation__r.ProcessingLockedUntil__c
      FROM AIConversationMessage__c
      WHERE Id = :waiting.Id
    ];
    Integer jobs = AIMessagingSelector.countQueuedMessageJobs();
    Test.stopTest();

    Assert.isFalse(startedByAnother, 'Only its sender can start it.');
    Assert.isFalse(startedAtTheCap, 'Not while the cap is still reached.');
    Assert.isTrue(startedWithRoom, 'Started once a place is free.');
    Assert.isFalse(startedTwice, 'And only once.');
    Assert.isFalse(waiting.IsAwaitingCapacity__c, 'No longer waiting.');
    Assert.isNotNull(
      waiting.AIConversation__r.ProcessingLockedUntil__c,
      'Its conversation is locked for the turn.'
    );
    Assert.areEqual(1, jobs, 'One job was queued for it.');
  }

  @IsTest
  static void testScenario3() {
    World world = createWorld();
    configure('MaxMessagesPerUserPerMinute__c', 2);
    String third;
    String othersFirst;

    Test.startTest();
    System.runAs(world.users[0]) {
      send(world, 'One');
      send(world, 'Two');
      third = refusalCode(world, 'Three');
    }
    System.runAs(world.users[1]) {
      othersFirst = refusalCode(world, 'One');
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_RATE_LIMITED,
      third,
      'The third message inside a minute is refused.'
    );
    Assert.isNull(othersFirst, 'The limit is per user.');
  }

  @IsTest
  static void testScenario4() {
    World world = createWorld();
    configure('MaxMessageLength__c', 20);
    String tooLong;
    String atTheMaximum;

    Test.startTest();
    System.runAs(world.users[0]) {
      tooLong = refusalCode(world, 'x'.repeat(21));
      atTheMaximum = refusalCode(world, 'x'.repeat(20));
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_TOO_LONG,
      tooLong,
      'One character over the configured maximum.'
    );
    Assert.isNull(atTheMaximum, 'At the maximum is accepted.');
  }

  @IsTest
  static void testScenario5() {
    World world = createWorld();
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.DailyMessageBudget__c = 100;
    settings.OrgUsageStateJson__c =
      '{"day":"' +
      String.valueOf(AIAssistGlobalUtility.getOrgToday()) +
      '","dayMessages":99,"dayTokens":0,"monthMessages":99,"monthTokens":0}';
    update settings;
    AIAssistSettingsService.clearCache();
    String underBudget;
    String atBudget;

    Test.startTest();
    System.runAs(world.users[0]) {
      underBudget = refusalCode(world, 'The hundredth');
    }
    settings.OrgUsageStateJson__c = settings.OrgUsageStateJson__c.replace(
      '"dayMessages":99',
      '"dayMessages":100'
    );
    update settings;
    AIAssistSettingsService.clearCache();
    System.runAs(world.users[0]) {
      atBudget = refusalCode(world, 'One too many');
    }
    Test.stopTest();

    Assert.isNull(underBudget, 'Ninety-nine of a hundred used.');
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_DAILY_MESSAGE_BUDGET,
      atBudget,
      'The budget for the day is used up.'
    );
  }
}
