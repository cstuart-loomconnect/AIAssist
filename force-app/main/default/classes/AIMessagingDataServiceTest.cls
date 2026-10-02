/*
Class Name: AIMessagingDataServiceTest

=================================================================
=================================================================

Description: Testing utility for AIMessagingDataService: the package's system-mode writes, the marker that tells the message trigger a write is the package's own, and the daily usage row.

=================================================================
=================================================================
Applicable Classes:

AIMessagingDataService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessagingDataServiceTest {
  // testScenario1: insertRecords and updateRecords write as the package, and the package marker is clear afterwards.
  // testScenario2: A write that fails throws the generic label with the real reason in detail, for an insert and for an update, and still clears the package marker.
  // testScenario3: insertQuietly and updateQuietly never throw: a failure is logged and the rest of the batch is still written.
  // testScenario4: A message from the AI Agent is accepted when the package writes it and refused when a user writes it, because the trigger reads the package marker.
  // testScenario5: addUsage creates the user's row for the day on first use, adds to it afterwards, keeps a separate row for another agent, and ignores a missing user.

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
    List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      7,
      2,
      false
    );

    Test.startTest();
    AIMessagingDataService.insertAsPackage(messages);
    messages[0]
      .ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED;
    AIMessagingDataService.updateAsPackage(new List<SObject>{ messages[0] });
    AIMessagingDataService.insertAsPackage(null);
    AIMessagingDataService.updateAsPackage(new List<SObject>());
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ],
      'The AI Agent messages were written, which only the package may do.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :messages[0].Id
      ]
      .ProcessingStatus__c,
      'The update was written.'
    );
    Assert.isFalse(
      AIMessagingDataService.isPackageWriting(),
      'The marker is clear once the write is done.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIConversationMessage__c orphan = AIAssistTestDataFactory.createAIConversationMessages(
      null,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      1,
      1,
      false
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, true)[0];
    agent.ConversationRetentionDays__c = -1;
    List<String> details = new List<String>();

    Test.startTest();
    try {
      AIMessagingDataService.insertAsPackage(new List<SObject>{ orphan });
      Assert.fail('An insert with no parent conversation should have thrown.');
    } catch (AIMessagingException ex) {
      Assert.areEqual(
        Label.AI_Error_Generic,
        ex.getMessage(),
        'The user sees only the generic label.'
      );
      details.add(ex.detail);
    }

    try {
      AIMessagingDataService.updateAsPackage(new List<SObject>{ agent });
      Assert.fail('An update the object model refuses should have thrown.');
    } catch (AIMessagingException ex) {
      details.add(ex.detail);
    }
    Test.stopTest();

    Assert.isTrue(
      details[0].startsWith('Failed to insert record'),
      'The detail for the log says what failed.'
    );
    Assert.isTrue(
      details[1].startsWith('Failed to update record'),
      'And so does the update\'s.'
    );
    Assert.isFalse(
      AIMessagingDataService.isPackageWriting(),
      'A failed write must not leave the marker set, or a user insert later in the transaction could forge a sender.'
    );
  }

  @IsTest
  static void testScenario3() {
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
    List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      3,
      2,
      false
    );
    AIConversationMessage__c orphan = AIAssistTestDataFactory.createAIConversationMessages(
      null,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      3,
      1,
      false
    )[0];
    messages.add(orphan);

    Test.startTest();
    try {
      AIMessagingDataService.insertAndLogFailures(
        messages,
        'AIMessagingDataServiceTest',
        'testScenario3'
      );
      AIMessagingDataService.updateAndLogFailures(
        new List<SObject>{ new AIConversationMessage__c(Id = messages[0].Id) },
        'AIMessagingDataServiceTest',
        'testScenario3'
      );
      AIMessagingDataService.insertAndLogFailures(
        null,
        'AIMessagingDataServiceTest',
        'testScenario3'
      );
    } catch (Exception ex) {
      Assert.fail('Quiet writes must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE AIConversation__c = :conversation.Id
      ],
      'The records that could be saved were saved.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIMessagingDataServiceTest'
      ],
      'The one that could not was logged.'
    );
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistAdminUser'
    );
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c packageMessage = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      null,
      1,
      false
    )[0];
    AIConversationMessage__c forgedMessage = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      null,
      1,
      false
    )[0];
    Database.SaveResult forgedResult;

    System.runAs(chatUser) {
      Test.startTest();
      AIMessagingDataService.insertAsPackage(
        new List<SObject>{ packageMessage }
      );
      forgedResult = Database.insert(forgedMessage, false);
      Test.stopTest();
    }

    Assert.isNotNull(
      packageMessage.Id,
      'The package may write as the AI Agent.'
    );
    Assert.isFalse(forgedResult.isSuccess(), 'A user may not.');
    Assert.areEqual(
      Label.AI_Error_Not_Authorised,
      forgedResult.getErrors()[0].getMessage(),
      'The refusal is a Custom Label.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      true
    );

    AIMessagingDataService.UsageDelta aiResponseUsage = new AIMessagingDataService.UsageDelta();
    aiResponseUsage.userId = chatUser.Id;
    aiResponseUsage.agentId = agents[0].Id;
    aiResponseUsage.modelConfigurationId = model.Id;
    aiResponseUsage.messages = 1;
    aiResponseUsage.inputTokens = 100;
    aiResponseUsage.outputTokens = 20;

    AIMessagingDataService.UsageDelta conversationStart = new AIMessagingDataService.UsageDelta();
    conversationStart.userId = chatUser.Id;
    conversationStart.agentId = agents[0].Id;
    conversationStart.modelConfigurationId = model.Id;
    conversationStart.conversations = 1;
    conversationStart.failedTurns = 1;

    AIMessagingDataService.UsageDelta otherAgentTurn = new AIMessagingDataService.UsageDelta();
    otherAgentTurn.userId = chatUser.Id;
    otherAgentTurn.agentId = agents[1].Id;
    otherAgentTurn.modelConfigurationId = model.Id;
    otherAgentTurn.messages = 1;

    Test.startTest();
    AIMessagingDataService.addToDailyUsage(aiResponseUsage);
    AIMessagingDataService.addToDailyUsage(aiResponseUsage);
    AIMessagingDataService.addToDailyUsage(conversationStart);
    AIMessagingDataService.addToDailyUsage(otherAgentTurn);
    AIMessagingDataService.addToDailyUsage(null);
    AIMessagingDataService.addToDailyUsage(
      new AIMessagingDataService.UsageDelta()
    );
    Test.stopTest();

    List<AIUsageDaily__c> rows = [
      SELECT
        AIAgent__c,
        MessageCount__c,
        ConversationCount__c,
        FailedTurnCount__c,
        InputTokens__c,
        OutputTokens__c,
        UsageDate__c,
        UsageKey__c
      FROM AIUsageDaily__c
      WHERE User__c = :chatUser.Id
      ORDER BY MessageCount__c DESC
    ];

    Assert.areEqual(
      2,
      rows.size(),
      'One row per user, agent, model and day: the unique key guarantees it.'
    );
    Assert.areEqual(2, rows[0].MessageCount__c, 'The two turns are added.');
    Assert.areEqual(
      1,
      rows[0].ConversationCount__c,
      'The conversation is added.'
    );
    Assert.areEqual(1, rows[0].FailedTurnCount__c, 'The failed turn is added.');
    Assert.areEqual(200, rows[0].InputTokens__c, 'Input tokens are added.');
    Assert.areEqual(40, rows[0].OutputTokens__c, 'Output tokens are added.');
    Assert.areEqual(
      Datetime.now().dateGmt(),
      rows[0].UsageDate__c,
      'The day is the UTC day.'
    );
    Assert.isTrue(
      rows[0].UsageKey__c.endsWith(Datetime.now().formatGmt('yyyyMMdd')) &&
      rows[0].UsageKey__c.length() <= 80,
      'The key ends with the day and fits its field.'
    );
  }
}
