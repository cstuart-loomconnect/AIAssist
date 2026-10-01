/*
Class Name: AIConversationIdleBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationIdleBatch: idle conversations are closed with the right reason, and nothing active, locked or unconfigured is touched.

=================================================================
=================================================================
Applicable Classes:

AIConversationIdleBatch

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationIdleBatchTest {
  // testScenario1: A conversation idle for longer than its agent's timeout is closed with the Idle Timeout reason and a close time.
  // testScenario2: A conversation with recent activity, one whose agent has no timeout, and one being processed are left open.
  // testScenario3: A conversation with no messages is measured from its creation.
  // testScenario4: The boundary: one minute inside the timeout stays open and one minute past it closes.
  // testScenario5: A conversation that is already closed is not touched again.
  // testScenario6: Bulk: a full scope of 200 idle conversations is closed in one pass.
  // testScenario7: Switched off, the batch closes nothing.

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
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 30;
    update agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    AIConversation__c closed = [
      SELECT
        Status__c,
        ConversationCloseReason__c,
        ConversationClosedTimestamp__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
      closed.Status__c,
      'Closed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT,
      closed.ConversationCloseReason__c,
      'For being idle.'
    );
    Assert.isNotNull(
      closed.ConversationClosedTimestamp__c,
      'With a close time.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIAgent__c noTimeoutAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    noTimeoutAgent.IdleTimeoutMinutes__c = null;
    agent.IdleTimeoutMinutes__c = 30;
    update new List<AIAgent__c>{ agent, noTimeoutAgent };
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      3,
      false
    );
    conversations[2].AIAgent__c = noTimeoutAgent.Id;
    insert conversations;
    conversations[0].LastMessageTimestamp__c = System.now().addMinutes(-10);
    conversations[1].LastMessageTimestamp__c = System.now().addMinutes(-120);
    conversations[1].ProcessingLockedUntil__c = System.now().addMinutes(5);
    conversations[2].LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversations;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      3,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE
          Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
      ],
      'None was closed: one is recent, one is mid-reply, one has no timeout.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 1440;
    update agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id]
      .Status__c,
      'Created just now, so not idle for a day.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 60;
    update agent;
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      2,
      true
    );
    conversations[0].LastMessageTimestamp__c = System.now().addMinutes(-59);
    conversations[1].LastMessageTimestamp__c = System.now().addMinutes(-61);
    update conversations;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [SELECT Status__c FROM AIConversation__c WHERE Id IN :conversations]
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      byId.get(conversations[0].Id).Status__c,
      'Inside the timeout.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
      byId.get(conversations[1].Id).Status__c,
      'Past it.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 30;
    update agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    conversation.ConversationClosedTimestamp__c = System.now().addDays(-1);
    conversation.LastMessageTimestamp__c = System.now().addDays(-2);
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED,
      [
        SELECT ConversationCloseReason__c
        FROM AIConversation__c
        WHERE Id = :conversation.Id
      ]
      .ConversationCloseReason__c,
      'The original reason stands.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 30;
    update agent;
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    for (AIConversation__c conversation : conversations)
      conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversations;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      200,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE
          Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED
          AND ConversationCloseReason__c = :AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT
      ],
      'All closed.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    agent.IdleTimeoutMinutes__c = 30;
    update agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id]
      .Status__c,
      'Left alone.'
    );
  }
}
