/*
Class Name: AIConversationIdleBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationIdleBatch: idle conversations are closed with the right reason, and nothing active, locked or unconfigured is touched.

=================================================================
=================================================================
Applicable Classes:

AIConversationIdleBatch: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationIdleBatchTest {
  // testScenario1: Run the batch on a conversation idle past its agent's timeout -> it is closed with the Idle Timeout reason and a close time.
  // testScenario2: Run the batch on a recent conversation, one with an agent with no timeout and one being processed -> none is closed.
  // testScenario3: Run the batch on a new conversation with no messages -> it is measured from its creation and stays open.
  // testScenario4: Run the batch with one conversation a minute inside the timeout and one a minute past it -> only the one past it is closed.
  // testScenario5: Run the batch on a conversation that is already closed -> its original close reason stands.
  // testScenario6: Run the batch on a full scope of 200 idle conversations -> all are closed in one pass.
  // testScenario7: Run the batch with the application switched off -> nothing is closed.

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
    // [1] Create an agent with a 30 minute timeout and a conversation idle for two hours
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
      null,
      1,
      true
    )[0];
    conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversation;

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Read the conversation back
    AIConversation__c closed = [
      SELECT
        Status__c,
        ConversationCloseReason__c,
        ConversationClosedTimestamp__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];

    // [4] Check it is closed with the idle timeout reason
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
      closed.Status__c,
      'The idle conversation should be closed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT,
      closed.ConversationCloseReason__c,
      'The close reason should be the idle timeout.'
    );
    Assert.isNotNull(
      closed.ConversationClosedTimestamp__c,
      'The close time should be set.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a recent conversation, a locked conversation and one for an agent with no timeout
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
      null,
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

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Count the active conversations
    Integer activeCount = [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
    ];

    // [4] Check none is closed
    Assert.areEqual(
      3,
      activeCount,
      'None should be closed: one is recent, one is mid-reply, one has no timeout.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create an agent with a one day timeout and a new conversation
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
      null,
      1,
      true
    )[0];

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Read the conversation back
    AIConversation__c result = [
      SELECT Status__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];

    // [4] Check it stays open
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      result.Status__c,
      'A conversation created just now should not be idle for a day.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create an agent with a 60 minute timeout and conversations idle for 59 and 61 minutes
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
      null,
      2,
      true
    );
    conversations[0].LastMessageTimestamp__c = System.now().addMinutes(-59);
    conversations[1].LastMessageTimestamp__c = System.now().addMinutes(-61);
    update conversations;

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Read the conversations back
    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [SELECT Status__c FROM AIConversation__c WHERE Id IN :conversations]
    );

    // [4] Check only the one past the timeout is closed
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      byId.get(conversations[0].Id).Status__c,
      'A conversation inside the timeout should stay open.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
      byId.get(conversations[1].Id).Status__c,
      'A conversation past the timeout should be closed.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Create an agent and a conversation the user already closed
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
      null,
      1,
      true
    )[0];
    conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    conversation.ConversationClosedTimestamp__c = System.now().addDays(-1);
    conversation.LastMessageTimestamp__c = System.now().addDays(-2);
    update conversation;

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Read the conversation back
    AIConversation__c result = [
      SELECT ConversationCloseReason__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];

    // [4] Check the original close reason stands
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED,
      result.ConversationCloseReason__c,
      'The original close reason should stand.'
    );
  }

  @IsTest
  static void testScenario6() {
    // [1] Create an agent and 200 idle conversations
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
      null,
      200,
      true
    );
    for (AIConversation__c conversation : conversations)
      conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversations;

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Count the closed conversations
    Integer closedCount = [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE
        Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED
        AND ConversationCloseReason__c = :AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_IDLE_TIMEOUT
    ];

    // [4] Check all 200 are closed
    Assert.areEqual(
      200,
      closedCount,
      'All 200 idle conversations should be closed.'
    );
  }

  @IsTest
  static void testScenario7() {
    // [1] Switch the application off, then create an agent and an idle conversation
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
      null,
      1,
      true
    )[0];
    conversation.LastMessageTimestamp__c = System.now().addMinutes(-120);
    update conversation;

    // [2] Run the idle batch
    Test.startTest();
    Database.executeBatch(new AIConversationIdleBatch(), 200);
    Test.stopTest();

    // [3] Read the conversation back
    AIConversation__c result = [
      SELECT Status__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];

    // [4] Check the conversation is left alone
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      result.Status__c,
      'The conversation should be left alone while the application is off.'
    );
  }
}
