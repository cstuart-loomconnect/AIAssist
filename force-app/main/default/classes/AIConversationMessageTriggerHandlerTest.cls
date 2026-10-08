/*
Class Name: AIConversationMessageTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIConversationMessageTrigger and AIConversationMessageTriggerHandler: the roll-up onto the conversation is bulk-safe.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageTriggerHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationMessageTriggerHandlerTest {
  // testScenario4: The roll-up adds the tokens to the conversation and moves the last message time to the newest User or AI Agent message.
  // testScenario5: A System message adds its tokens but does not move the last message time.
  // testScenario6: For an agent whose retention counts from the last message, the expiry moves forward with each message.
  // testScenario7: Bulk: 201 messages across several conversations roll up with one update per conversation and a few queries.
  // testScenario8: Switched off, the roll-up does nothing and the message still saves.
  // testScenario9: Calling the handler with nothing does nothing and does not throw.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      100,
      2,
      true
    );
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      50,
      1,
      true
    );
    Test.stopTest();

    AIConversation__c rolledUp = [
      SELECT ConversationTokenUsage__c, LastMessageTimestamp__c, MessageCount__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.areEqual(
      250,
      rolledUp.ConversationTokenUsage__c,
      'Tokens add up across inserts.'
    );
    Assert.isNotNull(
      rolledUp.LastMessageTimestamp__c,
      'The last message time moved.'
    );
    Assert.areEqual(
      3,
      rolledUp.MessageCount__c,
      'The native roll-up counts them.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      40,
      1,
      true
    );
    Test.stopTest();

    AIConversation__c rolledUp = [
      SELECT ConversationTokenUsage__c, LastMessageTimestamp__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.areEqual(
      40,
      rolledUp.ConversationTokenUsage__c,
      'The failed turn\'s tokens still count.'
    );
    Assert.isNull(
      rolledUp.LastMessageTimestamp__c,
      'But it is not a conversation event.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      false
    )[0];
    agent.ConversationRetentionDays__c = 20;
    agent.RetentionTrigger__c = AIAssistApplicationConstants.RETENTION_TRIGGER_LAST_MESSAGE_DATE;
    insert agent;
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    );
    Test.stopTest();

    AIConversation__c rolledUp = [
      SELECT LastMessageTimestamp__c, RetentionExpiryDate__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.areEqual(
      rolledUp.LastMessageTimestamp__c.dateGmt().addDays(20),
      rolledUp.RetentionExpiryDate__c,
      'Twenty days from the message.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      3,
      true
    );
    List<AIConversationMessage__c> messages = new List<AIConversationMessage__c>();
    for (AIConversation__c conversation : conversations)
      messages.addAll(
        AIAssistTestDataFactory.createAIConversationMessages(
          conversation.Id,
          1,
          67,
          false
        )
      );
    Integer queries;

    Test.startTest();
    insert messages;
    queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(201, messages.size(), 'Past the chunk size.');
    Assert.areEqual(
      67,
      [
        SELECT ConversationTokenUsage__c
        FROM AIConversation__c
        WHERE Id = :conversations[0].Id
      ]
      .ConversationTokenUsage__c,
      'Each conversation counted its own messages once.'
    );
    Assert.isTrue(
      queries <= 6,
      'Queries do not grow with the number of messages: ' + queries
    );
  }

  @IsTest
  static void testScenario8() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];

    Test.startTest();
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      100,
      1,
      true
    );
    Test.stopTest();

    AIConversation__c untouched = [
      SELECT ConversationTokenUsage__c, LastMessageTimestamp__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ];
    Assert.isTrue(
      untouched.ConversationTokenUsage__c == null ||
        untouched.ConversationTokenUsage__c == 0,
      'No roll-up.'
    );
    Assert.isNull(untouched.LastMessageTimestamp__c, 'No timestamp.');
  }

  @IsTest
  static void testScenario9() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      10,
      1,
      true
    )[0];

    Test.startTest();
    try {
      AIConversationMessageTriggerHandler.handleAfterInsert(null);
      AIConversationMessageTriggerHandler.handleAfterInsert(
        new List<AIConversationMessage__c>()
      );
    } catch (Exception ex) {
      Assert.fail('The handler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      10,
      [
        SELECT ConversationTokenUsage__c
        FROM AIConversation__c
        WHERE Id = :conversation.Id
      ]
      .ConversationTokenUsage__c,
      'Nothing was passed in, so nothing was counted again.'
    );
  }
}
