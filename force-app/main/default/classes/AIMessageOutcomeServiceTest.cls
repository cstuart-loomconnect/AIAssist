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
}
