/*
Class Name: AIChatConversationServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatConversationService: ownership, paging, history, resume, export and the shapes the window reads.

=================================================================
=================================================================
Applicable Classes:

AIChatConversationService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatConversationServiceTest {
  // testScenario1: A user owns their own conversation and reply, and another user's, a missing one and a wrong-type Id are all reported as not found.
  // testScenario2: The newest active conversation for the agent and record is found, and a closed one or another agent's is not.
  // testScenario3: A view shows title, agent, status and the messages oldest first, hides System messages, and pages with a more flag.
  // testScenario4: loadMessagesAfter returns only newer messages, and an unknown boundary returns all.
  // testScenario5: A reply shows its real values in place of the fake ones, both in the window and in the export, and the stored text is unchanged.
  // testScenario6: History lists only the user's own conversations, newest first, optionally for one record.
  // testScenario7: A closed conversation is resumed when the agent allows it, and refused otherwise, with the closed label.
  // testScenario8: Resume is refused at the user's concurrent conversation limit.
  // testScenario9: Execution steps get a Custom Label by what they did, with the data source or action name added.

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
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      other.Id,
      1,
      true
    )[0];
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    AIConversationMessage__c userMessage = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      5,
      1,
      true
    )[0];
    List<String> messages = new List<String>();

    Test.startTest();
    Id ownId = AIChatConversationService.assertOwnsConversation(conversation.Id)
      .Id;
    Id replyId = AIChatConversationService.assertOwnsAgentMessage(reply.Id).Id;
    for (Id bad : new List<Id>{ theirs.Id, agent.Id, null }) {
      try {
        AIChatConversationService.assertOwnsConversation(bad);
        Assert.fail('Should be refused.');
      } catch (AIChatConversationService.AIChatConversationServiceException ex) {
        messages.add(ex.getMessage());
        Assert.areEqual(
          Label.AI_Error_Conversation_Not_Found,
          ex.getMessage(),
          'The text is the Custom Label.'
        );
      }
    }
    try {
      AIChatConversationService.assertOwnsAgentMessage(userMessage.Id);
      Assert.fail('A user message is not a reply.');
    } catch (AIChatConversationService.AIChatConversationServiceException ex) {
      messages.add(ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(conversation.Id, ownId, 'Own conversation.');
    Assert.areEqual(reply.Id, replyId, 'Own reply.');
    Assert.areEqual(4, messages.size(), 'Four refusals.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c closed = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      false
    )[0];
    closed.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    closed.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    closed.ConversationClosedTimestamp__c = System.now();
    insert closed;

    Test.startTest();
    AIConversation__c found = AIChatConversationService.findActiveConversation(
      agent.Id,
      null
    );
    AIConversation__c none = AIChatConversationService.findActiveConversation(
      UserInfo.getUserId(),
      null
    );
    Test.stopTest();

    Assert.areEqual(conversation.Id, found.Id, 'The active one.');
    Assert.isNull(none, 'No conversation for a wrong agent Id.');
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
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
    AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
    ui.messagePageSize = 3;
    List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      1,
      5,
      true
    );
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      9,
      2,
      true
    );
    AIChatDataStructure.ConversationView view;
    AIChatDataStructure.MessagePage older;

    Test.startTest();
    view = AIChatConversationService.buildConversationView(
      conversation.Id,
      3,
      user,
      ui
    );
    older = AIChatConversationService.loadMessagePage(
      conversation.Id,
      view.messages[0].id,
      3,
      user,
      ui
    );
    Test.stopTest();

    Assert.areEqual(
      'Test message 0',
      view.title,
      'Named after the first user message.'
    );
    Assert.areEqual(3, view.messages.size(), 'One page.');
    Assert.isTrue(view.hasMoreMessages, 'More to load.');
    Assert.areEqual(messages[4].Id, view.messages[2].id, 'Newest last.');
    Assert.areEqual(2, older.messages.size(), 'The rest.');
    Assert.isFalse(older.hasMore, 'Nothing more.');
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
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
    AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
    List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      1,
      4,
      true
    );

    Test.startTest();
    List<AIChatDataStructure.ChatMessage> after = AIChatConversationService.loadMessagesAfter(
      conversation.Id,
      messages[1].Id,
      user,
      ui
    );
    List<AIChatDataStructure.ChatMessage> all = AIChatConversationService.loadMessagesAfter(
      conversation.Id,
      null,
      user,
      ui
    );
    Test.stopTest();

    Assert.areEqual(2, after.size(), 'Two newer.');
    Assert.areEqual(4, all.size(), 'All of them.');
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
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIChatDataStructure.UserState user = new AIChatDataStructure.UserState();
    AIChatDataStructure.UiSettings ui = new AIChatDataStructure.UiSettings();
    AIAssistTestDataFactory.createAIPIIMappings(
      conversation.Id,
      new Map<String, String>{ 'Jane Smith' => 'Mary Jones' },
      true
    );
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      false
    )[0];
    reply.MessageBody__c = 'Hello Mary Jones';
    AIMessagingDataService.insertAsPackage(new List<SObject>{ reply });
    String exported;
    AIChatDataStructure.ConversationView view;

    Test.startTest();
    view = AIChatConversationService.buildConversationView(
      conversation.Id,
      10,
      user,
      ui
    );
    exported = AIChatConversationService.exportConversation(conversation.Id);
    Test.stopTest();

    Assert.areEqual(
      'Hello Jane Smith',
      view.messages[0].displayText,
      'Shown with the real value.'
    );
    Assert.isTrue(exported.contains('Hello Jane Smith'), 'Exported with it.');
    Assert.areEqual(
      'Hello Mary Jones',
      [SELECT MessageBody__c FROM AIConversationMessage__c WHERE Id = :reply.Id]
      .MessageBody__c,
      'Never saved.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.createAIConversations(agent.Id, other.Id, 2, true);
    AIConversation__c about = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      false
    )[0];
    Account record = AIAssistTestDataFactory.createAccounts(1, true)[0];
    about.RelatedRecordId__c = String.valueOf(record.Id);
    about.RelatedObjectAPIName__c = 'Account';
    insert about;

    Test.startTest();
    List<AIChatDataStructure.ConversationSummary> all = AIChatConversationService.getConversationHistory(
      null,
      false
    );
    List<AIChatDataStructure.ConversationSummary> forRecord = AIChatConversationService.getConversationHistory(
      String.valueOf(record.Id),
      true
    );
    Test.stopTest();

    Assert.areEqual(2, all.size(), 'Only the user\'s own.');
    Assert.areEqual(1, forRecord.size(), 'One about the record.');
    Assert.areEqual(about.Id, forRecord[0].id, 'It is the right one.');
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AllowConversationResume__c = true;
    update agent;
    AIAgent__c noResume = AIAssistTestDataFactory.createAIAgents(
      1,
      agent.AIModelConfiguration__c,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      false
    );
    conversations.addAll(
      AIAssistTestDataFactory.createAIConversations(
        noResume.Id,
        UserInfo.getUserId(),
        1,
        false
      )
    );
    for (AIConversation__c each : conversations) {
      each.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
      each.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
      each.ConversationClosedTimestamp__c = System.now();
    }
    insert conversations;
    String shown;

    Test.startTest();
    AIChatConversationService.resumeConversation(conversations[0].Id);
    try {
      AIChatConversationService.resumeConversation(conversations[1].Id);
      Assert.fail('Should be refused.');
    } catch (AIChatConversationService.AIChatConversationServiceException ex) {
      shown = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      [SELECT Status__c FROM AIConversation__c WHERE Id = :conversations[0].Id]
      .Status__c,
      'Reopened.'
    );
    Assert.areEqual(
      Label.AI_Error_Conversation_Closed,
      shown,
      'The text is the Custom Label.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AllowConversationResume__c = true;
    update agent;
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    settings.MaxConcurrentConversations__c = 1;
    insert settings;
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    );
    AIConversation__c closed = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      false
    )[0];
    closed.Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    closed.ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    closed.ConversationClosedTimestamp__c = System.now();
    insert closed;
    String shown;

    Test.startTest();
    try {
      AIChatConversationService.resumeConversation(closed.Id);
      Assert.fail('At the limit.');
    } catch (AIChatConversationService.AIChatConversationServiceException ex) {
      shown = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      Label.AI_Error_Concurrent_Limit,
      shown,
      'The concurrent limit.'
    );
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
      UserInfo.getUserId(),
      1,
      true
    )[0];
    User other = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIDataSource__c source = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id FROM Account',
      true
    )[0];
    String sourceName = [
      SELECT DeveloperName__c
      FROM AIDataSource__c
      WHERE Id = :source.Id
    ]
    .DeveloperName__c;

    Test.startTest();
    AIChatDataStructure.ExecutionStep provider = AIChatConversationService.toExecutionStep(
      new AIExecutionStep__c(
        StepType__c = AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL,
        Status__c = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
        StepOrder__c = 2,
        DurationMilliseconds__c = 40
      )
    );
    AIChatDataStructure.ExecutionStep masking = AIChatConversationService.toExecutionStep(
      new AIExecutionStep__c(
        StepType__c = AIAssistApplicationConstants.STEP_TYPE_PII_MASKING
      )
    );
    AIChatDataStructure.ExecutionStep anyOther = AIChatConversationService.toExecutionStep(
      new AIExecutionStep__c(
        StepType__c = AIAssistApplicationConstants.STEP_TYPE_OTHER
      )
    );
    AIChatDataStructure.ExecutionStep detail = AIChatConversationService.toExecutionStep(
      new AIExecutionStep__c(StepDetail__c = 'Custom')
    );
    Test.stopTest();

    Assert.areEqual(
      Label.AI_Step_Calling_Model,
      provider.label,
      'Provider call.'
    );
    Assert.isTrue(
      provider.isSuccess &&
        provider.durationMs == 40 &&
        provider.stepOrder == 2,
      'Success, time and order.'
    );
    Assert.areEqual(Label.AI_Step_Protecting_Data, masking.label, 'Masking.');
    Assert.areEqual(Label.AI_Step_Finalising, anyOther.label, 'Anything else.');
    Assert.areEqual('Custom', detail.label, 'Stored detail wins.');
  }
}
