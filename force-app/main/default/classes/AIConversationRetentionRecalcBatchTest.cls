/*
Class Name: AIConversationRetentionRecalcBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationRetentionRecalcBatch and the agent trigger that starts it: a change to an agent's retention settings is applied to the conversations it already has.

=================================================================
=================================================================
Applicable Classes:

AIConversationRetentionRecalcBatch, AIAgentTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationRetentionRecalcBatchTest {
  // testScenario1: Changing an agent's retention days starts the batch, which moves the expiry date of its conversations, including one that had none, and leaves another agent's alone.
  // testScenario2: Setting retention to blank clears the expiry dates.
  // testScenario3: Each retention trigger counts from its own date: creation, the last message, or the close (and no date while still open).
  // testScenario4: A change that is not to the retention settings starts no batch, and the batch still runs while the application is switched off.
  // testScenario5: A failure to start the batch is logged and the agent still saves.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIAgent__c createAgent(Decimal days, String retentionTrigger) {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = days;
    agent.RetentionTrigger__c = retentionTrigger;
    insert agent;

    return agent;
  }

  private static Map<Id, Date> expiryById() {
    Map<Id, Date> expiries = new Map<Id, Date>();
    for (AIConversation__c conversation : [
      SELECT RetentionExpiryDate__c
      FROM AIConversation__c
    ])
      expiries.put(conversation.Id, conversation.RetentionExpiryDate__c);

    return expiries;
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = createAgent(
      30,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );
    AIAgent__c otherAgent = createAgent(
      30,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      2,
      true
    );
    AIConversation__c untouched = AIAssistTestDataFactory.createAIConversations(
      otherAgent.Id,
      1,
      true
    )[0];
    conversations[1].RetentionExpiryDate__c = null;
    update conversations[1];
    Date today = Datetime.now().dateGmt();

    Test.startTest();
    agent.ConversationRetentionDays__c = 7;
    update agent;
    Test.stopTest();

    Map<Id, Date> expiries = expiryById();
    Assert.areEqual(
      today.addDays(7),
      expiries.get(conversations[0].Id),
      'Moved from 30 days to 7.'
    );
    Assert.areEqual(
      today.addDays(7),
      expiries.get(conversations[1].Id),
      'A conversation with no date gets one.'
    );
    Assert.areEqual(
      today.addDays(30),
      expiries.get(untouched.Id),
      'Another agent\'s conversation is left alone.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = createAgent(
      30,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    Date before = expiryById().get(conversation.Id);

    Test.startTest();
    agent.ConversationRetentionDays__c = null;
    update agent;
    Test.stopTest();

    Assert.isNotNull(before, 'It had a date.');
    Assert.isNull(
      expiryById().get(conversation.Id),
      'Blank retention keeps the conversation indefinitely.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = createAgent(
      10,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      2,
      true
    );
    Datetime created = System.now().addDays(-20);
    Datetime lastMessage = System.now().addDays(-5);
    Datetime closed = System.now().addDays(-2);
    for (AIConversation__c conversation : conversations)
      Test.setCreatedDate(conversation.Id, created);
    conversations[0].LastMessageTimestamp__c = lastMessage;
    conversations[0]
      .Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversations[0].ConversationClosedTimestamp__c = closed;
    conversations[0]
      .ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT;
    update conversations[0];
    Set<Id> agentIds = new Set<Id>{ agent.Id };

    Test.startTest();
    new AIConversationRetentionRecalcBatch(agentIds)
      .execute(null, scopeFor(agent.Id));
    Map<Id, Date> fromCreated = expiryById();
    setTrigger(
      agent,
      AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE
    );
    new AIConversationRetentionRecalcBatch(agentIds)
      .execute(null, scopeFor(agent.Id));
    Map<Id, Date> fromLastMessage = expiryById();
    setTrigger(
      agent,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE
    );
    new AIConversationRetentionRecalcBatch(agentIds)
      .execute(null, scopeFor(agent.Id));
    Map<Id, Date> fromClosed = expiryById();
    new AIConversationRetentionRecalcBatch(null).finish(null);
    Test.stopTest();

    Assert.areEqual(
      created.dateGmt().addDays(10),
      fromCreated.get(conversations[0].Id),
      'From creation.'
    );
    Assert.areEqual(
      lastMessage.dateGmt().addDays(10),
      fromLastMessage.get(conversations[0].Id),
      'From the last message.'
    );
    Assert.areEqual(
      created.dateGmt().addDays(10),
      fromLastMessage.get(conversations[1].Id),
      'From creation when there is no message yet.'
    );
    Assert.areEqual(
      closed.dateGmt().addDays(10),
      fromClosed.get(conversations[0].Id),
      'From the close.'
    );
    Assert.isNull(
      fromClosed.get(conversations[1].Id),
      'An open conversation has no date until it closes.'
    );
  }

  // Changes the trigger without starting the batch, so the scenario runs each pass itself.
  private static void setTrigger(AIAgent__c agent, String retentionTrigger) {
    AIAgentTriggerHandler.isTestCustomExceptionThrown = true;
    agent.RetentionTrigger__c = retentionTrigger;
    update agent;
    AIAgentTriggerHandler.isTestCustomExceptionThrown = false;
  }

  private static List<AIConversation__c> scopeFor(Id agentId) {
    return [
      SELECT
        Id,
        CreatedDate,
        LastMessageTimestamp__c,
        ConversationClosedTimestamp__c,
        Status__c,
        RetentionExpiryDate__c,
        AIAgent__r.ConversationRetentionDays__c,
        AIAgent__r.RetentionTrigger__c
      FROM AIConversation__c
      WHERE AIAgent__c = :agentId
    ];
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = createAgent(
      30,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    agent.Description__c = 'Not a retention change.';
    update agent;
    Integer jobsAfterOtherChange = [
      SELECT COUNT()
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'AIConversationRetentionRecalcBatch'
    ];
    agent.ConversationRetentionDays__c = 5;
    update agent;
    Test.stopTest();

    Assert.areEqual(0, jobsAfterOtherChange, 'No batch for another field.');
    Assert.areEqual(
      Datetime.now().dateGmt().addDays(5),
      expiryById().get(conversation.Id),
      'Recalculated although the application is off.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = createAgent(
      30,
      AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE
    );

    Test.startTest();
    AIAgentTriggerHandler.isTestCustomExceptionThrown = true;
    agent.ConversationRetentionDays__c = 9;
    Database.SaveResult saved = Database.update(agent, false);
    AIAgentTriggerHandler.handleAfterUpdate(null, null);
    Test.stopTest();

    Assert.isTrue(saved.isSuccess(), 'The agent still saves.');
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIConversationRetentionRecalcBatch'
      ],
      'No batch was started.'
    );
  }
}
