/*
Class Name: AIConversationMessageService

=================================================================
=================================================================

Description: The entry point for a user sending a message: what the chat UI calls. Never talks to
the AI provider; that is handed off entirely to the asynchronous job.

Flow:
[1] AIMessageValidator checks the request: application on, message acceptable, agent active and
    assigned to the user, terms accepted, channel allowed, related record readable.
[2] Find an Active conversation to reuse, or start a new one (AIAgent__c.SingleActiveConversationPerRecord__c),
    closing the existing one first if it hit the agent's per-conversation message or token cap.
[3] AIUsageLimitService checks the user's and the organisation's limits.
[4] Take the conversation's processing lock, insert the user's message, and enqueue
    AIMessageProcessingQueueable, but only if the lock was free. If another message is still being
    processed this one waits, and that job's finalizer starts it.

Also owns retrying the newest message and manually closing a conversation, distinct from the idle
and retention jobs' automated closing.

Runs as the user (`with sharing`) and authorises as the user:
- A conversation is only ever found with a user-mode query, so a user reaches only their own
  (conversations are Private).
- Closing is a user-mode update, so only someone who can edit the conversation can close it.
- A new conversation is created in user mode: only fields the AI Assist User permission set can set.
- What the user may not write themselves (the message's token estimate and processing status) goes
  through AIMessagingDataService, after the checks above.

Every refusal is an AIMessagingException whose message is a Custom Label; the UI reads its code,
not its text. An unexpected failure reaches the caller as the generic label and is logged in full.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model and security model: runs with sharing, validation and limits moved out, outcome handling moved out, usage from AIUsageDaily__c, labels throughout, token accounting follows the agent's tracking method, methods shortened (retryMessage), single-use helpers inlined.
*/

public with sharing class AIConversationMessageService {
  // Validates the request, finds or creates the Active conversation, inserts the user's message, and enqueues the asynchronous turn. Returns the inserted message.
  public static AIConversationMessage__c sendMessage(
    Id agentId,
    String messageBody,
    String channel,
    String relatedObjectApiName,
    Id relatedRecordId
  ) {
    return sendMessage(
      null,
      agentId,
      messageBody,
      channel,
      relatedObjectApiName,
      relatedRecordId
    );
  }

  // As above, but continues conversationId when it is still Active, the user's own and on the same agent: the chat window passes the one it has open. Anything else (blank, closed, over its caps) starts a new conversation, so check the returned message's AIConversation__c.
  public static AIConversationMessage__c sendMessage(
    Id conversationId,
    Id agentId,
    String messageBody,
    String channel,
    String relatedObjectApiName,
    Id relatedRecordId
  ) {
    try {
      AIMessageValidator.ChatContext chatContext = AIMessageValidator.validateSendRequest(
        agentId,
        messageBody,
        channel,
        relatedObjectApiName,
        relatedRecordId
      );
      Decimal estimatedTokens = estimateTokenCount(messageBody);

      // Estimates count against the limits only where the agent asked for them: a "track" agent is measured by the provider after the call.
      Decimal tokensCountedForLimits = chatContext.agent.TokenTrackingMethod__c ==
        AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE ||
        chatContext.agent.TokenTrackingMethod__c ==
        AIAssistApplicationConstants.TRACKING_METHOD_PRE_REQUEST_CHECK
        ? estimatedTokens
        : 0;

      // The conversation to continue, found in user mode: by Id when the chat window passed one, otherwise by record when the agent keeps one conversation per record.
      List<AIConversation__c> candidateConversations = new List<AIConversation__c>();

      if (
        conversationId != null &&
        conversationId.getSobjectType() == AIConversation__c.SObjectType
      ) {
        candidateConversations = [
          SELECT Id, MessageCount__c, ConversationTokenUsage__c
          FROM AIConversation__c
          WHERE
            Id = :conversationId
            AND AIAgent__c = :chatContext.agent.Id
            AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
            AND OwnerId = :UserInfo.getUserId()
          WITH USER_MODE
          LIMIT 1
        ];
      } else if (
        conversationId == null &&
        chatContext.agent.SingleActiveConversationPerRecord__c == true &&
        relatedRecordId != null
      ) {
        candidateConversations = [
          SELECT Id, MessageCount__c, ConversationTokenUsage__c
          FROM AIConversation__c
          WHERE
            AIAgent__c = :chatContext.agent.Id
            AND RelatedRecordId__c = :String.valueOf(relatedRecordId)
            AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
            AND OwnerId = :UserInfo.getUserId()
          WITH USER_MODE
          LIMIT 1
        ];
      }

      AIConversation__c conversation = candidateConversations.isEmpty()
        ? null
        : candidateConversations[0];

      // A conversation at the agent's message or token cap is closed here, with the matching reason, so the user starts a fresh one instead of being blocked.
      if (conversation != null) {
        Decimal tokensUsed = conversation.ConversationTokenUsage__c == null
          ? 0
          : conversation.ConversationTokenUsage__c;

        if (
          chatContext.agent.MaxMessagesPerConversation__c != null &&
          conversation.MessageCount__c != null &&
          conversation.MessageCount__c >=
          chatContext.agent.MaxMessagesPerConversation__c
        ) {
          Database.SaveResult messageLimitCloseResult = Database.update(
            new AIConversation__c(
              Id = conversation.Id,
              Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
              ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_MESSAGE_LIMIT_REACHED
            ),
            false,
            AccessLevel.USER_MODE
          );
          if (!messageLimitCloseResult.isSuccess())
            throw AIMessagingException.newRefusal(
              AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
              Label.AI_Error_Conversation_Not_Found
            ); // A failure is reported as "not found", which reveals nothing about what exists.
          conversation = null;
        } else if (
          chatContext.agent.MaxTokensPerConversation__c != null &&
          tokensUsed + tokensCountedForLimits >=
          chatContext.agent.MaxTokensPerConversation__c
        ) {
          Database.SaveResult tokenLimitCloseResult = Database.update(
            new AIConversation__c(
              Id = conversation.Id,
              Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
              ConversationCloseReason__c = AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_TOKEN_LIMIT_REACHED
            ),
            false,
            AccessLevel.USER_MODE
          );
          if (!tokenLimitCloseResult.isSuccess())
            throw AIMessagingException.newRefusal(
              AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
              Label.AI_Error_Conversation_Not_Found
            );
          conversation = null;
        }
      }

      Boolean isNewConversation = conversation == null;

      if (
        isNewConversation &&
        AIAssistSettingsService.getUiSettings().IsUserInitiatedChatEnabled__c ==
        false
      ) {
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_NEW_CONVERSATIONS_PAUSED,
          Label.AI_Chat_New_Chats_Paused
        );
      }

      AIUsageLimitService.enforceUsageLimits(
        chatContext,
        isNewConversation,
        tokensCountedForLimits
      );

      if (isNewConversation) {
        // The new conversation is the user's own, so it is created in user mode: only fields the AI Assist User permission set can set.
        conversation = new AIConversation__c(
          AIAgent__c = chatContext.agent.Id,
          Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE,
          Channel__c = channel,
          RelatedObjectAPIName__c = relatedObjectApiName,
          RelatedRecordId__c = relatedRecordId == null
            ? null
            : String.valueOf(relatedRecordId)
        );

        Database.SaveResult conversationResult = Database.insert(
          conversation,
          false,
          AccessLevel.USER_MODE
        );
        if (!conversationResult.isSuccess())
          throw AIMessagingException.newFailure(
            'Failed to create conversation: ' +
              conversationResult.getErrors()[0].getStatusCode() +
              ' ' +
              conversationResult.getErrors()[0].getMessage(),
            null
          );

        // Counts towards the user's conversations for the day. Bookkeeping: a failure must not stop the user chatting.
        try {
          AIMessagingDataService.UsageDelta usageDelta = new AIMessagingDataService.UsageDelta();
          usageDelta.userId = chatContext.userId;
          usageDelta.agentId = chatContext.agent.Id;
          usageDelta.modelConfigurationId = chatContext.agent.AIModelConfiguration__c;
          usageDelta.conversations = 1;
          AIMessagingDataService.addToDailyUsage(usageDelta);
        } catch (Exception usageException) {
          AIPlatformLogManager.logException(
            usageException,
            'AIConversationMessageService',
            'sendMessage'
          );
        }
      }

      // Locked before the message is inserted, so a job finishing at the same moment either sees this message or finds the lock already released. It cannot miss it.
      Boolean shouldStartProcessing = AIConversationLockService.acquireLock(
        conversation.Id
      );

      AIConversationMessage__c userMessage = new AIConversationMessage__c(
        AIConversation__c = conversation.Id,
        Sender__c = AIAssistApplicationConstants.SENDER_USER,
        MessageBody__c = messageBody,
        ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
        TokenCount__c = chatContext.agent.TokenTrackingMethod__c ==
          AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE
          ? estimatedTokens
          : null
      );

      AIMessagingDataService.insertAsPackage(new List<SObject>{ userMessage });

      // Only when this message took the lock; otherwise it waits and the running job's finalizer starts it.
      if (shouldStartProcessing)
        System.enqueueJob(
          new AIMessageProcessingQueueable(userMessage.Id, conversation.Id)
        );

      return userMessage;
    } catch (Exception caughtException) {
      // Logs only what is unexpected and hands the caller a safe exception. A refusal is the system working, not a fault.
      if (caughtException instanceof AIMessagingException) {
        AIMessagingException knownException = (AIMessagingException) caughtException;
        if (!knownException.isRefusal)
          AIPlatformLogManager.logCustomMessage(
            knownException.getMessage(),
            knownException.detail,
            'AIConversationMessageService',
            'sendMessage',
            null
          );
        throw knownException;
      }

      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationMessageService',
        'sendMessage'
      );
      throw AIMessagingException.newFailure(
        caughtException.getMessage(),
        caughtException
      );
    }
  }

  // Re-runs the AI response for the conversation's newest user message: Try again after a failed turn, and Regenerate. Only the newest can be re-run, because the finalizer hands the lock to the newest user message and re-running an older one would answer the newest twice. Returns the message's Id.
  public static Id retryLatestUserMessage(Id conversationId) {
    try {
      // The user's own conversation, found in user mode so sharing and field-level security apply. Anything else (missing, someone else's, not visible) is "not found".
      if (
        conversationId == null ||
        conversationId.getSobjectType() != AIConversation__c.SObjectType
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
          Label.AI_Error_Conversation_Not_Found
        );

      List<AIConversation__c> ownConversations = [
        SELECT
          Id,
          Status__c,
          AIAgent__c,
          Channel__c,
          RelatedObjectAPIName__c,
          RelatedRecordId__c
        FROM AIConversation__c
        WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId()
        WITH USER_MODE
        LIMIT 1
      ];

      if (ownConversations.isEmpty())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
          Label.AI_Error_Conversation_Not_Found
        );

      AIConversation__c conversation = ownConversations[0];
      if (
        conversation.Status__c !=
        AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_CLOSED,
          Label.AI_Error_Conversation_Closed
        );

      List<AIConversationMessage__c> newestUserMessages = [
        SELECT Id, MessageBody__c
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :conversationId
          AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
        WITH USER_MODE
        ORDER BY CreatedDate DESC, Id DESC
        LIMIT 1
      ];

      if (newestUserMessages.isEmpty())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_MESSAGE_EMPTY,
          Label.AI_Error_Message_Empty
        );

      // A retry spends tokens and reads the record again, so it passes every check a new message does: the agent may have been unassigned or the record shared away since the first attempt.
      AIMessageValidator.ChatContext chatContext = AIMessageValidator.validateSendRequest(
        conversation.AIAgent__c,
        newestUserMessages[0].MessageBody__c,
        conversation.Channel__c,
        conversation.RelatedObjectAPIName__c,
        String.isBlank(conversation.RelatedRecordId__c)
          ? null
          : Id.valueOf(conversation.RelatedRecordId__c)
      );
      AIUsageLimitService.enforceUsageLimits(chatContext, false, 0);

      if (!AIConversationLockService.acquireLock(conversationId))
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_BUSY,
          Label.AI_Error_Conversation_Busy
        );

      AIMessagingDataService.updateAsPackage(
        new List<SObject>{
          new AIConversationMessage__c(
            Id = newestUserMessages[0].Id,
            ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED,
            FailureReason__c = null
          )
        }
      );

      System.enqueueJob(
        new AIMessageProcessingQueueable(
          newestUserMessages[0].Id,
          conversationId
        )
      );

      return newestUserMessages[0].Id;
    } catch (Exception caughtException) {
      // Logs only what is unexpected and hands the caller a safe exception. A refusal is the system working, not a fault.
      if (caughtException instanceof AIMessagingException) {
        AIMessagingException knownException = (AIMessagingException) caughtException;
        if (!knownException.isRefusal)
          AIPlatformLogManager.logCustomMessage(
            knownException.getMessage(),
            knownException.detail,
            'AIConversationMessageService',
            'retryMessage',
            null
          );
        throw knownException;
      }

      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationMessageService',
        'retryLatestUserMessage'
      );
      throw AIMessagingException.newFailure(
        caughtException.getMessage(),
        caughtException
      );
    }
  }

  // Manually ends a conversation, distinct from the idle and retention jobs' automated closing. Only someone who can edit the conversation can close it: the update runs in user mode.
  public static void closeConversation(Id conversationId, String closeReason) {
    try {
      // Not found, or not visible to this user, is reported the same way.
      if (
        conversationId == null ||
        conversationId.getSobjectType() != AIConversation__c.SObjectType
      )
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
          Label.AI_Error_Conversation_Not_Found
        );

      List<AIConversation__c> closableConversations = [
        SELECT
          Id,
          Status__c,
          AIAgent__c,
          Channel__c,
          RelatedObjectAPIName__c,
          RelatedRecordId__c
        FROM AIConversation__c
        WHERE Id = :conversationId AND OwnerId = :UserInfo.getUserId()
        WITH USER_MODE
        LIMIT 1
      ];

      if (closableConversations.isEmpty())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
          Label.AI_Error_Conversation_Not_Found
        );

      Database.SaveResult closeResult = Database.update(
        new AIConversation__c(
          Id = conversationId,
          Status__c = AIAssistApplicationConstants.CONVERSATION_STATUS_CLOSED,
          ConversationCloseReason__c = String.isBlank(closeReason)
            ? AIAssistApplicationConstants.CONVERSATION_CLOSE_REASON_USER_CLOSED
            : closeReason
        ),
        false,
        AccessLevel.USER_MODE
      );

      if (!closeResult.isSuccess())
        throw AIMessagingException.newRefusal(
          AIAssistApplicationConstants.ERROR_CONVERSATION_NOT_FOUND,
          Label.AI_Error_Conversation_Not_Found
        );
    } catch (Exception caughtException) {
      // Logs only what is unexpected and hands the caller a safe exception. A refusal is the system working, not a fault.
      if (caughtException instanceof AIMessagingException) {
        AIMessagingException knownException = (AIMessagingException) caughtException;
        if (!knownException.isRefusal)
          AIPlatformLogManager.logCustomMessage(
            knownException.getMessage(),
            knownException.detail,
            'AIConversationMessageService',
            'closeConversation',
            null
          );
        throw knownException;
      }

      AIPlatformLogManager.logException(
        caughtException,
        'AIConversationMessageService',
        'closeConversation'
      );
      throw AIMessagingException.newFailure(
        caughtException.getMessage(),
        caughtException
      );
    }
  }

  // A rough, cheap estimate (about four characters per token) for the limits; the provider's own count is only known after the callout.
  public static Decimal estimateTokenCount(String text) {
    return String.isBlank(text)
      ? 0
      : Math.ceil(
          text.length() /
          (Decimal) AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE
        );
  }
}
