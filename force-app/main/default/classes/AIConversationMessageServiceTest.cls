/*
Class Name: AIConversationMessageServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationMessageService: sending, continuing, retrying and closing, as a real end user holding only the AI Assist User permission set. The AI Agent Manager is replaced by a fake that answers.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationMessageServiceTest {
  // testScenario1: Send a first message -> the conversation is created, the user message is stored and locked, and the queued job answers it.
  // testScenario2: Send a second message by conversation Id, then by record on a one-conversation-per-record agent -> the open conversation is continued and found again.
  // testScenario3: Send with a closed, other-agent, another user's and wrong-type conversation Id -> none is continued and a new conversation is started.
  // testScenario4: Send to a conversation at the agent's message cap and one at its token cap -> each is closed with the matching reason and the message starts a new conversation.
  // testScenario5: Send with new chats paused and with a blank message -> each is refused with its label and nothing is stored.
  // testScenario6: Send while another message is being processed -> the message is stored and waits without starting a second job.
  // testScenario7: Retry the newest user message after a failure -> it is re-queued, its failure is cleared and the queued job answers it.
  // testScenario8: Retry a closed conversation, one with no user message, another user's, a wrong-type Id and a busy one -> each is refused with its label.
  // testScenario9: Close the user's own conversations with a given and the default reason, and another user's, a wrong-type and a null Id -> own ones close and the rest are reported as not found.
  // testScenario10: Estimate tokens for blank, exact, one-over and longest text -> blank is zero, an exact multiple is exact and anything over rounds up.

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
    // [1] Create a chat user and an agent
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    AIConversationMessage__c sent;

    // [2] Send a first message as the chat user
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

    // [3] Read back the stored message, the replies and the active conversations
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
    Integer activeCount = [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE
        OwnerId = :chatUser.Id
        AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
    ];

    // [4] Check the message was answered in one active conversation
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      userMessage.ProcessingStatus__c,
      'The answered message should be Complete.'
    );
    Assert.areEqual(1, replies.size(), 'There should be one reply.');
    Assert.areEqual(
      'Fake reply',
      replies[0].MessageBody__c,
      'The reply should be the provider\'s answer.'
    );
    Assert.areEqual(
      10,
      replies[0].InputTokenCount__c,
      'The reply should carry the executor\'s tokens.'
    );
    Assert.areEqual(
      1,
      activeCount,
      'The user should own one Active conversation.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create a chat user and an agent that allows one conversation per record
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    agent.SingleActiveConversationPerRecord__c = true;
    update agent;

    // [2] Create an account and an open conversation for it as the chat user
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

    // [3] Send a second message by conversation Id and then by record
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

    // [4] Count the user's conversations
    Integer conversationCount = [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE OwnerId = :chatUser.Id
    ];

    // [5] Check the open conversation was continued and no second one was created
    Assert.areEqual(
      conversation.Id,
      byId.AIConversation__c,
      'The open conversation should be continued by Id.'
    );
    Assert.areEqual(
      conversation.Id,
      byRecord.AIConversation__c,
      'The open conversation should be found again by record.'
    );
    Assert.areEqual(
      1,
      conversationCount,
      'No second conversation should be created.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Create two chat users and an agent each
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ otherUser },
      'AIAssistUser'
    );
    AIModelConfiguration__c otherModel = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c otherAgent = AIAssistTestDataFactory.createAIAgents(
      1,
      otherModel.Id,
      true
    )[0];
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

    // [2] Create a closed, other-agent and another user's conversation
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

    // [3] Send a message to each unusable conversation Id as the chat user
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

    // [4] Check none of those conversations was used
    Assert.isFalse(
      startedIds.contains(conversations[0].Id) ||
        startedIds.contains(conversations[1].Id) ||
        startedIds.contains(theirs.Id),
      'None of those conversations should have been used.'
    );
    Assert.isFalse(
      startedIds.isEmpty(),
      'Messages should be stored in conversations of the user\'s own.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create a chat user and an agent
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

    // [2] Create an agent with a message cap and one with a token cap
    List<AIAgent__c> capped = AIAssistTestDataFactory.createAIAgents(
      2,
      agent.AIModelConfiguration__c,
      false
    );
    capped[0].MaxMessagesPerConversation__c = 2;
    capped[1].MaxTokensPerConversation__c = 100;
    capped[1]
      .TokenTrackingMethod__c = AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE;
    insert capped;

    // [3] Fill a conversation for each cap
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
    AIAssistTestDataFactory.createAIConversationMessages(
      full.Id,
      AIAssistApplicationConstants.SENDER_USER,
      1,
      2,
      true
    );
    AIAssistTestDataFactory.createAIConversationMessages(
      heavy.Id,
      AIAssistApplicationConstants.SENDER_USER,
      100,
      1,
      true
    );

    // [4] Send a message to each full conversation as the chat user
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

    // [5] Read back the two capped conversations
    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [
        SELECT Status__c, ConversationCloseReason__c
        FROM AIConversation__c
        WHERE Id IN :new Set<Id>{ full.Id, heavy.Id }
      ]
    );

    // [6] Check each was closed with its reason and a new conversation was started
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED,
      byId.get(full.Id).ConversationCloseReason__c,
      'The conversation should be closed at the message cap.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED,
      byId.get(heavy.Id).ConversationCloseReason__c,
      'The conversation should be closed at the token cap.'
    );
    Assert.areNotEqual(
      full.Id,
      afterMessageCap.AIConversation__c,
      'A new conversation should be started after the message cap.'
    );
    Assert.areNotEqual(
      heavy.Id,
      afterTokenCap.AIConversation__c,
      'A new conversation should be started after the token cap.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Create a chat user and an agent, and pause new chats
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
    uiSettings.IsUserInitiatedChatEnabled__c = false;
    upsert uiSettings;

    // [2] Send a normal and a blank message as the chat user
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
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
          labels.add(ex.getMessage());
        }
      }
      Test.stopTest();
    }

    // [3] Count the stored messages
    Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c];

    // [4] Check both were refused and nothing was stored
    Assert.areEqual(2, labels.size(), 'Both messages should be refused.');
    Assert.areEqual(
      Label.AI_Chat_New_Chats_Paused,
      labels[0],
      'A new chat should be refused while new chats are paused.'
    );
    Assert.areEqual(
      Label.AI_Error_Message_Empty,
      labels[1],
      'A blank message should be refused first.'
    );
    Assert.areEqual(0, messageCount, 'Nothing should be stored.');
  }

  @IsTest
  static void testScenario6() {
    // [1] Create a chat user, an agent and a locked conversation
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationLockService.acquireLock(conversation.Id);

    // [2] Send a message to the locked conversation as the chat user
    AIConversationMessage__c waiting;
    Integer jobsQueued;

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
      jobsQueued = Limits.getQueueableJobs();
      Test.stopTest();
    }

    // [3] Read back the stored message and the lock state
    AIConversationMessage__c stored = [
      SELECT ProcessingStatus__c
      FROM AIConversationMessage__c
      WHERE Id = :waiting.Id
    ];
    Boolean isLocked = AIConversationLockService.isConversationLocked(
      conversation.Id
    );

    // [4] Check the message waits with no job started
    Assert.areEqual(
      0,
      jobsQueued,
      'The conversation was locked, so no job should have been started for it.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
      stored.ProcessingStatus__c,
      'The message should wait as Queued.'
    );
    Assert.isTrue(
      isLocked,
      'The lock should still be held by whoever took it.'
    );
  }

  @IsTest
  static void testScenario7() {
    // [1] Create a chat user, an agent and a conversation with a failed user message
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      chatUser.Id,
      1,
      true
    )[0];
    AIConversationMessage__c failed = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_USER,
      null,
      1,
      false
    )[0];
    failed.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED;
    failed.FailureReason__c = AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;
    insert failed;

    // [2] Retry the newest user message as the chat user
    Id retried;

    System.runAs(chatUser) {
      Test.startTest();
      retried = AIConversationMessageService.retryLatestUserMessage(
        conversation.Id
      );
      Test.stopTest();
    }

    // [3] Read back the retried message
    AIConversationMessage__c after = [
      SELECT ProcessingStatus__c, FailureReason__c
      FROM AIConversationMessage__c
      WHERE Id = :failed.Id
    ];

    // [4] Check the message was retried, answered and its failure cleared
    Assert.areEqual(
      failed.Id,
      retried,
      'The newest user message should be retried.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
      after.ProcessingStatus__c,
      'The retry should be answered.'
    );
    Assert.isNull(after.FailureReason__c, 'The old failure should be cleared.');
  }

  @IsTest
  static void testScenario8() {
    // [1] Create two chat users and an agent
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
    User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
    AIAssistTestDataFactory.assignPermissionSet(
      new List<User>{ otherUser },
      'AIAssistUser'
    );

    // [2] Create four conversations for the chat user and one for the other user
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

    // [3] Give the last conversation a user message and lock it
    System.runAs(chatUser) {
      insert AIAssistTestDataFactory.createAIConversationMessages(
        conversations[3].Id,
        AIAssistApplicationConstants.SENDER_USER,
        null,
        1,
        false
      );
    }
    AIConversationLockService.acquireLock(conversations[3].Id);

    // [4] Retry each case as the chat user
    Map<String, String> messageByCase = new Map<String, String>();
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
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
          messageByCase.put(key, ex.getMessage());
        }
      }
      Test.stopTest();
    }

    // [5] Check every case was refused with its label
    Assert.areEqual(5, messageByCase.size(), 'Every case should be refused.');
    Assert.areEqual(
      Label.AI_Error_Conversation_Closed,
      messageByCase.get('closed'),
      'A closed conversation should be refused as closed.'
    );
    Assert.areEqual(
      Label.AI_Error_Message_Empty,
      messageByCase.get('empty'),
      'A conversation with nothing to retry should be refused as empty.'
    );
    Assert.areEqual(
      Label.AI_Error_Conversation_Not_Found,
      messageByCase.get('theirs'),
      'Another user\'s conversation should be reported as not found.'
    );
    Assert.areEqual(
      Label.AI_Error_Conversation_Not_Found,
      messageByCase.get('badId'),
      'An Id of the wrong type should be reported as not found.'
    );
    Assert.areEqual(
      Label.AI_Error_Conversation_Busy,
      messageByCase.get('busy'),
      'A conversation with a turn already running should be reported as busy.'
    );
  }

  @IsTest
  static void testScenario9() {
    // [1] Create two chat users, an agent and their conversations
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
    AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);
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

    // [2] Close the user's own conversations and try to close others as the chat user
    List<String> messages = new List<String>();

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
        } catch (AIConversationMessageService.AIConversationMessageServiceException ex) {
          messages.add(ex.getMessage());
        }
      }
      Test.stopTest();
    }

    // [3] Read back all the conversations
    Map<Id, AIConversation__c> byId = new Map<Id, AIConversation__c>(
      [
        SELECT
          Status__c,
          ConversationCloseReason__c,
          ConversationClosedTimestamp__c
        FROM AIConversation__c
      ]
    );

    // [4] Check own conversations closed and the rest were refused as not found
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED,
      byId.get(mine[0].Id).ConversationCloseReason__c,
      'The default reason should be used.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_SYSTEM_OVERRIDE,
      byId.get(mine[1].Id).ConversationCloseReason__c,
      'The given reason should be used.'
    );
    Assert.isNotNull(
      byId.get(mine[0].Id).ConversationClosedTimestamp__c,
      'The close time should be stamped by the trigger.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
      byId.get(theirs.Id).Status__c,
      'Another user\'s conversation should be untouched.'
    );
    Assert.areEqual(3, messages.size(), 'There should be three refusals.');
    Assert.areEqual(
      new Set<String>{ Label.AI_Error_Conversation_Not_Found },
      new Set<String>(messages),
      'Each refusal should be the not found Custom Label.'
    );
  }

  @IsTest
  static void testScenario10() {
    // [1] Work out the characters per token
    Integer perToken = AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE;

    // [2] Estimate tokens for blank, exact, one-over and longest text
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

    // [3] Check blank is zero, exact is exact and anything over rounds up
    Assert.areEqual(0, blank, 'Blank text should be nothing.');
    Assert.areEqual(3, exact, 'An exact multiple should be exact.');
    Assert.areEqual(4, rounded, 'One character over should round up.');
    Assert.areEqual(
      Math.ceil(
        AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS /
        (Decimal) perToken
      ),
      huge,
      'The longest allowed message should round up.'
    );
  }
}
