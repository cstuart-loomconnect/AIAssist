/*
Class Name: AIConversationMessageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationMessageService: sending, continuing, retrying and closing, as a real end user holding only the AI Assist User permission set. The AI Agent Manager is replaced by a fake that answers.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationMessageServiceTest {
  // testScenario1: A first message creates the conversation, stores the user message, takes the lock, and and the queued job answers it.
  // testScenario2: A second message continues the open conversation named by its Id, and an agent that keeps one conversation per record reuses it for the same record.
  // testScenario3: A conversation Id that is closed, on another agent, another user's or of the wrong type is not continued: a new conversation is started.
  // testScenario4: A conversation at the agent's message cap, and one at its token cap, are closed with the matching reason and the message starts a new conversation.
  // testScenario5: When new chats are paused a new conversation is refused with its label, and a bad request is refused with the validator's label, with nothing stored.
  // testScenario6: A message sent while another is being processed is stored and waits: it does not start a second job, and the first job hands over to it.
  // testScenario7: retryMessage re-queues the newest user message, clears its failure and the queued job answers it.
  // testScenario8: retryMessage refuses a closed conversation, one with no user message, another user's, a bad Id, and one that is busy.
  // testScenario9: closeConversation closes the user's own conversation with the given reason, or the default, and reports another user's, a missing one and a bad Id as not found.
  // testScenario10: estimateTokens is zero for blank text, rounds up, and is exact on a multiple of the characters-per-token estimate.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  // The AI Agent Manager replaced, so the messaging layer is tested on its own behaviour: it answers every turn successfully.
  private class AnsweringExecutor implements AIMessageProcessingQueueable.IAIResponseExecutor {
    public AIAgentManager.AgentResult execute(
      AIMessageProcessingQueueable.AIResponseRequest request
    ) {
      AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
      result.isSuccessful = true;
      result.replyText = 'Fake reply';
      result.inputTokens = 10;
      result.outputTokens = 5;
      result.totalTokensUsed = 15;
      return result;
    }
  }

  @IsTest
  static void testScenario1() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIConversationMessage__c sent;

    System.runAs(chatUser) {
      Test.startTest();
      sent = AIConversationMessageService.sendMessage(
        agent.Id,
        'Hello there',
        AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
        null,
        null
      );
      Test.stopTest();
    }

    AIConversationMessage__c userMessage = [
      SELECT ProcessingStatus__c, AIConversation__c
      FROM AIConversationMessage__c
      WHERE Id = :sent.Id
    ];
    List<AIConversationMessage__c> replies = [
      SELECT MessageBody__c, TokenCount__c, InputTokenCount__c
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :sent.AIConversation__c
        AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT
    ];

    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      userMessage.ProcessingStatus__c,
      'The answered message is Complete.'
    );
    Assert.areEqual(1, replies.size(), 'One reply.');
    Assert.areEqual(
      'Fake reply',
      replies[0].MessageBody__c,
      'It is the executor\'s answer.'
    );
    Assert.areEqual(
      10,
      replies[0].InputTokenCount__c,
      'The reply carries the executor\'s tokens.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE
          OwnerId = :chatUser.Id
          AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
      ],
      'The user owns one Active conversation.'
    );
  }

  @IsTest
  static void testScenario2() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    agent.SingleActiveConversationPerRecord__c = true;
    update agent;
    Account record;
    AIConversation__c conversation;
    System.runAs(chatUser) {
      record = AIAssistTestDataFactory.createAccounts(1, true)[0];
      conversation = AIAssistTestDataFactory.createAIConversations(
        agent.Id,
        chatUser.Id,
        1,
        false
      )[0];
      conversation.RelatedObjectAPIName__c = 'Account';
      conversation.RelatedRecordId__c = String.valueOf(record.Id);
      insert conversation;
    }
    AIConversationMessage__c byId;
    AIConversationMessage__c byRecord;

    System.runAs(chatUser) {
      Test.startTest();
      byId = AIConversationMessageService.sendMessage(
        conversation.Id,
        agent.Id,
        'Hello',
        null,
        'Account',
        record.Id
      );
      byRecord = AIConversationMessageService.sendMessage(
        agent.Id,
        'Again',
        null,
        'Account',
        record.Id
      );
      Test.stopTest();
    }

    Assert.areEqual(
      conversation.Id,
      byId.AIConversation__c,
      'The open conversation is continued by Id.'
    );
    Assert.areEqual(
      conversation.Id,
      byRecord.AIConversation__c,
      'And found again by record.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIConversation__c WHERE OwnerId = :chatUser.Id],
      'No second conversation was created.'
    );
  }

  @IsTest
  static void testScenario3() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ otherUser },
      'AIAssistUser'
    );
    AIAgent__c otherAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      2,
      false
    );
    conversations[0]
      .Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversations[0]
      .ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    conversations[0].ConversationClosedTimestamp__c = Datetime.now();
    conversations[1].AIAgent__c = otherAgent.Id;
    insert conversations;
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      otherUser.Id,
      1,
      true
    )[0];
    Set<Id> startedIds = new Set<Id>();

    System.runAs(chatUser) {
      Test.startTest();
      startedIds.add(
        AIConversationMessageService.sendMessage(
            conversations[0].Id,
            agent.Id,
            'one',
            null,
            null,
            null
          )
          .AIConversation__c
      );
      startedIds.add(
        AIConversationMessageService.sendMessage(
            conversations[1].Id,
            agent.Id,
            'two',
            null,
            null,
            null
          )
          .AIConversation__c
      );
      startedIds.add(
        AIConversationMessageService.sendMessage(
            theirs.Id,
            agent.Id,
            'three',
            null,
            null,
            null
          )
          .AIConversation__c
      );
      startedIds.add(
        AIConversationMessageService.sendMessage(
            agent.Id,
            agent.Id,
            'four',
            null,
            null,
            null
          )
          .AIConversation__c
      );
      Test.stopTest();
    }

    Assert.isFalse(
      startedIds.contains(conversations[0].Id) ||
        startedIds.contains(conversations[1].Id) ||
        startedIds.contains(theirs.Id),
      'None of those conversations was used.'
    );
    Assert.isFalse(
      startedIds.isEmpty(),
      'Messages were stored in conversations of the user\'s own.'
    );
  }

  @IsTest
  static void testScenario4() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    List<AIAgent__c> capped = AIAssistTestDataFactory.createAIAgents(
      2,
      model.Id,
      false
    );
    capped[0].MaxMessagesPerConversation__c = 2;
    capped[1].MaxTokensPerConversation__c = 100;
    capped[1]
      .TokenTrackingMethod__c = AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE;
    insert capped;
    AIConversation__c full = AIAssistTestDataFactory.createAIConversations(
      capped[0].Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversation__c heavy = AIAssistTestDataFactory.createAIConversations(
      capped[1].Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIAssistTestDataFactory.createAIConversationMessages(full.Id, 1, 2, true);
    AIAssistTestDataFactory.createAIConversationMessages(
      heavy.Id,
      100,
      1,
      true
    );
    AIConversationMessage__c afterMessageCap;
    AIConversationMessage__c afterTokenCap;

    System.runAs(chatUser) {
      Test.startTest();
      afterMessageCap = AIConversationMessageService.sendMessage(
        full.Id,
        capped[0].Id,
        'Hello',
        null,
        null,
        null
      );
      afterTokenCap = AIConversationMessageService.sendMessage(
        heavy.Id,
        capped[1].Id,
        'Hello',
        null,
        null,
        null
      );
      Test.stopTest();
    }

    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [
        SELECT Status__c, ConversationCloseReason__c
        FROM AIConversation__c
        WHERE Id IN :new Set<Id>{ full.Id, heavy.Id }
      ]
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED,
      byId.get(full.Id).ConversationCloseReason__c,
      'Closed at the message cap.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED,
      byId.get(heavy.Id).ConversationCloseReason__c,
      'Closed at the token cap.'
    );
    Assert.areNotEqual(
      full.Id,
      afterMessageCap.AIConversation__c,
      'A new conversation was started.'
    );
    Assert.areNotEqual(
      heavy.Id,
      afterTokenCap.AIConversation__c,
      'And another.'
    );
  }

  @IsTest
  static void testScenario5() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
    uiSettings.IsUserInitiatedChatEnabled__c = false;
    upsert uiSettings;
    List<String> codes = new List<String>();
    List<String> labels = new List<String>();

    System.runAs(chatUser) {
      Test.startTest();
      for (String body : new List<String>{ 'Hello', '   ' }) {
        try {
          AIConversationMessageService.sendMessage(
            agent.Id,
            body,
            null,
            null,
            null
          );
          Assert.fail('This message should have been refused.');
        } catch (AIMessagingException ex) {
          codes.add(ex.code);
          labels.add(ex.getMessage());
        }
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_NEW_CONVERSATIONS_PAUSED,
      codes[0],
      'New chats are paused.'
    );
    Assert.areEqual(
      Label.AI_Chat_New_Chats_Paused,
      labels[0],
      'The text is the Custom Label.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      codes[1],
      'A blank message is refused first.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM AIConversationMessage__c],
      'Nothing was stored.'
    );
  }

  @IsTest
  static void testScenario6() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);
    AIConversationMessage__c waiting;

    System.runAs(chatUser) {
      Test.startTest();
      waiting = AIConversationMessageService.sendMessage(
        conversation.Id,
        agent.Id,
        'Waiting',
        null,
        null,
        null
      );
      Integer jobsQueued = Limits.getQueueableJobs();
      Assert.areEqual(
        0,
        jobsQueued,
        'The conversation was locked, so no job was started for it.'
      );
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
      [
        SELECT ProcessingStatus__c
        FROM AIConversationMessage__c
        WHERE Id = :waiting.Id
      ]
      .ProcessingStatus__c,
      'The message waits as Queued.'
    );
    Assert.isTrue(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'The lock is still held by whoever took it.'
    );
  }

  @IsTest
  static void testScenario7() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c failed;
    failed = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      null,
      1,
      false
    )[0];
    failed.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED;
    failed.FailureReason__c = AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;
    insert failed;
    Id retried;

    System.runAs(chatUser) {
      Test.startTest();
      retried = AIConversationMessageService.retryLatestUserMessage(
        conversation.Id
      );
      Test.stopTest();
    }

    AIConversationMessage__c after = [
      SELECT ProcessingStatus__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE Id = :failed.Id
    ];
    Assert.areEqual(failed.Id, retried, 'It is the newest user message.');
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      after.ProcessingStatus__c,
      'The retry was answered.'
    );
    Assert.isNull(after.FailureReason__c, 'And the old failure is cleared.');
  }

  @IsTest
  static void testScenario8() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ otherUser },
      'AIAssistUser'
    );
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      4,
      false
    );
    conversations[0]
      .Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED;
    conversations[0]
      .ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED;
    conversations[0].ConversationClosedTimestamp__c = Datetime.now();
    insert conversations;
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      otherUser.Id,
      1,
      true
    )[0];
    System.runAs(chatUser) {
      insert AIAssistTestDataFactory.createAIConversationMessages(
        conversations[3].Id,
        null,
        1,
        false
      );
    }
    AIConversationLockService.acquireLock(conversations[3].Id);
    Map<String, String> codeByCase = new Map<String, String>();
    Map<String, Id> idByCase = new Map<String, Id>{
      'closed' => conversations[0].Id,
      'empty' => conversations[1].Id,
      'theirs' => theirs.Id,
      'badId' => agent.Id,
      'busy' => conversations[3].Id
    };

    System.runAs(chatUser) {
      Test.startTest();
      for (String key : idByCase.keySet()) {
        try {
          AIConversationMessageService.retryLatestUserMessage(
            idByCase.get(key)
          );
          Assert.fail('The ' + key + ' case should have been refused.');
        } catch (AIMessagingException ex) {
          codeByCase.put(key, ex.code);
        }
      }
      Test.stopTest();
    }

    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_CLOSED,
      codeByCase.get('closed'),
      'Closed.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
      codeByCase.get('empty'),
      'Nothing to retry.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
      codeByCase.get('theirs'),
      'Another user\'s conversation is reported as not found.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
      codeByCase.get('badId'),
      'An Id of the wrong type is too.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_BUSY,
      codeByCase.get('busy'),
      'A turn is already running.'
    );
  }

  @IsTest
  static void testScenario9() {
    User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ chatUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIMessageProcessingQueueable.aiResponseExecutor = new AnsweringExecutor();
    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ otherUser },
      'AIAssistUser'
    );
    List<AIConversation__c> mine = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      2,
      true
    );
    AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      otherUser.Id,
      1,
      true
    )[0];
    List<String> codes = new List<String>();

    System.runAs(chatUser) {
      Test.startTest();
      AIConversationMessageService.closeConversation(mine[0].Id, null);
      AIConversationMessageService.closeConversation(
        mine[1].Id,
        AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE
      );
      for (Id badId : new List<Id>{ theirs.Id, agent.Id, null }) {
        try {
          AIConversationMessageService.closeConversation(badId, null);
          Assert.fail('This conversation should not have been closable.');
        } catch (AIMessagingException ex) {
          codes.add(ex.code);
          Assert.areEqual(
            Label.AI_Error_Conversation_Not_Found,
            ex.getMessage(),
            'The text is the Custom Label.'
          );
        }
      }
      Test.stopTest();
    }

    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [
        SELECT
          Status__c,
          ConversationCloseReason__c,
          ConversationClosedTimestamp__c
        FROM AIConversation__c
      ]
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED,
      byId.get(mine[0].Id).ConversationCloseReason__c,
      'The default reason.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE,
      byId.get(mine[1].Id).ConversationCloseReason__c,
      'The given reason.'
    );
    Assert.isNotNull(
      byId.get(mine[0].Id).ConversationClosedTimestamp__c,
      'The close time was stamped by the trigger.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      byId.get(theirs.Id).Status__c,
      'Theirs is untouched.'
    );
    Assert.areEqual(3, codes.size(), 'Three refusals.');
  }

  @IsTest
  static void testScenario10() {
    Integer perToken = AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE;
    Decimal blank;
    Decimal exact;
    Decimal rounded;
    Decimal huge;

    Test.startTest();
    blank =
      AIConversationMessageService.estimateTokenCount(null) +
      AIConversationMessageService.estimateTokenCount('  ');
    exact = AIConversationMessageService.estimateTokenCount(
      'x'.repeat(perToken * 3)
    );
    rounded = AIConversationMessageService.estimateTokenCount(
      'x'.repeat(perToken * 3 + 1)
    );
    huge = AIConversationMessageService.estimateTokenCount(
      'x'.repeat(AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS)
    );
    Test.stopTest();

    Assert.areEqual(0, blank, 'Blank is nothing.');
    Assert.areEqual(3, exact, 'An exact multiple.');
    Assert.areEqual(4, rounded, 'One over rounds up.');
    Assert.areEqual(
      Math.ceil(
        AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS /
        (Decimal) perToken
      ),
      huge,
      'The longest allowed message.'
    );
  }
}
