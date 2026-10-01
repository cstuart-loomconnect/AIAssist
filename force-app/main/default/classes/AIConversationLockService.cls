/*
Class Name: AIConversationLockService

=================================================================
=================================================================

Description: Makes sure only one message per conversation is processed at a time. The lock is
AIConversation__c.ProcessingLockedUntil__c: while it holds a time in the future the conversation
is locked; blank or past, it is free.

Why: if two AIMessageProcessingQueueable jobs ran on one conversation at once, each would build
its own history (so replies arrive out of order), both would try to create the conversation's
AIPIIMapping__c, and both would add to ConversationTokenUsage__c.

How it works:
[1] sendMessage calls lock. If the conversation is free it is locked and a job is enqueued. If
    not, the new message is saved but no job is enqueued: it waits.
[2] When a job starts it calls isLocked. A job that sat in a busy org's queue for longer than the
    lock lasts finds it expired and stands down rather than run beside whatever took over.
[3] When a job ends, the finalizer calls handOff. If the user sent a newer message meanwhile, the
    lock is kept and that message's Id is returned so the finalizer can start it. Otherwise the
    lock is released.
[4] When a retry is scheduled, the finalizer calls extend so new messages keep waiting behind it.

The lock cannot get stuck: it is an expiry time, not a checkbox. If a job and its finalizer both
fail without releasing it, it expires after AIAssistSettings__c.ProcessingLockMinutes__c and the
next message takes it over.

Every method that changes the lock reads the conversation SELECT ... FOR UPDATE first, which
holds the record until the transaction ends. So lock and handOff cannot run at once on the same
conversation: a message sent just as a job finishes is either seen by the finalizer or finds the
lock already released. A record that stays locked past the platform's wait is reported as busy
rather than failing the user's send with a platform error.

`without sharing` with explicit system mode on every statement: ProcessingLockedUntil__c is
system-managed and not even readable by the AI Assist User permission set. Callers have already
authorised the user against the conversation; this class only ever touches the lock.

Throws AIMessagingException without logging; the caller logs it once.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt: AIMessagingException, explicit system mode, lock row busy reported as a refusal, isLocked and release added, methods renamed (lock, isLocked, extend, release, handOff).
*/

public without sharing class AIConversationLockService {
  // Locks the conversation if it is free. True when the caller now holds the lock and should start processing; false when another message is already being processed.
  public static Boolean acquireLock(Id conversationId) {
    AIConversation__c conversation = lockRow(conversationId);
    if (conversation == null)
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
        Label.AI_Error_Conversation_Not_Found
      );

    if (
      conversation.ProcessingLockedUntil__c != null &&
      conversation.ProcessingLockedUntil__c > System.now()
    )
      return false;

    setLockedUntil(
      conversationId,
      System.now()
        .addMinutes(AIAssistSettingsService.getProcessingLockMinutes())
    );
    return true;
  }

  // Read-only: is the conversation still locked? No row lock is taken, so it is safe to call before a callout.
  public static Boolean isConversationLocked(Id conversationId) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      return false;

    List<AIConversation__c> conversations = [
      SELECT ProcessingLockedUntil__c
      FROM AIConversation__c
      WHERE Id = :conversationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return !conversations.isEmpty() &&
      conversations[0].ProcessingLockedUntil__c != null &&
      conversations[0].ProcessingLockedUntil__c > System.now();
  }

  // Keeps the conversation locked for a retry: resets the lock to its full time so it cannot expire before the retry has run.
  public static void extendLock(Id conversationId) {
    if (lockRow(conversationId) == null)
      return; // Deleted: nothing to lock.

    setLockedUntil(
      conversationId,
      System.now()
        .addMinutes(AIAssistSettingsService.getProcessingLockMinutes())
    );
  }

  // Frees the conversation without looking for a waiting message, for a turn that could not be handed on.
  public static void releaseLock(Id conversationId) {
    if (lockRow(conversationId) == null)
      return; // Deleted: nothing to release.

    setLockedUntil(conversationId, null);
  }

  // Called once a message has finished. If the user has sent a newer message since, keeps the lock and returns that message's Id so the caller can process it next. Otherwise releases the lock and returns null.
  public static Id releaseOrHandOffLock(
    Id conversationId,
    Id processedMessageId
  ) {
    if (lockRow(conversationId) == null)
      return null; // Deleted: nothing to hand on.

    // The newest message the user has sent. If it is not the one just processed, it arrived while that one ran and is waiting.
    List<AIConversationMessage__c> newestUserMessages = [
      SELECT Id
      FROM AIConversationMessage__c
      WHERE
        AIConversation__c = :conversationId
        AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC, Id DESC
      LIMIT 1
    ];

    if (
      !newestUserMessages.isEmpty() &&
      newestUserMessages[0].Id != processedMessageId
    ) {
      setLockedUntil(
        conversationId,
        System.now()
          .addMinutes(AIAssistSettingsService.getProcessingLockMinutes())
      );
      return newestUserMessages[0].Id;
    }

    setLockedUntil(conversationId, null); // Blank is unlocked.
    return null;
  }

  // FOR UPDATE holds the record until the transaction ends, so no other transaction can read and change the lock at the same time. Null if the Id is blank, not a conversation, or the conversation does not exist.
  private static AIConversation__c lockRow(Id conversationId) {
    if (
      conversationId == null ||
      conversationId.getSobjectType() != AIConversation__c.SObjectType
    )
      return null;

    try {
      List<AIConversation__c> conversations = [
        SELECT Id, ProcessingLockedUntil__c
        FROM AIConversation__c
        WHERE Id = :conversationId
        WITH SYSTEM_MODE
        LIMIT 1
        FOR UPDATE
      ];
      return conversations.isEmpty() ? null : conversations[0];
    } catch (QueryException lockWaitException) {
      // Another transaction holds the record past the platform's wait. The caller can only try again later.
      throw AIMessagingException.newRefusal(
        AIAssistApplicationConstants.ERROR_CONVERSATION_BUSY,
        Label.AI_Error_Conversation_Busy
      );
    }
  }

  // Saves the lock's expiry. Null unlocks the conversation.
  private static void setLockedUntil(
    Id conversationId,
    Datetime lockExpiresAt
  ) {
    Database.SaveResult saveResult = Database.update(
      new AIConversation__c(
        Id = conversationId,
        ProcessingLockedUntil__c = lockExpiresAt
      ),
      false,
      AccessLevel.SYSTEM_MODE
    );

    if (!saveResult.isSuccess())
      throw AIMessagingException.newFailure(
        'Failed to update the conversation lock for ' +
          conversationId +
          ': ' +
          saveResult.getErrors()[0].getMessage(),
        null
      );
  }
}
