/*
Class Name: AIMessageOutcomeService

=================================================================
=================================================================

Description: Records what happens when a turn ends, whether it succeeded or failed, after the transaction's last callout.

Step 1: Work out whether the turn succeeded from the agent result
Step 2: On success, save the AI reply with its tokens, latency, model and prompt template, and supersede any earlier reply
Step 3: Close the user's message, and any older message still waiting, as Complete
Step 4: On failure, record the tokens spent, mark the messages Failed and log the real error
Step 5: Record the execution evidence and return the Custom Label the chat window shows

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIMessageOutcomeService {
  // Everything about the turn that is known by the time it ends.
  public class AIResponseContext {
    public Id conversationId;
    public Id triggeringMessageId;
    public Id userId;
    public Id agentId;
    public Id modelConfigurationId;
    public String providerName;
    public String modelIdentifier;
    public Id promptTemplateId;
    public Decimal promptTemplateVersion;
    public String tokenTrackingMethod;
  }

  // Records the outcome of one finished turn. Never throws: a bookkeeping failure is logged, and a reply that cannot be saved becomes a failed turn.
  public static void recordAiResponseOutcome(
    AIResponseContext responseContext,
    AIAgentManager.AgentResult agentResult,
    AIExecutionStepTracker executionTrace
  ) {
    try {
      // [1] A successful result is saved as a reply; anything else falls through to the failed turn below
      if (agentResult != null && agentResult.isSuccessful) {
        try {
          // [2] Work out the token counts, treating a missing figure as zero
          Decimal inputTokens = agentResult.inputTokens == null
            ? 0
            : agentResult.inputTokens;
          Decimal outputTokens = agentResult.outputTokens == null
            ? 0
            : agentResult.outputTokens;

          // [3] A provider that reports only a total still has its tokens counted, as input
          if (
            inputTokens + outputTokens == 0 &&
            agentResult.totalTokensUsed != null
          )
            inputTokens = agentResult.totalTokensUsed;

          // [4] Keep the suggested workflow action only if it is a real AIWorkflowAction__c Id, and ignore a bad one rather than failing the reply
          Id suggestedActionId = null;
          try {
            if (String.isNotBlank(agentResult.suggestedWorkflowActionId))
              suggestedActionId = Id.valueOf(
                agentResult.suggestedWorkflowActionId
              );
            if (
              suggestedActionId != null &&
              suggestedActionId.getSobjectType() !=
              AIWorkflowAction__c.SObjectType
            )
              suggestedActionId = null;
          } catch (Exception ex) {
            suggestedActionId = null;
          }

          // [5] Use the fallback text when the model returned no reply
          agentResult.replyText = String.isBlank(agentResult.replyText)
            ? Label.AI_Chat_Fallback_Default
            : agentResult.replyText;

          // [6] Build the reply, counting its tokens by length when the agent estimates them
          AIConversationMessage__c replyMessage = new AIConversationMessage__c(
            AIConversation__c = responseContext.conversationId,
            Sender__c = AIAssistApplicationConstants.SENDER_AI_AGENT,
            MessageBody__c = agentResult.replyText,
            ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
            TokenCount__c = responseContext.tokenTrackingMethod ==
              AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE
              ? AIConversationMessageService.estimateTokenCount(
                  agentResult.replyText
                )
              : agentResult.totalTokensUsed,
            InputTokenCount__c = inputTokens,
            OutputTokenCount__c = outputTokens,
            LatencyMilliseconds__c = agentResult.latencyMilliseconds,
            AIModelConfiguration__c = responseContext.modelConfigurationId,
            AIPromptTemplate__c = responseContext.promptTemplateId,
            PromptTemplateVersion__c = responseContext.promptTemplateVersion,
            SuggestedWorkflowAction__c = suggestedActionId,
            InReplyTo__c = responseContext.triggeringMessageId
          );

          // [7] Save the reply; if this fails the turn has not succeeded
          AIMessagingDataService.insertOrThrow(
            new List<SObject>{ replyMessage }
          );

          // [8] Regenerate: replace an earlier reply to the same message only now the new one is saved, so a regenerate that failed leaves the old answer standing
          if (responseContext.triggeringMessageId != null) {
            List<AIConversationMessage__c> replacedReplies = [
              SELECT Id
              FROM AIConversationMessage__c
              WHERE
                InReplyTo__c = :responseContext.triggeringMessageId
                AND Id != :replyMessage.Id
                AND IsSuperseded__c = FALSE
              WITH SYSTEM_MODE
            ];
            for (AIConversationMessage__c replacedReply : replacedReplies)
              replacedReply.IsSuperseded__c = true;
            AIMessagingDataService.updateAndLogFailures(
              replacedReplies,
              'AIMessageOutcomeService',
              'recordAiResponseOutcome'
            );
          }

          // [9] Mark the user's message, and any older one still waiting, as Complete
          closeWaitingMessages(
            responseContext,
            AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
            null,
            'recordAiResponseOutcome'
          );

          // [10] Record the execution evidence on the reply
          AIExecutionStepRecorder.recordExecutionSteps(
            replyMessage.Id,
            executionTrace,
            responseContext.providerName,
            responseContext.modelIdentifier
          );

          return;
        } catch (Exception ex) {
          // [11] Without the reply record the turn has not succeeded, so log the cause and treat it as a failed turn
          AIPlatformLogManager.logException(
            ex,
            'AIMessageOutcomeService',
            'recordAiResponseOutcome'
          );
          fail(
            responseContext,
            AIAssistApplicationConstants.FAILURE_REASON_OTHER,
            ex.getMessage(),
            agentResult,
            executionTrace
          );
          return;
        }
      }

      // [12] The agent failed (or returned nothing), so record a failed turn with its reason
      fail(
        responseContext,
        agentResult == null || String.isBlank(agentResult.failureReason)
          ? AIAssistApplicationConstants.FAILURE_REASON_OTHER
          : agentResult.failureReason,
        agentResult == null ? null : agentResult.errorMessage,
        agentResult,
        executionTrace
      );
    } catch (Exception ex) {
      // [13] The bookkeeping itself threw, so log it and still tell the window the turn failed
      AIPlatformLogManager.logException(
        ex,
        'AIMessageOutcomeService',
        'recordAiResponseOutcome'
      );
      publishMessageFailure(
        responseContext == null ? null : responseContext.conversationId,
        AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }

  // Records a turn whose job died before it could report: an uncatchable governor limit, a stale lock, or a data source write the job rolled back on purpose. Never throws.
  public static void recordAiResponseFailure(
    AIResponseContext responseContext,
    Decimal tokensSpent,
    String detail,
    String failureReason
  ) {
    try {
      // [1] Build a result that carries only the tokens spent, treating a missing figure as zero
      AIAgentManager.AgentResult agentResult = new AIAgentManager.AgentResult();
      agentResult.totalTokensUsed = tokensSpent == null ? 0 : tokensSpent;

      // [2] Record the failed turn
      fail(responseContext, failureReason, detail, agentResult, null);
    } catch (Exception ex) {
      // [3] The bookkeeping itself threw, so log it and still tell the window the turn failed
      AIPlatformLogManager.logException(
        ex,
        'AIMessageOutcomeService',
        'recordAiResponseFailure'
      );
      publishMessageFailure(
        responseContext == null ? null : responseContext.conversationId,
        AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }

  // Returns the Custom Label that matches the reason a turn failed. Safe to show: a label, never provider or configuration detail. Never throws.
  public static String publishMessageFailure(
    Id conversationId,
    String failureReason
  ) {
    // [1] Start with the generic label, used for any reason not matched below
    String userMessage = Label.AI_Error_Generic;

    // [2] Pick the label that matches the failure reason
    if (failureReason == AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT)
      userMessage = Label.AI_Error_Provider_Timeout;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
    )
      userMessage = Label.AI_Error_Provider_Unavailable;
    else if (
      failureReason == AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED
    )
      userMessage = Label.AI_Error_Daily_Usage_Limit;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_REQUEST_BLOCKED
    )
      userMessage = Label.AI_Error_Request_Blocked;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED
    )
      userMessage = Label.AI_Error_Privacy_Masking_Failed;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
    )
      userMessage = Label.AI_Error_Provider_Not_Configured;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_MESSAGE_MISSING
    )
      userMessage = Label.AI_Error_Conversation_Not_Found;
    else if (
      failureReason ==
      AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
    )
      userMessage = Label.AI_Error_Provider_Authentication;
    else if (
      failureReason == AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
    )
      userMessage = Label.AI_Error_Provider_Model_Retired;
    else if (
      failureReason == AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED
    )
      userMessage = Label.AI_Error_Provider_Rate_Limited;
    else if (
      failureReason == AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY
    )
      userMessage = Label.AI_Error_Service_Busy;

    // [3] Return the label
    return userMessage;
  }

  // Records a failed turn: the log, the tokens it spent, the user's message, the evidence and the label for the window.
  private static void fail(
    AIResponseContext responseContext,
    String failureReason,
    String detail,
    AIAgentManager.AgentResult agentResult,
    AIExecutionStepTracker executionTrace
  ) {
    // [1] Fall back to Other when no reason was given
    String reason = String.isBlank(failureReason)
      ? AIAssistApplicationConstants.FAILURE_REASON_OTHER
      : failureReason;

    // [2] Log the real error for administrators, never on a record the user can read
    AIPlatformLogManager.logCustomMessage(
      'AI responseContext failed: ' + reason,
      detail,
      'AIMessageOutcomeService',
      'fail',
      responseContext.triggeringMessageId
    );

    // [3] Work out the tokens the failed turn spent
    Decimal tokensSpent = agentResult == null ||
      agentResult.totalTokensUsed == null
      ? 0
      : agentResult.totalTokensUsed;

    // [4] Keep the spent tokens counting towards the conversation's total, using a System message that is never sent to the model or shown in the chat
    if (responseContext.conversationId != null && tokensSpent > 0) {
      AIMessagingDataService.insertAndLogFailures(
        new List<SObject>{
          new AIConversationMessage__c(
            AIConversation__c = responseContext.conversationId,
            Sender__c = AIAssistApplicationConstants.SENDER_SYSTEM,
            MessageBody__c = 'Turn failed: ' + reason,
            ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
            FailureReason__c = reason,
            TokenCount__c = tokensSpent
          )
        },
        'AIMessageOutcomeService',
        'fail'
      );
    }

    // [5] Mark the user's message, and any older one still waiting, as Failed
    closeWaitingMessages(
      responseContext,
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      reason,
      'fail'
    );

    // [6] Record the execution evidence on the user's message, as there is no reply to attach it to
    AIExecutionStepRecorder.recordExecutionSteps(
      responseContext.triggeringMessageId,
      executionTrace,
      responseContext.providerName,
      responseContext.modelIdentifier
    );

    // [7] Get the label for the window
    publishMessageFailure(responseContext.conversationId, reason);
  }

  // Ends the turn's message, and with it every user message in the conversation still Queued that was sent at or before it. Only the newest waiting message is answered, so an older one would otherwise stay Queued for ever. A failure is logged, never thrown.
  private static void closeWaitingMessages(
    AIResponseContext responseContext,
    String processingStatus,
    String failureReason,
    String methodName
  ) {
    try {
      // [1] Nothing to close when the turn has no message
      if (responseContext.triggeringMessageId == null)
        return;

      // [2] Find the turn's message and the user messages still Queued in the conversation
      List<AIConversationMessage__c> endedMessages = new List<AIConversationMessage__c>();
      Datetime triggeredAt;
      List<AIConversationMessage__c> candidates = [
        SELECT Id, CreatedDate
        FROM AIConversationMessage__c
        WHERE
          Id = :responseContext.triggeringMessageId
          OR (AIConversation__c = :responseContext.conversationId
          AND Sender__c = :AIAssistApplicationConstants.SENDER_USER
          AND ProcessingStatus__c = :AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED)
        WITH SYSTEM_MODE
      ];

      // [3] Note when the turn's own message was sent
      for (AIConversationMessage__c candidate : candidates) {
        if (candidate.Id == responseContext.triggeringMessageId)
          triggeredAt = candidate.CreatedDate;
      }

      // [4] Close the turn's message and every one sent at or before it, by time and, within the same second, by Id
      for (AIConversationMessage__c candidate : candidates) {
        if (
          candidate.Id == responseContext.triggeringMessageId ||
          (triggeredAt != null &&
          (candidate.CreatedDate < triggeredAt ||
          (candidate.CreatedDate == triggeredAt &&
          candidate.Id < responseContext.triggeringMessageId)))
        ) {
          endedMessages.add(
            new AIConversationMessage__c(
              Id = candidate.Id,
              ProcessingStatus__c = processingStatus,
              FailureReason__c = failureReason,
              IsAwaitingCapacity__c = false
            )
          );
        }
      }

      // [5] Save the new status
      AIMessagingDataService.updateAndLogFailures(
        endedMessages,
        'AIMessageOutcomeService',
        methodName
      );
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIMessageOutcomeService',
        methodName
      );
    }
  }
}
