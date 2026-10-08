/*
Class Name: AIConversationTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIConversationTrigger and AIConversationTriggerHandler: retention expiry and the close timestamp, bulk-safe and quiet when the application is switched off.

=================================================================
=================================================================
Applicable Classes:

AIConversationTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationTriggerHandlerTest {
  // testScenario2: Retention counted from creation or from the last message sets the expiry date at insert, and one counted from closing does not.
  // testScenario3: Closing a conversation stamps the close time and starts a retention that counts from closing, once.
  // testScenario4: A later update of a closed conversation leaves its close time and expiry alone.
  // testScenario5: Bulk: 201 conversations, across the 200-record chunk boundary, all get an expiry, within a few queries.
  // testScenario6: Switched off, the trigger does nothing: no expiry, and the conversation still saves.
  // testScenario7: Calling the handler with nothing, or with no old values, does nothing and does not throw.
  // testScenario8: An unexpected failure inside the handler is logged and never stops the save.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario2() {
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      4,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    );
    agents[0].ConversationRetentionDays__c = 30;
    agents[0]
      .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
    agents[1].ConversationRetentionDays__c = 30;
    agents[1]
      .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
    agents[2].ConversationRetentionDays__c = 30;
    agents[2]
      .RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
    insert agents;
    List<AIConversation__c> conversations = new List<AIConversation__c>();
    for (AIAgent__c agent : agents)
      conversations.addAll(
        AIAssistTestDataFactory.createAIConversations(agent.Id, 1, false)
      );

    Test.startTest();
    insert conversations;
    Test.stopTest();

    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [
        SELECT AIAgent__c, RetentionExpiryDate__c
        FROM AIConversation__c
        WHERE Id IN :conversations
      ]
    );
    Date expected = Datetime.now().dateGmt().addDays(30);
    Assert.areEqual(
      expected,
      byId.get(conversations[0].Id).RetentionExpiryDate__c,
      'From creation.'
    );
    Assert.areEqual(
      expected,
      byId.get(conversations[1].Id).RetentionExpiryDate__c,
      'Last-message retention starts from creation until a message arrives.'
    );
    Assert.isNull(
      byId.get(conversations[2].Id).RetentionExpiryDate__c,
      'From closing: no expiry until it closes.'
    );
    Assert.isNull(
      byId.get(conversations[3].Id).RetentionExpiryDate__c,
      'No retention days means keep indefinitely.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 10;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
    insert agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    update conversation;
    Test.stopTest();

    AIConversation__c closed = [
      SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.isNotNull(
      closed.ConversationClosedTimestamp__c,
      'The time it closed.'
    );
    Assert.areEqual(
      closed.ConversationClosedTimestamp__c.dateGmt().addDays(10),
      closed.RetentionExpiryDate__c,
      'The expiry counts from closing.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 10;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CLOSED_DATE;
    insert agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversation.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    update conversation;
    AIConversation__c before = [
      SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];

    Test.startTest();
    conversation.Channel__c = AIAssistApplicationConstants.CHANNEL_MOBILE;
    update conversation;
    Test.stopTest();

    AIConversation__c after = [
      SELECT ConversationClosedTimestamp__c, RetentionExpiryDate__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.areEqual(
      before.ConversationClosedTimestamp__c,
      after.ConversationClosedTimestamp__c,
      'Unchanged.'
    );
    Assert.areEqual(
      before.RetentionExpiryDate__c,
      after.RetentionExpiryDate__c,
      'Unchanged.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 5;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
    insert agent;
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      201,
      false
    );
    Integer queries;

    Test.startTest();
    insert conversations;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(
      201,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE RetentionExpiryDate__c != NULL
      ],
      'Every conversation was stamped, in both chunks.'
    );
    Assert.isTrue(
      queries <= 5,
      'Queries do not grow with the number of records: ' + queries
    );
  }

  @IsTest
  static void testScenario6() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 5;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_CONVERSATION_CREATED_DATE;
    insert agent;
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      3,
      false
    );

    Test.startTest();
    insert conversations;
    Test.stopTest();

    Assert.areEqual(
      3,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE RetentionExpiryDate__c = NULL
      ],
      'Nothing was added while switched off.'
    );
  }

  @IsTest
  static void testScenario7() {
    Test.startTest();
    try {
      AIConversationTriggerHandler.handleBeforeInsert(null);
      AIConversationTriggerHandler.handleBeforeInsert(
        new List<AIConversation__c>()
      );
      AIConversationTriggerHandler.handleBeforeUpdate(null, null);
      AIConversationTriggerHandler.handleBeforeUpdate(
        new Map<Id, AIConversation__c>(),
        null
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Nothing to do is not a fault.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIConversationTriggerHandler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      AIConversationTriggerHandler.handleBeforeInsert(
        new List<AIConversation__c>{ new AIConversation__c() }
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIConversationTriggerHandler'
      ],
      'Logged once.'
    );
  }
}
