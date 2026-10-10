/*
Class Name: AIConversationLockService

=================================================================
=================================================================

Description: Makes sure only one message per conversation is processed at a time, using AIConversation__c.ProcessingLockedUntil__c.

Step 1: sendMessage takes the lock (acquireLock); if the conversation is busy the new message is saved and waits
Step 2: A starting job checks the lock is still held (isConversationLocked) and stands down if it has expired
Step 3: A finishing job hands the lock to a newer waiting message, or releases it (releaseOrHandOffLock)
Step 4: A scheduled retry keeps the lock for itself (extendLock); a turn that cannot be handed on frees it (releaseLock)

A lock is an expiry time, not a checkbox: while it holds a time in the future the conversation is locked, and blank or
past means free. If a job and its finalizer both fail without releasing it, it expires after
AIAssistSettings__c.ProcessingLockMinutes__c and the next message takes it over.

Every method that changes the lock reads the conversation SELECT ... FOR UPDATE first, which holds the record until the
transaction ends, so two callers cannot change the lock at once. A record held past the platform's wait is reported as
busy rather than failing the user's send with a platform error.

Runs without sharing with explicit system mode on every statement: ProcessingLockedUntil__c is system-managed, and
callers have already authorised the user against the conversation. Throws its own exception without logging; the
caller logs it once.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationLockService {

    public class AIConversationLockServiceException extends Exception {}

    // Locks the conversation if it is free. True when the caller now holds the lock and should start processing; false when another message is already being processed.
    public static Boolean acquireLock(Id conversationId) {

        // [1] Read the conversation and hold its row
        AIConversation__c conversation = lockRow(conversationId);
        if (conversation == null) throw new AIConversationLockServiceException(Label.AI_Error_Conversation_Not_Found);

        // [2] Another message is being processed, so the caller must wait
        if (conversation.ProcessingLockedUntil__c != null && conversation.ProcessingLockedUntil__c > System.now()) return false;

        // [3] Take the lock for the configured time
        setLockedUntil(conversationId, System.now().addMinutes(AIAssistSettingsService.getSettings().ProcessingLockMinutes__c.intValue()));

        return true;
    }

    // Read-only: is the conversation still locked? No row lock is taken, so it is safe to call before a callout.
    public static Boolean isConversationLocked(Id conversationId) {

        // [1] Nothing is locked when the Id is blank or not a conversation
        if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return false;

        // [2] Read the lock
        List<AIConversation__c> conversations = [SELECT ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversationId WITH SYSTEM_MODE LIMIT 1];

        // [3] Locked only when the conversation exists and the lock is in the future
        return !conversations.isEmpty() && conversations[0].ProcessingLockedUntil__c != null && conversations[0].ProcessingLockedUntil__c > System.now();
    }

    // Keeps the conversation locked for a retry: resets the lock to its full time so it cannot expire before the retry has run.
    public static void extendLock(Id conversationId) {

        // [1] Nothing to lock when the conversation is gone
        if (lockRow(conversationId) == null) return;

        // [2] Restart the full lock time
        setLockedUntil(conversationId, System.now().addMinutes(AIAssistSettingsService.getSettings().ProcessingLockMinutes__c.intValue()));
    }

    // Frees the conversation without looking for a waiting message, for a turn that could not be handed on.
    public static void releaseLock(Id conversationId) {

        // [1] Nothing to release when the conversation is gone
        if (lockRow(conversationId) == null) return;

        // [2] A blank time means unlocked
        setLockedUntil(conversationId, null);
    }

    // Called once a message has finished. If the user has sent a newer message since, keeps the lock and returns that message's Id so the caller can process it next. Otherwise releases the lock and returns null.
    public static Id releaseOrHandOffLock(Id conversationId, Id processedMessageId) {

        // [1] Nothing to hand on when the conversation is gone
        if (lockRow(conversationId) == null) return null;

        // [2] Find the newest message the user has sent; if it is not the one just processed, it arrived meanwhile and is waiting
        List<AIConversationMessage__c> newestUserMessages = [SELECT Id FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c = :AIAssistApplicationConstants.SENDER_USER WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 1];

        // [3] Keep the lock for the waiting message and hand it on
        if (!newestUserMessages.isEmpty() && newestUserMessages[0].Id != processedMessageId) {

            setLockedUntil(conversationId, System.now().addMinutes(AIAssistSettingsService.getSettings().ProcessingLockMinutes__c.intValue()));

            return newestUserMessages[0].Id;
        }

        // [4] Nothing is waiting, so release the lock
        setLockedUntil(conversationId, null);

        return null;
    }

    // Reads the conversation with FOR UPDATE, which holds the record until the transaction ends. Null if the Id is blank, not a conversation, or the conversation does not exist.
    private static AIConversation__c lockRow(Id conversationId) {

        // [1] Nothing to read when the Id is blank or not a conversation
        if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) return null;

        try {

            // [2] Read and hold the row so no other transaction can change the lock at the same time
            List<AIConversation__c> conversations = [SELECT Id, ProcessingLockedUntil__c FROM AIConversation__c WHERE Id = :conversationId WITH SYSTEM_MODE LIMIT 1 FOR UPDATE];

            return conversations.isEmpty() ? null : conversations[0];

        } catch (QueryException ex) {
            // [3] Another transaction holds the record past the platform's wait, so the caller can only try again later
            throw new AIConversationLockServiceException(Label.AI_Error_Conversation_Busy);
        }
    }

    // Saves the lock's expiry. Null unlocks the conversation.
    private static void setLockedUntil(Id conversationId, Datetime lockExpiresAt) {

        // [1] Save the new expiry in system mode
        Database.SaveResult saveResult = Database.update(new AIConversation__c(Id = conversationId, ProcessingLockedUntil__c = lockExpiresAt), false, AccessLevel.SYSTEM_MODE);

        // [2] Log the failure and refuse
        if (!saveResult.isSuccess()) {

            AIPlatformLogManager.logCustomMessage('Failed to update the conversation lock for ' + conversationId + ': ' + saveResult.getErrors()[0].getMessage(), null, 'AIConversationLockService', 'lockRow', null);

            throw new AIConversationLockServiceException(Label.AI_Error_Generic);
        }
    }
}
