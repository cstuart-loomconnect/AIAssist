/*
Class Name: AIConversationRetentionBatchTest

=================================================================
=================================================================

Description: Testing utility for AIConversationRetentionBatch: expired conversations are deleted with their children, and anything on legal hold or not yet expired is kept.

=================================================================
=================================================================
Applicable Classes:

AIConversationRetentionBatch

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationRetentionBatchTest {
  // testScenario1: An expired conversation is deleted together with its messages and its feedback.
  // testScenario2: A conversation on legal hold is kept however old it is.
  // testScenario3: The boundary: expiring today is deleted, expiring tomorrow is kept, and no expiry date is kept.
  // testScenario4: Bulk: 200 expired conversations are deleted in one pass.
  // testScenario5: Retention still runs while the application is switched off.

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
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      5,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIFeedback(
      conversation.Id,
      message.Id,
      1,
      true
    );
    conversation.RetentionExpiryDate__c = Datetime.now().dateGmt().addDays(-1);
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationRetentionBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id],
      'The conversation is gone.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversationMessage__c WHERE Id = :message.Id],
      'And so are its messages.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIFeedback__c],
      'And so is its feedback, not left behind with a blank conversation.'
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
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.RetentionExpiryDate__c = Datetime.now()
      .dateGmt()
      .addDays(-400);
    conversation.IsOnLegalHold__c = true;
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationRetentionBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id],
      'Held, so kept.'
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
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      3,
      true
    );
    Date today = Datetime.now().dateGmt();
    conversations[0].RetentionExpiryDate__c = today;
    conversations[1].RetentionExpiryDate__c = today.addDays(1);
    conversations[2].RetentionExpiryDate__c = null;
    update conversations;

    Test.startTest();
    Database.executeBatch(new AIConversationRetentionBatch(), 200);
    Test.stopTest();

    Map<Id, AIConversation__c> remaining = new Map<Id, AIConversation__c>(
      [SELECT Id FROM AIConversation__c WHERE Id IN :conversations]
    );
    Assert.isFalse(
      remaining.containsKey(conversations[0].Id),
      'Due today: deleted.'
    );
    Assert.isTrue(
      remaining.containsKey(conversations[1].Id),
      'Due tomorrow: kept.'
    );
    Assert.isTrue(
      remaining.containsKey(conversations[2].Id),
      'No expiry: kept.'
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
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    for (AIConversation__c conversation : conversations)
      conversation.RetentionExpiryDate__c = Datetime.now()
        .dateGmt()
        .addDays(-1);
    update conversations;

    Test.startTest();
    Database.executeBatch(new AIConversationRetentionBatch(), 200);
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM AIConversation__c], 'All deleted.');
  }

  @IsTest
  static void testScenario5() {
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
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      1,
      true
    )[0];
    conversation.RetentionExpiryDate__c = Datetime.now().dateGmt().addDays(-1);
    update conversation;

    Test.startTest();
    Database.executeBatch(new AIConversationRetentionBatch(), 200);
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversation__c],
      'Deleted although the application is off.'
    );
  }
}
