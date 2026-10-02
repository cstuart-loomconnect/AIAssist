/*
Class Name: AIMessageProcessingQueueableTest

=================================================================
=================================================================

Description: Testing utility for AIMessageProcessingQueueable: the asynchronous turn. The AI Agent Manager is replaced by a fake, so these tests prove what the job loads, bounds, records and reports.

=================================================================
=================================================================
Applicable Classes:

AIMessageProcessingQueueable

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessageProcessingQueueableTest {
  // testScenario1: A turn loads the conversation and agent, calls the executor with the question as the history, and records the reply.
  // testScenario2: The history is bounded by message count, ends with the question being answered even when newer messages exist, and leaves out System messages.
  // testScenario3: The history is also bounded by characters, keeping the newest message whatever its size.
  // testScenario4: If the lock has gone, the job stands down without calling the executor or writing anything.
  // testScenario5: A message deleted after it was queued is reported to the chat window without a failure record or an exception.
  // testScenario6: A failed provider result is recorded as a failed turn with its reason.
  // testScenario7: An unexpected exception is logged and recorded as Other, and one from the messaging layer as a configuration error.
  // testScenario8: A retryable result records nothing yet: the finalizer retries it as a new job.
  // testScenario9: As a real job, a data source write rolls the turn back and the finalizer records the failure and frees the lock.
  // testScenario10: As a real job, a retryable turn is retried by the finalizer as a second attempt that answers, and the lock is freed.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // Replaces the AI Agent Manager. The kind selects what the turn does, so the messaging layer is tested on its own behaviour.
  private class FakeExecutor implements AIMessageProcessingQueueable.IAIResponseExecutor {
    private String kind;

    public FakeExecutor(String kind) {
      this.kind = kind;
    }

    public AIAgentManager.AgentResult execute(
      AIMessageProcessingQueueable.AIResponseRequest request
    ) {
      if (kind == 'generic')
        throw new CalloutException('Boom');
      if (kind == 'config')
        throw AIMessagingException.newFailure('No model', null);
      if (kind == 'write') {
        AIAgentManager.AIDataSourceWriteException writeException = new AIAgentManager.AIDataSourceWriteException(
          'Wrote'
        );
        writeException.tokensUsed = 25;
        throw writeException;
      }

      AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
      result.inputTokens = 10;
      result.outputTokens = 5;
      result.totalTokensUsed = 15;

      if (kind == 'fail') {
        result.failureReason = AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
        result.errorMessage = 'Provider said no';
      } else if (kind == 'retry' && request.attemptNumber < 2) {
        result.isRetryable = true;
      } else {
        result.isSuccessful = true;
        result.replyText = kind == 'echo'
          ? request.messageHistory.size() +
            '|' +
            request.messageHistory[request.messageHistory.size() - 1]
              .MessageBody__c
          : 'attempt ' + request.attemptNumber;
      }

      return result;
    }
  }

  @IsTest
  static void testScenario1() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('echo');

    Test.startTest();
    new AIMessageProcessingQueueable(question.Id, conversation.Id)
      .execute(null);
    Test.stopTest();

    AIConversationMessage__c reply = [
      SELECT MessageBody__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
    ];
    Assert.areEqual(
      '1|Test message 0',
      reply.MessageBody__c,
      'The history was the question alone.'
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
  }

  @IsTest
  static void testScenario2() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    List<AIConversationMessage__c> older = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      AIAssistApplicationConstants.MAX_HISTORY_MESSAGES + 10,
      true
    );
    AIConversationMessage__c newerThanQuestion = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_SYSTEM,
      10,
      3,
      true
    );
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('echo');

    Test.startTest();
    new AIMessageProcessingQueueable(
        older[older.size() - 1].Id,
        conversation.Id
      )
      .execute(null);
    Test.stopTest();

    String replyText = [
      SELECT MessageBody__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
    ]
    .MessageBody__c;
    Assert.areEqual(
      AIAssistApplicationConstants.MAX_HISTORY_MESSAGES +
        '|' +
        older[older.size() - 1].MessageBody__c,
      replyText,
      'Capped, and it ends with the message being answered, not the newer one.'
    );
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    Integer half =
      (AIAssistApplicationConstants.MAX_HISTORY_CHARACTERS / 2) + 1;
    List<AIConversationMessage__c> big = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      3,
      false
    );
    for (AIConversationMessage__c message : big)
      message.MessageBody__c = 'x'.repeat(half);
    insert big;
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('echo');

    Test.startTest();
    new AIMessageProcessingQueueable(big[2].Id, conversation.Id).execute(null);
    Test.stopTest();

    Assert.isTrue(
      [
          SELECT MessageBody__c
          FROM AIConversationMessage__c
          WHERE
            AIConversation__c = :conversation.Id
            AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
        ]
        .MessageBody__c.startsWith('1|'),
      'Only the newest fits within the character budget.'
    );
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIConversationLockService.releaseLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor(
      'generic'
    );

    Test.startTest();
    new AIMessageProcessingQueueable(question.Id, conversation.Id)
      .execute(null);
    Test.stopTest();

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c != :AIAssistApplicationConstants.SENDER_USER
      ],
      'No reply and no failure record: the executor was never called.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIPlatformLog__c],
      'Standing down is not a fault.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    Id deletedId = question.Id;
    delete question;
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor(
      'generic'
    );

    Test.startTest();
    try {
      new AIMessageProcessingQueueable(deletedId, conversation.Id)
        .execute(null);
    } catch (Exception ex) {
      Assert.fail(
        'A missing message must not fail the job: ' + ex.getMessage()
      );
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE AIConversation__c = :conversation.Id
      ],
      'Nothing was written.'
    );
  }

  @IsTest
  static void testScenario6() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('fail');

    Test.startTest();
    new AIMessageProcessingQueueable(question.Id, conversation.Id)
      .execute(null);
    Test.stopTest();

    AIConversationMessage__c failed = [
      SELECT ProcessingStatus__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE Id = :question.Id
    ];
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      failed.ProcessingStatus__c,
      'The question failed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      failed.FailureReason__c,
      'With the executor\'s reason.'
    );
  }

  @IsTest
  static void testScenario7() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIConversationMessage__c second = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor(
      'generic'
    );
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor(
      'generic'
    );

    Test.startTest();
    new AIMessageProcessingQueueable(question.Id, conversation.Id)
      .execute(null);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor(
      'config'
    );
    new AIMessageProcessingQueueable(second.Id, conversation.Id).execute(null);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_OTHER,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .FailureReason__c,
      'An unexpected exception is Other.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :second.Id
      ]
      .FailureReason__c,
      'A setup problem is a configuration error.'
    );
    Assert.isTrue(
      [SELECT COUNT() FROM AIPlatformLog__c] >= 2,
      'Both were logged.'
    );
  }

  @IsTest
  static void testScenario8() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('retry');
    String statusBefore = [
      SELECT ProcessingStatus__c
      FROM AIConversationMessage__c
      WHERE Id = :question.Id
    ]
    .ProcessingStatus__c;

    Test.startTest();
    new AIMessageProcessingQueueable(question.Id, conversation.Id)
      .execute(null);
    Test.stopTest();

    Assert.areEqual(
      statusBefore,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .ProcessingStatus__c,
      'The question is untouched: still waiting for its retry.'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c != :AIAssistApplicationConstants.SENDER_USER
      ],
      'And nothing else was written.'
    );
  }

  @IsTest
  static void testScenario9() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('write');

    Boolean wasRolledBack = false;

    try {
      Test.startTest();
      System.enqueueJob(
        new AIMessageProcessingQueueable(question.Id, conversation.Id)
      );
      Test.stopTest();
    } catch (AIAgentManager.AIDataSourceWriteException ex) {
      wasRolledBack = true;
    }

    AIConversationMessage__c failed = [
      SELECT ProcessingStatus__c
      FROM AIConversationMessage__c
      WHERE Id = :question.Id
    ];
    Assert.isTrue(
      wasRolledBack,
      'The job let the exception out on purpose, so the write is rolled back.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      failed.ProcessingStatus__c,
      'The finalizer recorded the failure.'
    );
    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'And freed the conversation.'
    );
  }

  @IsTest
  static void testScenario10() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
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
    AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIMessageProcessingQueueable.aiResponseExecutor = new FakeExecutor('retry');

    Test.startTest();
    System.enqueueJob(
      new AIMessageProcessingQueueable(question.Id, conversation.Id)
    );
    Test.stopTest();

    List<AIConversationMessage__c> replies = [
      SELECT MessageBody__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversation.Id
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
    ];
    Assert.areEqual(1, replies.size(), 'One reply.');
    Assert.areEqual(
      'attempt 2',
      replies[0].MessageBody__c,
      'From the second attempt.'
    );
    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'The conversation is free again.'
    );
  }
}
