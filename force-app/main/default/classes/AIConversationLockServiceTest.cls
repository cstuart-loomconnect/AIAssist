/*
Class Name: AIConversationLockServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationLockService: one turn per conversation at a time, lock expiry, retry extension, release and hand-off to a waiting message.

=================================================================
=================================================================
Applicable Classes:

AIConversationLockService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIConversationLockServiceTest {
  // testScenario1: Lock a free conversation twice -> the first caller gets the lock, the second is told it is busy, and the lock lasts the configured minutes.
  // testScenario2: Check and lock a conversation whose lock has expired -> it reads as unlocked and can be taken again.
  // testScenario3: Lock a deleted conversation, a wrong-type Id and a null Id -> each is refused with the not found label.
  // testScenario4: Check, extend, release and hand off a deleted conversation, a wrong-type Id and a null Id -> nothing is locked and nothing is handed on.
  // testScenario5: Extend then release a locked conversation -> the extend restarts the full lock time and the release leaves the lock blank.
  // testScenario6: Hand off after the newest message and after an older one -> the first releases the lock, the second returns the newer message and keeps the lock.
  // testScenario7: Lock 20 conversations in one transaction -> each is locked independently with one query and one update each.

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
    // [1] Create an agent and a conversation
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    )[0];

    // [2] Lock the conversation twice and check whether it is locked
    Boolean first;
    Boolean second;
    Boolean afterLock;

    Test.startTest();
    first = AIConversationLockService.acquireLock(conversation.Id);
    second = AIConversationLockService.acquireLock(conversation.Id);
    afterLock = AIConversationLockService.isConversationLocked(conversation.Id);
    Test.stopTest();

    // [3] Read the lock time
    Datetime lockedUntil = [
      SELECT ProcessingLockedUntil__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ]
    .ProcessingLockedUntil__c;

    // [4] Check the first caller got the lock and the second did not
    Assert.isTrue(first, 'The first caller should take the lock.');
    Assert.isFalse(
      second,
      'The second caller should be told another message is being processed.'
    );
    Assert.isTrue(afterLock, 'The conversation should read as locked.');
    Assert.isTrue(
      lockedUntil >
      System.now()
        .addMinutes(
          AIAssistSettingsService.getSettings()
            .ProcessingLockMinutes__c.intValue() - 1
        ),
      'The lock should last the configured time.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Create an agent and a conversation whose lock has expired
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    )[0];
    conversation.ProcessingLockedUntil__c = System.now().addMinutes(-1);
    update conversation;

    // [2] Check the expired lock, then take the lock again
    Boolean stillLocked;
    Boolean taken;

    Test.startTest();
    stillLocked = AIConversationLockService.isConversationLocked(
      conversation.Id
    );
    taken = AIConversationLockService.acquireLock(conversation.Id);
    Test.stopTest();

    // [3] Check the expired lock reads as unlocked and can be taken
    Assert.isFalse(stillLocked, 'A lock in the past should be no lock.');
    Assert.isTrue(taken, 'An expired lock should be taken again.');
  }

  @IsTest
  static void testScenario3() {
    // [1] Create an agent and delete one of its conversations
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    );
    Id deletedId = conversations[0].Id;
    delete conversations[0];
    List<String> messages = new List<String>();

    // [2] Try to lock the deleted conversation, a wrong-type Id and a null Id
    Test.startTest();
    for (Id badId : new List<Id>{ deletedId, agent.Id, null }) {
      try {
        AIConversationLockService.acquireLock(badId);
      } catch (AIConversationLockService.AIConversationLockServiceException ex) {
        messages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    // [3] Check each Id is refused with the not found label
    Assert.areEqual(3, messages.size(), 'Each bad Id should be refused.');
    Assert.areEqual(
      new Set<String>{ Label.AI_Error_Conversation_Not_Found },
      new Set<String>(messages),
      'The refusal should be the not found Custom Label.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Create an agent and delete one of its conversations
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    );
    Id deletedId = conversations[0].Id;
    delete conversations[0];

    // [2] Check, extend, release and hand off the deleted conversation, a wrong-type Id and a null Id
    Boolean locked;
    Id handedOn;

    Test.startTest();
    locked =
      AIConversationLockService.isConversationLocked(deletedId) ||
      AIConversationLockService.isConversationLocked(agent.Id) ||
      AIConversationLockService.isConversationLocked(null);
    for (Id badId : new List<Id>{ deletedId, agent.Id, null }) {
      AIConversationLockService.extendLock(badId);
      AIConversationLockService.releaseLock(badId);
    }
    handedOn = AIConversationLockService.releaseOrHandOffLock(deletedId, null);
    Test.stopTest();

    // [3] Check nothing is locked and nothing is handed on
    Assert.isFalse(locked, 'None of them should be locked.');
    Assert.isNull(handedOn, 'There should be nothing to hand on.');
  }

  @IsTest
  static void testScenario5() {
    // [1] Create an agent and a conversation locked for 30 seconds
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    )[0];
    conversation.ProcessingLockedUntil__c = System.now().addSeconds(30);
    update conversation;

    // [2] Extend the lock, then release it
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

    // [3] Read the released lock time
    Datetime released = [
      SELECT ProcessingLockedUntil__c
      FROM AIConversation__c
      WHERE Id = :conversation.Id
    ]
    .ProcessingLockedUntil__c;

    // [4] Check the extend restarted the lock time and the release cleared it
    Assert.isTrue(
      extended >
      System.now()
        .addMinutes(
          AIAssistSettingsService.getSettings()
            .ProcessingLockMinutes__c.intValue() - 1
        ),
      'The lock should be reset to its full time.'
    );
    Assert.isFalse(lockedAfterRelease, 'The conversation should be released.');
    Assert.isNull(released, 'A blank value should mean unlocked.');
  }

  @IsTest
  static void testScenario6() {
    // [1] Create an agent, two conversations with messages, and lock both conversations
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    );
    AIConversation__c conversation = conversations[0];
    AIConversation__c second = conversations[1];
    List<AIConversationMessage__c> firstMessages = AIAssistTestDataFactory.createAIConversationMessages(
      conversation.Id,
      AIAssistApplicationConstants.SENDER_USER,
      10,
      1,
      true
    );
    List<AIConversationMessage__c> secondMessages = AIAssistTestDataFactory.createAIConversationMessages(
      second.Id,
      AIAssistApplicationConstants.SENDER_USER,
      10,
      2,
      true
    );
    AIConversationLockService.acquireLock(conversation.Id);
    AIConversationLockService.acquireLock(second.Id);

    // [2] Hand off the lock after the newest message and after an older one
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

    // [3] Read the lock state of both conversations
    Boolean firstLocked = AIConversationLockService.isConversationLocked(
      conversation.Id
    );
    Boolean secondLocked = AIConversationLockService.isConversationLocked(
      second.Id
    );

    // [4] Check the first lock is released and the second is kept for the waiting message
    Assert.isNull(
      nothingWaiting,
      'With no newer message nothing should be handed on.'
    );
    Assert.isFalse(
      firstLocked,
      'The conversation with nothing waiting should be freed.'
    );
    Assert.areEqual(
      secondMessages[1].Id,
      waiting,
      'The newer message should be handed on.'
    );
    Assert.isTrue(
      secondLocked,
      'The lock should be kept for the waiting message.'
    );
  }

  @IsTest
  static void testScenario7() {
    // [1] Create an agent and 200 conversations
    AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      true
    )[0];
    AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(
      1,
      model.Id,
      true
    )[0];
    List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(
      agent.Id,
      null,
      200,
      true
    );

    // [2] Lock 20 conversations in one transaction
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

    // [3] Count the locked conversations
    Integer lockedCount = [
      SELECT COUNT()
      FROM AIConversation__c
      WHERE ProcessingLockedUntil__c != NULL
    ];

    // [4] Check each lock used one query and one update
    Assert.areEqual(20, locked, 'Every free conversation should be locked.');
    Assert.areEqual(
      20,
      queries,
      'There should be one query per lock, no more.'
    );
    Assert.areEqual(20, statements, 'There should be one update per lock.');
    Assert.areEqual(
      20,
      lockedCount,
      'Only the conversations locked should carry a lock.'
    );
  }
}
