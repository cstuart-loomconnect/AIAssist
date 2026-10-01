/*
Class Name: AIChatControllerTest

=================================================================
=================================================================

Description: Testing utility for AIChatController: the window's round trips, how refusals are shown from their code, and that nothing internal reaches the window. The AI Agent Manager is replaced by a fake that answers.

=================================================================
=================================================================
Applicable Classes:

AIChatController

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIChatControllerTest {
  // testScenario1: A ready context offers the agent, the usage meter and no open conversation.
  // testScenario2: The context stops early with the right state when the application is off, in maintenance, the channel is not allowed, the terms are unsigned, or no agent is offered.
  // testScenario3: Sending a message creates the conversation, and the window gets SENT with the conversation and message.
  // testScenario4: A refusal comes back as a status chosen from its code, with the Custom Label and the code: LIMIT for a limit, BLOCKED for access, ERROR for a bad message.
  // testScenario5: A slash command the user cannot use is refused, and one they can use sends the visible text with the hidden instructions after the separator.
  // testScenario6: Open, update, history, close and resume work for the owner, and another user's conversation gives the not found label.
  // testScenario7: Debug, export and PII views are refused with the not authorised label for a user without the setting, and work with it.
  // testScenario8: Feedback, terms and a retry work, and feedback is refused while the setting is off.
  // testScenario9: An unexpected failure gives the window only the generic label and is logged.

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
      AIMessageProcessingQueueable.AIResponseRequest request
    ) {
      AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
      result.isSuccessful = true;
      result.replyText = 'Fake reply';
      result.totalTokensUsed = 15;
      return result;
    }
  }

  @IsTest
  static void testScenario1() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    update agent;

    Test.startTest();
    AIChatDataStructure.ChatContext context = AIChatController.getChatContext(
      null,
      null,
      AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_STATE_READY,
      context.state,
      'Ready.'
    );
    Assert.areEqual(agent.Id, context.agent.id, 'The agent.');
    Assert.isNotNull(context.usage, 'The usage meter.');
    Assert.isNull(context.openConversation, 'No conversation yet.');
  }

  @IsTest
  static void testScenario2() {
    List<String> states = new List<String>();
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();

    Test.startTest();
    states.add(AIChatController.getChatContext(null, null, null, null).state);
    settings.CurrentTermsVersion__c = 'v1';
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    states.add(AIChatController.getChatContext(null, null, null, null).state);
    settings.CurrentTermsVersion__c = null;
    ui.IsMaintenanceMode__c = true;
    upsert ui;
    states.add(AIChatController.getChatContext(null, null, null, null).state);
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    states.add(AIChatController.getChatContext(null, null, null, null).state);
    Test.stopTest();

    Assert.areEqual(
      new List<String>{
        AIAssistApplicationConstants.CHAT_STATE_NO_AGENT,
        AIAssistApplicationConstants.CHAT_STATE_TERMS,
        AIAssistApplicationConstants.CHAT_STATE_MAINTENANCE,
        AIAssistApplicationConstants.CHAT_STATE_INACTIVE
      },
      states,
      'Each state.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    update agent;
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIChatDataStructure.SendResult result;

    Test.startTest();
    result = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{
          'agentId' => agent.Id,
          'text' => 'Hello',
          'channel' => AIAssistApplicationConstants.CHANNEL_UTILITY_BAR
        }
      )
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT,
      result.status,
      'Sent.'
    );
    Assert.isTrue(result.isNewConversation, 'A new conversation.');
    Assert.areEqual('Hello', result.userMessage.displayText, 'The message.');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ],
      'And the job answered.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    update agent;
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    settings.MaxConcurrentConversations__c = 1;
    settings.UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES;
    insert settings;
    AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      UserInfo.getUserId(),
      1,
      true
    );
    AIAgent__c inactive = AIAssistTestDataFactory.createAIAgents(
      1,
      agent.AIModelConfiguration__c,
      false
    )[0];
    inactive.IsActive__c = false;
    insert inactive;

    Test.startTest();
    AIChatDataStructure.SendResult limited = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{ 'agentId' => agent.Id, 'text' => 'Hello' }
      )
    );
    AIChatDataStructure.SendResult blocked = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{ 'agentId' => inactive.Id, 'text' => 'Hello' }
      )
    );
    AIChatDataStructure.SendResult empty = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '   ' }
      )
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_LIMIT,
      limited.status,
      'A limit.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONCURRENT_LIMIT,
      limited.code,
      'With its code.'
    );
    Assert.areEqual(
      Label.AI_Error_Concurrent_Limit,
      limited.message,
      'The text is the Custom Label.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_BLOCKED,
      blocked.status,
      'Blocked.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR,
      empty.status,
      'A bad message.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    update agent;
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIChatCommandService.testCommands = new List<AIChatCommand__mdt>{
      new AIChatCommand__mdt(
        Command__c = '/sum',
        IsActive__c = true,
        PromptText__c = 'Summarise.'
      )
    };
    AIChatDataStructure.SendResult unknown;
    AIChatDataStructure.SendResult known;

    Test.startTest();
    unknown = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/nope' }
      )
    );
    known = AIChatController.sendMessage(
      JSON.serialize(
        new Map<String, Object>{ 'agentId' => agent.Id, 'text' => '/sum' }
      )
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_ERROR,
      unknown.status,
      'Not a command here.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CHAT_SEND_STATUS_SENT,
      known.status,
      'Sent.'
    );
    Assert.isTrue(known.userMessage.isCommand, 'Shown as a command.');
    Assert.isTrue(
      [
          SELECT MessageBody__c
          FROM AIConversationMessage__c
          WHERE Sender__c = :AIAssistApplicationConstants.SENDER_USER
        ]
        .MessageBody__c.contains('Summarise.'),
      'The hidden instructions are stored.'
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
    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      1,
      1,
      true
    )[0];
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      other.Id,
      1,
      true
    )[0];
    String shown;

    Test.startTest();
    AIChatDataStructure.ConversationView view = AIChatController.openConversation(
      conversation.Id
    );
    AIChatDataStructure.ConversationUpdate update1 = AIChatController.getConversationUpdate(
      conversation.Id,
      null
    );
    AIChatDataStructure.MessagePage earlier = AIChatController.getEarlierMessages(
      conversation.Id,
      message.Id
    );
    List<AIChatDataStructure.ConversationSummary> history = AIChatController.getConversationHistory(
      null,
      false
    );
    try {
      AIChatController.openConversation(theirs.Id);
      Assert.fail('Not theirs.');
    } catch (AuraHandledException ex) {
      shown = ex.getMessage();
    }
    AIChatController.closeConversation(conversation.Id);
    Test.stopTest();

    Assert.areEqual(1, view.messages.size(), 'The message.');
    Assert.areEqual(1, update1.messages.size(), 'The update.');
    Assert.isTrue(earlier.messages.isEmpty(), 'Nothing earlier.');
    Assert.areEqual(1, history.size(), 'Only the user\'s own.');
    Assert.areEqual(
      Label.AI_Error_Conversation_Not_Found,
      shown,
      'The text is the Custom Label.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
      [SELECT Status__c FROM AIConversation__c WHERE Id = :conversation.Id]
      .Status__c,
      'Closed.'
    );
  }

  @IsTest
  static void testScenario7() {
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
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    String shown;

    Test.startTest();
    try {
      AIChatController.getDebugTrace(reply.Id);
      Assert.fail('Debug is off.');
    } catch (AuraHandledException ex) {
      shown = ex.getMessage();
    }
    AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(
      UserInfo.getUserId(),
      false
    )[0];
    settings.DebugModeEnabled__c = true;
    settings.ConversationExportEnabled__c = true;
    insert settings;
    AIChatDataStructure.DebugTrace trace = AIChatController.getDebugTrace(
      reply.Id
    );
    String pairs = AIChatController.getPiiMappings(reply.Id);
    String exported = AIChatController.exportConversation(conversation.Id);
    AIChatDataStructure.FailureDetail detail = AIChatController.getFailureDetail(
      conversation.Id
    );
    Test.stopTest();

    Assert.areEqual(
      Label.AI_Error_Not_Authorised,
      shown,
      'The text is the Custom Label.'
    );
    Assert.areEqual(reply.Id, trace.replyMessageId, 'The trace.');
    Assert.areEqual('{ }', pairs, 'No masking.');
    Assert.isTrue(exported.contains('Test message'), 'The transcript.');
    Assert.isNotNull(detail, 'The failure detail.');
  }

  @IsTest
  static void testScenario8() {
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
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_AI_AGENT,
      5,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      1,
      1,
      true
    );
    agent.AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
    update agent;
    AIAssistSettings__c terms = AIAssistSettings__c.getOrgDefaults();
    terms.CurrentTermsVersion__c = 'v1';
    update terms;
    AIAssistSettingsService.cachedSettings = null;
    String shown;

    Test.startTest();
    AIChatController.submitFeedback(
      reply.Id,
      AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL,
      null,
      null
    );
    AIChatController.acknowledgeTerms();
    AIChatController.retryLatestMessage(conversation.Id);
    AIAssistUISettings__c ui = AIAssistUISettings__c.getOrgDefaults();
    ui.IsFeedbackEnabled__c = false;
    upsert ui;
    try {
      AIChatController.submitFeedback(
        reply.Id,
        AIAssistApplicationConstants.FEEDBACK_RATING_HELPFUL,
        null,
        null
      );
      Assert.fail('Feedback is off.');
    } catch (AuraHandledException ex) {
      shown = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM AIFeedback__c], 'One rating.');
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AITermsAcknowledgment__c],
      'Terms acknowledged.'
    );
    Assert.areEqual(
      Label.AI_Error_Not_Authorised,
      shown,
      'The text is the Custom Label.'
    );
  }

  @IsTest
  static void testScenario9() {
    String shown;

    Test.startTest();
    try {
      AIChatController.sendMessage('not json');
      Assert.fail('Bad request.');
    } catch (AuraHandledException ex) {
      shown = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      Label.AI_Error_Generic,
      shown,
      'Nothing internal is shown.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIChatController'
      ],
      'Logged once.'
    );
  }
}
