/*
Class Name: AIMessageProcessingFinalizerTest

=================================================================
=================================================================

Description: Testing utility for AIMessageProcessingFinalizer: what must always happen when a turn ends: release or hand on the lock, retry, and tell the chat window when nothing else can.

=================================================================
=================================================================
Applicable Classes:

AIMessageProcessingFinalizer

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMessageProcessingFinalizerTest {
  // testScenario1: A turn that ended normally with nothing waiting releases the lock.
  // testScenario2: A newer message that arrived during the turn is handed the lock and queued, and the answer is recorded.
  // testScenario3: A requested retry queues the same message again with the tokens so far and keeps the conversation locked.
  // testScenario4: A job that started after its lock expired is failed as a timeout and leaves the lock alone.
  // testScenario5: When the retry cannot be queued the turn is failed as a provider error and the lock is released, so the user is not left waiting.
  // testScenario6: When the waiting message cannot be queued the lock is released and the chat window is told.
  // testScenario7: setTokens treats null as zero, and the turn context is the one the job fills in.
  // testScenario8: A conversation that has been deleted does not make the finalizer throw.

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

  // Fills the asynchronous queue so the finalizer cannot add to it.
  private class IdleJob implements Queueable {
    public void execute(QueueableContext context) {
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
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );

    Test.startTest();
    finalizer.execute(null);
    Test.stopTest();

    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'Released.'
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
    AIConversationMessage__c newer = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );

    Test.startTest();
    finalizer.execute(null);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :newer.Id
      ]
      .ProcessingStatus__c,
      'The waiting message was picked up and answered.'
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
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );
    finalizer.scheduleRetry(40, 10);
    Boolean lockedAfterFinalizer;

    Test.startTest();
    finalizer.execute(null);
    lockedAfterFinalizer = AIConversationLockService.isConversationLocked(
      conversation.Id
    );
    Test.stopTest();

    Assert.isTrue(lockedAfterFinalizer, 'The lock is kept for the retry.');
    Assert.areEqual(40, finalizer.inputTokens, 'The tokens are carried.');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversation.Id
          AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
      ],
      'The retry ran and answered.'
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
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );
    finalizer.markLockExpired();

    Test.startTest();
    finalizer.execute(null);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .FailureReason__c,
      'Timed out.'
    );
    Assert.isTrue(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'The lock belongs to whoever holds it now.'
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
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );
    finalizer.scheduleRetry(10, 5);

    Test.startTest();
    for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++)
      System.enqueueJob(new IdleJob());
    finalizer.execute(null);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      [
        SELECT FailureReason__c
        FROM AIConversationMessage__c
        WHERE Id = :question.Id
      ]
      .FailureReason__c,
      'The turn ended as failed.'
    );
    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'And the lock was freed.'
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
    AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      0,
      1,
      true
    );
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );

    Test.startTest();
    for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++)
      System.enqueueJob(new IdleJob());
    finalizer.execute(null);
    Test.stopTest();

    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'The lock was freed, not left behind a job nobody queued.'
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIMessageProcessingFinalizer'
      ] >= 1,
      'The failure was logged.'
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
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      null,
      chatUser.Id
    );

    Test.startTest();
    finalizer.recordTokensSpent(null, null);
    AIMessageOutcomeService.AIResponseContext responseContext = finalizer.getResponseContext();
    Test.stopTest();

    Assert.areEqual(
      0,
      finalizer.inputTokens + finalizer.outputTokens,
      'Null is none.'
    );
    Assert.areEqual(
      conversation.Id,
      responseContext.conversationId,
      'The conversation.'
    );
    Assert.areEqual(
      question.Id,
      responseContext.triggeringMessageId,
      'The message.'
    );
    Assert.areEqual(chatUser.Id, responseContext.userId, 'The user.');
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
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      question.Id,
      conversation.Id,
      1,
      chatUser.Id
    );
    delete conversation;

    Test.startTest();
    try {
      finalizer.execute(null);
    } catch (Exception ex) {
      Assert.fail('A finalizer must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id],
      'The conversation is gone.'
    );
  }
}
