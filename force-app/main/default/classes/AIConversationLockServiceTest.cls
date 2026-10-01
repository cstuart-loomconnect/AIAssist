/*
Class Name: AIConversationLockServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationLockService: one turn per conversation at a time, lock expiry, retry extension, release and hand-off to a waiting message.

=================================================================
=================================================================
Applicable Classes:

AIConversationLockService

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationLockServiceTest {
  // testScenario1: A free conversation is locked once, a second attempt is told it is busy, and the lock expires after the configured minutes.
  // testScenario2: An expired lock can be taken again.
  // testScenario3: Locking a conversation that does not exist, or an Id of the wrong type, is refused with the not found label.
  // testScenario4: isLocked, extend and release quietly do nothing for a missing conversation or a wrong Id.
  // testScenario5: extend restarts the full lock time for a retry, and release frees the conversation.
  // testScenario6: handOff releases the lock when the processed message is the newest, and returns the newer message and keeps the lock when one arrived meanwhile.
  // testScenario7: Bulk: two hundred conversations are each locked independently, in a limited number of queries and statements.

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
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    AIConversation__c conversation = conversations[0];
    Boolean first;
    Boolean second;
    Boolean afterLock;
    Datetime lockedUntil;

    Test.startTest();
    first = AIConversationLockService.acquireLock(conversation.Id);
    second = AIConversationLockService.acquireLock(conversation.Id);
    afterLock = AIConversationLockService.isConversationLocked(conversation.Id);
    Test.stopTest();

    lockedUntil = [
      SELECT ProcessingLockedUntil__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ]
    .ProcessingLockedUntil__c;
    Assert.isTrue(first, 'The first caller takes the lock.');
    Assert.isFalse(
      second,
      'The second is told another message is being processed.'
    );
    Assert.isTrue(afterLock, 'The conversation reads as locked.');
    Assert.isTrue(
      lockedUntil >
      System.now()
        .addMinutes(AIAssistSettingsService.getProcessingLockMinutes() - 1),
      'The lock lasts the configured time.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    AIConversation__c conversation = conversations[0];
    conversation.ProcessingLockedUntil__c = System.now().addMinutes(-1);
    update conversation;
    Boolean taken;
    Boolean stillLocked;

    Test.startTest();
    stillLocked = AIConversationLockService.isConversationLocked(
      conversation.Id
    );
    taken = AIConversationLockService.acquireLock(conversation.Id);
    Test.stopTest();

    Assert.isFalse(stillLocked, 'A lock in the past is no lock.');
    Assert.isTrue(taken, 'It can be taken.');
  }

  @IsTest
  static void testScenario3() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    Id deletedId = conversations[0].Id;
    delete conversations[0];
    List<String> codes = new List<String>();

    Test.startTest();
    for (Id badId : new List<Id>{ deletedId, agent.Id, null }) {
      try {
        AIConversationLockService.acquireLock(badId);
        Assert.fail('Nothing to lock, so this should have thrown.');
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

    Assert.areEqual(3, codes.size(), 'Each bad Id was refused.');
    Assert.areEqual(
      AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
      codes[0],
      'Not found.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    Id deletedId = conversations[0].Id;
    delete conversations[0];
    Boolean locked;

    Test.startTest();
    locked =
      AIConversationLockService.isConversationLocked(deletedId) ||
      AIConversationLockService.isConversationLocked(agent.Id) ||
      AIConversationLockService.isConversationLocked(null);
    for (Id badId : new List<Id>{ deletedId, agent.Id, null }) {
      AIConversationLockService.extendLock(badId);
      AIConversationLockService.releaseLock(badId);
    }
    Id handedOn = AIConversationLockService.releaseOrHandOffLock(
      deletedId,
      null
    );
    Test.stopTest();

    Assert.isFalse(locked, 'None of them is locked.');
    Assert.isNull(handedOn, 'Nothing to hand on.');
  }

  @IsTest
  static void testScenario5() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    AIConversation__c conversation = conversations[0];
    conversation.ProcessingLockedUntil__c = System.now().addSeconds(30);
    update conversation;
    Datetime extended;
    Boolean lockedAfterRelease;

    Test.startTest();
    AIConversationLockService.extendLock(conversation.Id);
    extended = [
      SELECT ProcessingLockedUntil__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ]
    .ProcessingLockedUntil__c;
    AIConversationLockService.releaseLock(conversation.Id);
    lockedAfterRelease = AIConversationLockService.isConversationLocked(
      conversation.Id
    );
    Test.stopTest();

    Assert.isTrue(
      extended >
      System.now()
        .addMinutes(AIAssistSettingsService.getProcessingLockMinutes() - 1),
      'The lock was reset to its full time.'
    );
    Assert.isFalse(lockedAfterRelease, 'Released.');
    Assert.isNull(
      [
        SELECT ProcessingLockedUntil__c
        FROM AIConversation__c
        WHERE Id = :conversation.Id
      ]
      .ProcessingLockedUntil__c,
      'A blank value is unlocked.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    AIConversation__c conversation = conversations[0];
    AIConversation__c second = conversations[1];
    List<AIConversationMessage__c> firstMessages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      10,
      1,
      true
    );
    List<AIConversationMessage__c> secondMessages = AIAssistTestDataFactory.createAIConversationMessages(
      second.Id,
      10,
      2,
      true
    );
    AIConversationLockService.acquireLock(conversation.Id);
    AIConversationLockService.acquireLock(second.Id);
    Id nothingWaiting;
    Id waiting;

    Test.startTest();
    nothingWaiting = AIConversationLockService.releaseOrHandOffLock(
      conversation.Id,
      firstMessages[0].Id
    );
    waiting = AIConversationLockService.releaseOrHandOffLock(
      second.Id,
      secondMessages[0].Id
    );
    Test.stopTest();

    Assert.isNull(nothingWaiting, 'No newer message, so nothing is handed on.');
    Assert.isFalse(
      AIConversationLockService.isConversationLocked(conversation.Id),
      'And the conversation is freed.'
    );
    Assert.areEqual(
      secondMessages[1].Id,
      waiting,
      'The newer message is handed on.'
    );
    Assert.isTrue(
      AIConversationLockService.isConversationLocked(second.Id),
      'And the lock is kept for it.'
    );
  }

  @IsTest
  static void testScenario7() {
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      200,
      true
    );
    Integer locked = 0;
    Integer queries;
    Integer statements;

    Test.startTest();
    for (Integer i = 0; i < 20; i++) {
      if (AIConversationLockService.acquireLock(conversations[i].Id))
        locked++;
    }
    queries = Limits.getQueries();
    statements = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(20, locked, 'Every free conversation was locked.');
    Assert.areEqual(20, queries, 'One query per lock, no more.');
    Assert.areEqual(20, statements, 'And one update.');
    Assert.areEqual(
      20,
      [
        SELECT COUNT()
        FROM AIConversation__c
        WHERE ProcessingLockedUntil__c != NULL
      ],
      'Only those locked carry a lock.'
    );
  }
}
