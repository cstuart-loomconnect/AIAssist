/*
Class Name: AIConversationMessageService

=================================================================
=================================================================

Description: The entry point for a user sending a message: what the chat UI calls. Never talks to the AI provider; that is handed off entirely to the asynchronous job.

Step 1: Check the request is allowed (AIMessageValidator)
Step 2: Find an Active conversation to reuse, or start a new one, closing an existing one first if it hit the agent's message or token cap
Step 3: Check the usage limits (AIUsageLimitService)
Step 4: Take the conversation's processing lock, insert the user's message and enqueue AIMessageProcessingQueueable, only if the lock was free

Also owns retrying the newest message, manually closing a conversation (distinct from the idle and retention jobs' automated closing),
and starting or failing messages held at the cap on messages in flight.

Authorises as the user even though the class is declared without sharing: a conversation is only ever found or changed with a
user-mode statement, so a user reaches only their own (conversations are Private) and only fields the AI Assist User
permission set can set. What the user may not write themselves (the message's token estimate and processing status)
goes through AIMessagingDataService, after those checks.

Every refusal is an exception whose message is a Custom Label; the UI shows it, not its text. An unexpected failure reaches
the caller as the generic label and is logged in full.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIConversationMessageService {

    public class AIConversationMessageServiceException extends Exception {}

    // Validates the request, finds or creates the Active conversation, inserts the user's message, and enqueues the asynchronous turn. Returns the inserted message.
    public static AIConversationMessage__c sendMessage(Id agentId, String messageBody, String channel, String relatedObjectApiName, Id relatedRecordId) {

        // [1] Send without naming a conversation
        return sendMessage(null, agentId, messageBody, channel, relatedObjectApiName, relatedRecordId);
    }

    // As above, but continues conversationId when it is still Active, the user's own and on the same agent: the chat window passes the one it has open. Anything else (blank, closed, over its caps) starts a new conversation, so check the returned message's AIConversation__c.
    public static AIConversationMessage__c sendMessage(Id conversationId, Id agentId, String messageBody, String channel, String relatedObjectApiName, Id relatedRecordId) {

        // [1] Send without asking for a prompt template
        return sendMessage(conversationId, agentId, messageBody, channel, relatedObjectApiName, relatedRecordId, null);
    }

    // As above, and answers the message with promptTemplateId, one of the agent's active Prompt Templates, instead of the agent's default (a slash command's template arrives this way). A blank Id, or one that is no longer active on the agent when the turn runs, leaves the choice to the default and the model.
    public static AIConversationMessage__c sendMessage(Id conversationId, Id agentId, String messageBody, String channel, String relatedObjectApiName, Id relatedRecordId, Id promptTemplateId) {

        try {

            // [1] Check the request is allowed
            AIMessageValidator.ChatContext chatContext = AIMessageValidator.validateSendRequest(agentId, messageBody, channel, relatedObjectApiName, relatedRecordId);
            Decimal estimatedTokens = estimateTokenCount(messageBody);

            // [2] Count the estimate against the limits only where the agent asked for it: a "track" agent is measured by the provider after the call
            Decimal tokensCountedForLimits = chatContext.agent.TokenTrackingMethod__c == AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE || chatContext.agent.TokenTrackingMethod__c == AIAssistApplicationConstants.TRACKING_METHOD_PRE_REQUEST_CHECK ? estimatedTokens : 0;

            // [3] Find the conversation to continue in user mode: by Id when the chat window passed one, otherwise by record when the agent keeps one conversation per record
            List<AIConversation__c> candidateConversations = new List<AIConversation__c>();

            if (conversationId != null && conversationId.getSobjectType() == AIConversation__c.SObjectType) {

                candidateConversations = [SELECT Id, MessageCount__c, ConversationTokenUsage__c FROM AIConversation__c WHERE Id = :conversationId AND AIAgent__c = :chatContext.agent.Id AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE AND OwnerId = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
            } else if (conversationId == null && chatContext.agent.SingleActiveConversationPerRecord__c == true && relatedRecordId != null) {

                candidateConversations = [SELECT Id, MessageCount__c, ConversationTokenUsage__c FROM AIConversation__c WHERE AIAgent__c = :chatContext.agent.Id AND RelatedRecordId__c = :String.valueOf(relatedRecordId) AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE AND OwnerId = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
            }

            AIConversation__c conversation = candidateConversations.isEmpty() ? null : candidateConversations[0];

            // [4] Close a conversation at the agent's message or token cap, with the matching reason, so the user starts a fresh one instead of being blocked
            if (conversation != null) {

                Decimal tokensUsed = conversation.ConversationTokenUsage__c == null ? 0 : conversation.ConversationTokenUsage__c;

                if (chatContext.agent.MaxMessagesPerConversation__c != null && conversation.MessageCount__c != null && conversation.MessageCount__c >= chatContext.agent.MaxMessagesPerConversation__c) {

                    Database.SaveResult messageLimitCloseResult = Database.update(new AIConversation__c(Id = conversation.Id, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED), false, AccessLevel.USER_MODE);

                    // A failure is reported as "not found", which reveals nothing about what exists
                    if (!messageLimitCloseResult.isSuccess()) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

                    conversation = null;
                } else if (chatContext.agent.MaxTokensPerConversation__c != null && tokensUsed + tokensCountedForLimits >= chatContext.agent.MaxTokensPerConversation__c) {

                    Database.SaveResult tokenLimitCloseResult = Database.update(new AIConversation__c(Id = conversation.Id, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED), false, AccessLevel.USER_MODE);

                    if (!tokenLimitCloseResult.isSuccess()) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

                    conversation = null;
                }
            }

            // [5] Refuse a new conversation while new chats are paused
            Boolean isNewConversation = conversation == null;

            if (isNewConversation && chatContext.userSettings != null && chatContext.userSettings.IsUserInitiatedChatEnabled__c == false) throw new AIConversationMessageServiceException(Label.AI_Chat_New_Chats_Paused);

            // [6] Check the usage limits
            AIUsageLimitService.enforceUsageLimits(chatContext, isNewConversation);

            if (isNewConversation) {

                // [7] Create the new conversation in user mode, as the user's own: only fields the AI Assist User permission set can set
                conversation = new AIConversation__c(AIAgent__c = chatContext.agent.Id, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE, Channel__c = channel, RelatedObjectAPIName__c = relatedObjectApiName, RelatedRecordId__c = relatedRecordId == null ? null : String.valueOf(relatedRecordId));

                Database.SaveResult conversationResult = Database.insert(conversation, false, AccessLevel.USER_MODE);

                if (!conversationResult.isSuccess()) {

                    AIPlatformLogManager.logCustomMessage('Failed to create conversation: ' + conversationResult.getErrors()[0].getStatusCode() + ' ' + conversationResult.getErrors()[0].getMessage(), null, 'AIConversationMessageService', 'sendMessage', null);

                    throw new AIConversationMessageServiceException(Label.AI_Error_Generic);
                }
            }

            // [8] Take the lock before the message is inserted, so a job finishing at the same moment either sees this message or finds the lock already released
            Boolean shouldStartProcessing = AIConversationLockService.acquireLock(conversation.Id);

            // [9] At the org-wide cap on messages in flight, keep the message Queued and start it when a place is free (startHeldMessage)
            Boolean isHeld = shouldStartProcessing && AIUsageLimitService.isInFlightCapReached();

            // [10] Build and insert the user's message
            AIConversationMessage__c userMessage = new AIConversationMessage__c(AIConversation__c = conversation.Id, Sender__c = AIAssistApplicationConstants.SENDER_USER, MessageBody__c = messageBody, AIPromptTemplate__c = promptTemplateId, ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, IsAwaitingCapacity__c = isHeld, TokenCount__c = chatContext.agent.TokenTrackingMethod__c == AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE ? estimatedTokens : null);

            AIMessagingDataService.insertOrThrow(new List<SObject>{ userMessage });

            // [11] Start the turn only when this message took the lock; otherwise it waits and the running job's finalizer starts it
            if (isHeld) AIConversationLockService.releaseLock(conversation.Id);
            else if (shouldStartProcessing) System.enqueueJob(new AIMessageProcessingQueueable(userMessage.Id, conversation.Id));

            return userMessage;

        } catch (Exception ex) {
            // [12] A package exception already carries a Custom Label and was logged where it was thrown, so pass it on
            if (!ex.getTypeName().startsWith('System.')) throw ex;

            // [13] Log anything else here and give the caller the generic label
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'sendMessage');
            AIPlatformLogManager.logCustomMessage(ex.getMessage(), null, 'AIConversationMessageService', 'sendMessage', null);

            throw new AIConversationMessageServiceException(Label.AI_Error_Generic, ex);
        }
    }

    // Fails every message, whoever sent it, that has waited longer than HELD_MESSAGE_TIMEOUT_MINUTES for a place under the cap on messages in flight, so its sender is offered Try again instead of a wait that never ends: only the sender can start a held message, and they may have closed the window. Returns how many were failed. isRecentOnly looks at the last day alone, which is what a finalizer or a chat window can afford; the maintenance job looks at them all. Never throws.
    public static Integer failExpiredHeldMessages(Boolean isRecentOnly) {

        try {

            // [1] Work out how long a message may wait
            Datetime heldBefore = System.now().addMinutes(-AIAssistApplicationConstants.HELD_MESSAGE_TIMEOUT_MINUTES);
            List<AIConversationMessage__c> failedMessages = new List<AIConversationMessage__c>();
            Set<Id> conversationIds = new Set<Id>();

            for (AIConversationMessage__c heldMessage : lockExpiredHeldMessages(heldBefore, isRecentOnly ? heldBefore.addDays(-1) : null, AIAssistApplicationConstants.HELD_MESSAGE_SWEEP_SIZE)) {

                // [2] Skip a message its sender started while this waited for the lock
                if (!heldMessage.IsAwaitingCapacity__c || heldMessage.ProcessingStatus__c != AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED) continue;

                // [3] Fail the message as the service being busy
                failedMessages.add(new AIConversationMessage__c(Id = heldMessage.Id, ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, FailureReason__c = AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY, IsAwaitingCapacity__c = false));
                conversationIds.add(heldMessage.AIConversation__c);
            }

            // [4] Save the failures, logging any that do not save
            AIMessagingDataService.updateAndLogFailures(failedMessages, 'AIConversationMessageService', 'failExpiredHeldMessages');

            // [5] Tell each affected conversation its message failed
            for (Id conversationId : conversationIds) AIMessageOutcomeService.publishMessageFailure(conversationId, AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY);

            return failedMessages.size();

        } catch (Exception ex) {
            // [6] Log it and report that nothing was failed
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'failExpiredHeldMessages');

            return 0;
        }
    }

    // True when the signed-in user has a message in this conversation waiting for a place under the cap on messages in flight. The chat window asks this on every update, so it is one indexed read and nothing else: startHeldMessage and its sweep of every user's expired messages run only for a window that has something to start.
    public static Boolean hasHeldMessage(Id conversationId) {

        return ![SELECT Id FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND IsAwaitingCapacity__c = TRUE AND ProcessingStatus__c = :AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED AND CreatedById = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    // Starts the signed-in user's oldest message that is waiting for a place under the cap on messages in flight, if a place is free. True when one was started. A job runs as whoever queues it and reads the conversation in user mode, so a waiting message can only be started by its own sender: from the finalizer of that user's earlier turn, or from their chat window asking for an update. Any user's finalizer or window first fails the messages that have waited too long (failExpiredHeldMessages), which are then no longer started. Never throws.
    public static Boolean startHeldMessage() {

        // [1] Fail the messages that have waited too long first
        failExpiredHeldMessages(true);

        Savepoint beforeStart;

        try {

            // [2] Find the user's oldest message still waiting
            Datetime heldSince = System.now().addMinutes(-AIAssistApplicationConstants.HELD_MESSAGE_TIMEOUT_MINUTES);
            List<AIConversationMessage__c> heldMessages = [SELECT Id, AIConversation__c FROM AIConversationMessage__c WHERE IsAwaitingCapacity__c = TRUE AND ProcessingStatus__c = :AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED AND CreatedById = :UserInfo.getUserId() AND CreatedDate >= :heldSince WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC LIMIT 1];

            // [3] Do nothing when there is none, no job can be queued, the cap is still reached, or the conversation is locked
            if (heldMessages.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs() || AIUsageLimitService.isInFlightCapReached() || !AIConversationLockService.acquireLock(heldMessages[0].AIConversation__c)) return false;

            // [4] Free the lock and take it again after the savepoint, so that if the job cannot be queued the message goes back to waiting with no lock left on its conversation
            AIConversationLockService.releaseLock(heldMessages[0].AIConversation__c);
            beforeStart = Database.setSavepoint();
            AIConversationLockService.acquireLock(heldMessages[0].AIConversation__c);

            // [5] Stop the message waiting and queue its turn
            AIMessagingDataService.updateOrThrow(new List<SObject>{ new AIConversationMessage__c(Id = heldMessages[0].Id, IsAwaitingCapacity__c = false) });
            System.enqueueJob(new AIMessageProcessingQueueable(heldMessages[0].Id, heldMessages[0].AIConversation__c));

            return true;

        } catch (Exception ex) {
            // [6] Roll back to the savepoint, log it and report that nothing was started
            if (beforeStart != null) Database.rollback(beforeStart);

            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'startHeldMessage');

            return false;
        }
    }

    // Re-runs the AI response for the conversation's newest user message: Try again after a failed turn, and Regenerate. Only the newest can be re-run, because the finalizer hands the lock to the newest user message and re-running an older one would answer the newest twice. Returns the message's Id.
    public static Id retryLatestUserMessage(Id conversationId) {

        try {

            // [1] Refuse a blank or wrong-type Id as not found
            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

            // [2] Find the user's own conversation in user mode, so sharing and field-level security apply
            List<AIConversation__c> ownConversations = [SELECT Id, Status__c, AIAgent__c, Channel__c, RelatedObjectAPIName__c, RelatedRecordId__c FROM AIConversation__c WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];

            // [3] Anything else (missing, someone else's, not visible) is not found
            if (ownConversations.isEmpty()) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

            // [4] Refuse a conversation that is no longer Active
            AIConversation__c conversation = ownConversations[0];

            if (conversation.Status__c != AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Closed);

            // [5] Find the newest message the user sent
            List<AIConversationMessage__c> newestUserMessages = [SELECT Id, MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversationId AND Sender__c = :AIAssistApplicationConstants.SENDER_USER WITH USER_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 1];

            if (newestUserMessages.isEmpty()) throw new AIConversationMessageServiceException(Label.AI_Error_Message_Empty);

            // [6] Pass every check a new message does, as a retry spends tokens and reads the record again: the agent may have been unassigned or the record shared away since the first attempt
            AIMessageValidator.ChatContext chatContext = AIMessageValidator.validateSendRequest(conversation.AIAgent__c, newestUserMessages[0].MessageBody__c, conversation.Channel__c, conversation.RelatedObjectAPIName__c, String.isBlank(conversation.RelatedRecordId__c) ? null : Id.valueOf(conversation.RelatedRecordId__c));
            AIUsageLimitService.enforceUsageLimits(chatContext, false);

            // [7] Refuse when another turn is already running
            if (!AIConversationLockService.acquireLock(conversationId)) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Busy);

            // [8] Queue the message again and clear its failure
            AIMessagingDataService.updateOrThrow(new List<SObject>{ new AIConversationMessage__c(Id = newestUserMessages[0].Id, ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, FailureReason__c = null) });

            // [9] Start the turn
            System.enqueueJob(new AIMessageProcessingQueueable(newestUserMessages[0].Id, conversationId));

            return newestUserMessages[0].Id;

        } catch (Exception ex) {
            // [10] A package exception already carries a Custom Label and was logged where it was thrown, so pass it on
            if (!ex.getTypeName().startsWith('System.')) throw ex;

            // [11] Log anything else here and give the caller the generic label
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'retryLatestUserMessage');
            AIPlatformLogManager.logCustomMessage(ex.getMessage(), null, 'AIConversationMessageService', 'retryLatestUserMessage', null);

            throw new AIConversationMessageServiceException(Label.AI_Error_Generic, ex);
        }
    }

    // Manually ends a conversation, distinct from the idle and retention jobs' automated closing. Only someone who can edit the conversation can close it: the update runs in user mode.
    public static void closeConversation(Id conversationId, String closeReason) {

        try {

            // [1] Refuse a blank or wrong-type Id as not found
            if (conversationId == null || conversationId.getSobjectType() != AIConversation__c.SObjectType) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

            // [2] Find the user's own conversation in user mode
            List<AIConversation__c> closableConversations = [SELECT Id, Status__c, AIAgent__c, Channel__c, RelatedObjectAPIName__c, RelatedRecordId__c FROM AIConversation__c WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];

            // [3] Not found, or not visible to this user, is reported the same way
            if (closableConversations.isEmpty()) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

            // [4] Close it with the given reason, or the default
            Database.SaveResult closeResult = Database.update(new AIConversation__c(Id = conversationId, Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED, ConversationCloseReason__c = String.isBlank(closeReason) ? AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED : closeReason), false, AccessLevel.USER_MODE);

            if (!closeResult.isSuccess()) throw new AIConversationMessageServiceException(Label.AI_Error_Conversation_Not_Found);

        } catch (Exception ex) {
            // [5] A package exception already carries a Custom Label and was logged where it was thrown, so pass it on
            if (!ex.getTypeName().startsWith('System.')) throw ex;

            // [6] Log anything else here and give the caller the generic label
            AIPlatformLogManager.logException(ex, 'AIConversationMessageService', 'closeConversation');
            AIPlatformLogManager.logCustomMessage(ex.getMessage(), null, 'AIConversationMessageService', 'closeConversation', null);

            throw new AIConversationMessageServiceException(Label.AI_Error_Generic, ex);
        }
    }

    // A rough, cheap estimate (about four characters per token) for the limits; the provider's own count is only known after the callout.
    public static Decimal estimateTokenCount(String text) {

        // [1] Blank text is nothing; otherwise round up
        return String.isBlank(text) ? 0 : Math.ceil(text.length() / (Decimal) AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE);
    }

    // Gets the messages still held at the cap on messages in flight that were sent before heldBefore, whoever sent them. heldSince, when given, keeps the query to a range of the CreatedDate index. Locked and read again by the caller's check, so one its sender is starting at this moment is seen as it ends up.
    @TestVisible
    private static List<AIConversationMessage__c> lockExpiredHeldMessages(Datetime heldBefore, Datetime heldSince, Integer maximum) {

        // [1] Start from the given time, or from a date before any message
        Datetime earliest = heldSince == null ? Datetime.newInstanceGmt(2000, 1, 1) : heldSince;

        // [2] Read and lock the messages of every user, in system mode
        return [SELECT Id, AIConversation__c, IsAwaitingCapacity__c, ProcessingStatus__c FROM AIConversationMessage__c WHERE IsAwaitingCapacity__c = TRUE AND ProcessingStatus__c = :AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED AND CreatedDate < :heldBefore AND CreatedDate >= :earliest WITH SYSTEM_MODE LIMIT :maximum FOR UPDATE];
    }
}
