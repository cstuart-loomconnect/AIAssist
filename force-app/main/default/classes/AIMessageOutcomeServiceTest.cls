/*
Class Name: AIMessageOutcomeServiceTest

=================================================================
=================================================================

Description: Testing utility for AIMessageOutcomeService: what is recorded when a turn ends, whether it succeeded or failed, and the label the chat window is told.

=================================================================
=================================================================
Applicable Classes:

AIMessageOutcomeService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessageOutcomeServiceTest {
  // testScenario1: A successful turn stores the reply with the provider's tokens, latency and model, marks the question Complete and adds the usage.
  // testScenario2: An Estimate agent counts the reply by its length, and a provider that reports only a total has it counted as input.
  // testScenario3: A suggested workflow action is stored when it is a real action Id, and ignored when it is the wrong type or not an Id.
  // testScenario4: A failed result records the reason on the question, a System message holding the tokens spent, the failed turn in the usage, and the cause in the log.
  // testScenario5: A null result and a blank reason both fail the turn as Other.
  // testScenario6: recordFailure fails the turn with the given reason and tokens, and treats null tokens as none.
  // testScenario7: notifyFailure returns the Custom Label that matches each reason, and the generic one for any other.
  // testScenario8: When the reply cannot be saved the turn becomes a failed turn, and a null turn never throws.
  // testScenario9: Two messages sent while a third is being answered all end up Complete: the first by its own reply, the skipped one and the newest by the newest's reply. A failed turn fails the messages waiting behind it the same way.
  // testScenario10: A regenerated reply supersedes the earlier reply to the same message once it is saved, and a regenerate that fails leaves the earlier reply standing.

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
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      result,
      new AIExecutionStepTracker(conversation.Id, question.Id, false, false)
    );
    Test.stopTest();

    AIConversationMessage__c reply = [
      SELECT
        MessageBody__c,
        TokenCount__c,
        InputTokenCount__c,
        OutputTokenCount__c,
        LatencyMilliseconds__c,
        AIModelConfiguration__c,
        ProcessingStatus__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
    ];
    AIUsageDaily__c usage = [
      SELECT
        MessageCount__c,
        FailedTurnCount__c,
        InputTokens__c,
        OutputTokens__c
      FROM AIUsageDaily__c
      WHERE User__c = :chatUser.Id
    ];

    Assert.areEqual('The answer', reply.MessageBody__c, 'The reply.');
    Assert.areEqual(
      50,
      reply.TokenCount__c,
      'A tracked agent uses the provider\'s total.'
    );
    Assert.areEqual(40, reply.InputTokenCount__c, 'Input tokens.');
    Assert.areEqual(10, reply.OutputTokenCount__c, 'Output tokens.');
    Assert.areEqual(1200, reply.LatencyMilliseconds__c, 'Latency.');
    Assert.areEqual(
      agent.AIModelConfiguration__c,
      reply.AIModelConfiguration__c,
      'The model.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .ProcessingStatus__c,
      'The question is Complete.'
    );
    Assert.areEqual(1, usage.MessageCount__c, 'One responseContext.');
    Assert.areEqual(0, usage.FailedTurnCount__c, 'None failed.');
    Assert.areEqual(40, usage.InputTokens__c, 'Input tokens counted.');
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE;
    result.replyText = 'x'
      .repeat(AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE * 8);
    result.inputTokens = 0;
    result.outputTokens = 0;
    result.totalTokensUsed = 77;

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      result,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      8,
      [
        SELECT TokenCount__c
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ]
      .TokenCount__c,
      'Estimated from the length.'
    );
    Assert.areEqual(
      77,
      [SELECT InputTokens__c FROM AIUsageDaily__c WHERE User__c = :chatUser.Id]
      .InputTokens__c,
      'The only figure there is counts as input.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    )[0];
    List<String> suggestions = new List<String>{
      action.Id,
      agent.Id,
      'not an id'
    };

    Test.startTest();
    for (String suggestion : suggestions) {
      result.suggestedWorkflowActionId = suggestion;
      AIMessageOutcomeService.recordAiResponseOutcome(
        responseContext,
        result,
        null
      );
    }
    Test.stopTest();

    List<AIConversationMessage__c> replies = [
      SELECT SuggestedWorkflowAction__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ORDER BY CreatedDate, Id
    ];
    Assert.areEqual(
      3,
      replies.size(),
      'A bad suggestion never fails the reply.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE SuggestedWorkflowAction__c = :action.Id
      ],
      'Only the real action is stored.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    result.isSuccessful = false;
    result.failureReason = AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;
    result.errorMessage = 'Read timed out';

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      result,
      null
    );
    Test.stopTest();

    AIConversationMessage__c failedQuestion = [
      SELECT ProcessingStatus__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE Id = :question.Id
    ];
    AIConversationMessage__c systemMessage = [
      SELECT TokenCount__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM
    ];

    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      failedQuestion.ProcessingStatus__c,
      'The question failed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
      failedQuestion.FailureReason__c,
      'With the reason.'
    );
    Assert.areEqual(
      50,
      systemMessage.TokenCount__c,
      'The tokens a failed turn spent still count.'
    );
    Assert.areEqual(
      1,
      [
        SELECT FailedTurnCount__c
        FROM AIUsageDaily__c
        WHERE User__c = :chatUser.Id
      ]
      .FailedTurnCount__c,
      'A failed turn is counted.'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ],
      'No reply.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIMessageOutcomeService'
      ],
      'The detail went to the log, not to a record the user can read.'
    );
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    result.isSuccessful = false;
    result.failureReason = null;

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      result,
      null
    );
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      null,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_OTHER,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .FailureReason__c,
      'Other.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseFailure(
      responseContext,
      null,
      'Job was killed',
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
    );
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .FailureReason__c,
      'The reason.'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM
      ],
      'No tokens, so no System message.'
    );
  }

  @IsTest
  static void testScenario7() {
    Map<String, String> labelByReason = new Map<String, String>{
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT => Label.AI_Error_Provider_Timeout,
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR => Label.AI_Error_Provider_Unavailable,
      AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED => Label.AI_Error_Daily_Usage_Limit,
      AIAssistApplicationConstants.FAILURE_REASON_REQUEST_BLOCKED => Label.AI_Error_Request_Blocked,
      AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED => Label.AI_Error_Privacy_Masking_Failed,
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR => Label.AI_Error_Provider_Not_Configured,
      AIAssistApplicationConstants.FAILURE_REASON_MESSAGE_MISSING => Label.AI_Error_Conversation_Not_Found,
      AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED => Label.AI_Error_Provider_Authentication,
      AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED => Label.AI_Error_Provider_Model_Retired,
      AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED => Label.AI_Error_Provider_Rate_Limited,
      AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY => Label.AI_Error_Service_Busy,
      AIAssistApplicationConstants.FAILURE_REASON_OTHER => Label.AI_Error_Generic
    };
    Map<String, String> actual = new Map<String, String>();

    Test.startTest();
    for (String reason : labelByReason.keySet())
      actual.put(
        reason,
        AIMessageOutcomeService.publishMessageFailure(null, reason)
      );
    String unknown = AIMessageOutcomeService.publishMessageFailure(
      null,
      'Something new'
    );
    Test.stopTest();

    for (String reason : labelByReason.keySet())
      Assert.areEqual(
        labelByReason.get(reason),
        actual.get(reason),
        'The label for ' + reason + '.'
      );
    Assert.areEqual(
      Label.AI_Error_Generic,
      unknown,
      'An unknown reason is generic.'
    );
  }

  @IsTest
  static void testScenario8() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = question.Id;
    responseContext.userId = chatUser.Id;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = 'The answer';
    result.inputTokens = 40;
    result.outputTokens = 10;
    result.totalTokensUsed = 50;
    result.latencyMilliseconds = 1200;

    responseContext.conversationId = agent.Id;

    Test.startTest();
    try {
      AIMessageOutcomeService.recordAiResponseOutcome(
        responseContext,
        result,
        null
      );
      AIMessageOutcomeService.recordAiResponseOutcome(null, result, null);
      AIMessageOutcomeService.recordAiResponseFailure(null, 0, null, null);
    } catch (Exception ex) {
      Assert.fail('Outcome recording must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .ProcessingStatus__c,
      'No reply could be saved, so the turn failed.'
    );
  }

  // A conversation with user messages a second apart, all Queued, and the context of a turn on the message at the given index.
  private static List<AIConversationMessage__c> createQueuedMessages(
    AIConversation__c conversation,
    Integer numberOfMessages
  ) {
    List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      numberOfMessages,
      false
    );
    for (AIConversationMessage__c message : messages)
      message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
    insert messages;
    for (Integer index = 0; index < messages.size(); index++)
      Test.setCreatedDate(
        messages[index].Id,
        System.now().addMinutes(-10).addSeconds(index)
      );

    return messages;
  }

  private static AIMessageOutcomeService.AIResponseContext contextFor(
    AIConversation__c conversation,
    AIAgent__c agent,
    Id messageId
  ) {
    AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
    responseContext.conversationId = conversation.Id;
    responseContext.triggeringMessageId = messageId;
    responseContext.userId = conversation.OwnerId;
    responseContext.agentId = agent.Id;
    responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
    responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

    return responseContext;
  }

  private static AIAgentManager.AgentResult reply(String text) {
    AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
    result.isSuccessful = true;
    result.replyText = text;
    result.inputTokens = 4;
    result.outputTokens = 1;
    result.totalTokensUsed = 5;

    return result;
  }

  private static Map<Id, String> statusById(
    List<AIConversationMessage__c> messages
  ) {
    Map<Id, String> statuses = new Map<Id, String>();
    for (AIConversationMessage__c message : [
      SELECT ProcessingStatus__c
      FROM AIConversationMessage__c
      WHERE Id IN :messages
    ])
      statuses.put(message.Id, message.ProcessingStatus__c);

    return statuses;
  }

  @IsTest
  static void testScenario9() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      2,
      true
    );
    for (AIConversation__c conversation : conversations)
      conversation.OwnerId = chatUser.Id;
    // The first is being answered when the second and third are sent.
    List<AIConversationMessage__c> answered = createQueuedMessages(
      conversations[0],
      3
    );
    List<AIConversationMessage__c> failed = createQueuedMessages(
      conversations[1],
      2
    );

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      contextFor(conversations[0], agent, answered[0].Id),
      reply('First answer'),
      null
    );
    Map<Id, String> afterFirst = statusById(answered);
    // The finalizer hands the lock to the newest, so the second is never answered itself.
    AIMessageOutcomeService.recordAiResponseOutcome(
      contextFor(conversations[0], agent, answered[2].Id),
      reply('Newest answer'),
      null
    );
    AIMessageOutcomeService.recordAiResponseFailure(
      contextFor(conversations[1], agent, failed[1].Id),
      0,
      'The provider is down.',
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
    );
    Test.stopTest();

    Map<Id, String> afterNewest = statusById(answered);
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      afterFirst.get(answered[0].Id),
      'The first is Complete by its own reply.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
      afterFirst.get(answered[1].Id),
      'A message sent after the one answered is still waiting.'
    );
    for (AIConversationMessage__c message : answered)
      Assert.areEqual(
        AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
        afterNewest.get(message.Id),
        'All three end up Complete, including the one the hand-off skipped.'
      );
    for (AIConversationMessage__c message : [
      SELECT ProcessingStatus__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE Id IN :failed
    ]) {
      Assert.areEqual(
        AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
        message.ProcessingStatus__c,
        'A failed turn fails the message waiting behind it too.'
      );
      Assert.areEqual(
        AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
        message.FailureReason__c,
        'With the same reason.'
      );
    }
  }

  @IsTest
  static void testScenario10() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    conversation.OwnerId = chatUser.Id;
    AIConversationMessage__c question = createQueuedMessages(
      conversation,
      1
    )[0];
    AIMessageOutcomeService.AIResponseContext responseContext = contextFor(
      conversation,
      agent,
      question.Id
    );

    Test.startTest();
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      reply('First answer'),
      null
    );
    AIMessageOutcomeService.recordAiResponseFailure(
      responseContext,
      0,
      'The regenerate failed.',
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
    );
    Map<String, Boolean> afterFailure = new Map<String, Boolean>();
    for (AIConversationMessage__c answer : [
      SELECT MessageBody__c, IsSuperseded__c
      FROM AIConversationMessage__c
      WHERE InReplyTo__c = :question.Id
    ])
      afterFailure.put(answer.MessageBody__c, answer.IsSuperseded__c);
    AIMessageOutcomeService.recordAiResponseOutcome(
      responseContext,
      reply('Second answer'),
      null
    );
    Test.stopTest();

    Map<String, Boolean> afterRegenerate = new Map<String, Boolean>();
    for (AIConversationMessage__c answer : [
      SELECT MessageBody__c, IsSuperseded__c
      FROM AIConversationMessage__c
      WHERE InReplyTo__c = :question.Id
    ])
      afterRegenerate.put(answer.MessageBody__c, answer.IsSuperseded__c);

    Assert.areEqual(
      new Map<String, Boolean>{ 'First answer' => false },
      afterFailure,
      'A failed regenerate leaves the earlier reply standing.'
    );
    Assert.areEqual(
      new Map<String, Boolean>{
        'First answer' => true,
        'Second answer' => false
      },
      afterRegenerate,
      'The new reply replaces the old one, and both answer the same message.'
    );
  }
}
