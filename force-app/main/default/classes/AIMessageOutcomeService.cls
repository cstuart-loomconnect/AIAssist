/*
Class Name: AIMessageOutcomeService

=================================================================
=================================================================

Description: What happens when a turn ends, wherever it ended: in AIMessageProcessingQueueable or,
if the job was killed, in AIMessageProcessingFinalizer. AIAgentManager only makes the callouts and
returns a result; everything that touches the database or the event bus is here, after the
transaction's last callout.

A successful turn:
- inserts the AI reply with its token counts, latency, model, and the prompt template and version
  that produced it;
- marks the user's message Complete;
- records the execution evidence (AIExecutionStepRecorder) on the reply;
- adds the turn to the user's usage for the day (AIUsageDaily__c);
- publishes AIMessageReadyEvent__e so the chat window fetches the reply.

A failed turn:
- records the tokens it still spent, as a System message, so they count towards the conversation's
  total and the user's limits;
- marks the user's message Failed with a failure reason;
- records the execution evidence on the user's message (there is no reply to attach it to);
- counts the failed turn in usage;
- tells the chat window with the Custom Label that matches the reason, never the provider's own
  error text, which can carry configuration detail or an echo of the prompt.

The detailed error goes to the platform log, never to a record the user can read.

Everything after the answer exists is best effort: a bookkeeping failure is logged and never
turns a finished answer into an error. The exception is the reply insert itself. Without it the
turn has not succeeded, so that failure becomes a failed turn.

Token accounting follows AIAgent__c.TokenTrackingMethod__c: Estimate counts the reply by its
length; Track and Pre-Request use the provider's own count.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development, split out of AIConversationMessageService.
*/

public inherited sharing class AIMessageOutcomeService {
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
    public List<AIViolationRule__c> aiRules; // The AI evaluated rules the turn was asked to flag.
  }

  // Records the outcome of one finished turn and tells the chat window. Never throws.
  public static void recordAiResponseOutcome(
    AIResponseContext responseContext,
    AIAgentManager.AgentResult agentResult,
    AIExecutionStepTracker executionTrace
  ) {
    try {
      if (agentResult != null && agentResult.isSuccessful) {
        try {
          Decimal inputTokens = agentResult.inputTokens == null
            ? 0
            : agentResult.inputTokens;
          Decimal outputTokens = agentResult.outputTokens == null
            ? 0
            : agentResult.outputTokens;
          if (
            inputTokens + outputTokens == 0 &&
            agentResult.totalTokensUsed != null
          )
            inputTokens = agentResult.totalTokensUsed; // A provider that reports only a total still has its tokens counted, as input.

          // The model names a workflow action by Id; only a real AIWorkflowAction__c Id is stored, and a bad one is ignored rather than failing the reply.
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
          } catch (Exception notAnId) {
            suggestedActionId = null;
          }

          // The model flags a rule by putting its signal tag in the reply. The tag is taken out, and a blocking rule withholds the reply.
          AIViolationService.Inspection replyInspection = AIViolationService.checkReplyForSignalTags(
            responseContext,
            agentResult.replyText
          );
          if (replyInspection.isBlocked) {
            fail(
              responseContext,
              AIAssistApplicationConstants.FAILURE_REASON_REQUEST_BLOCKED,
              'A blocking violation rule fired.',
              agentResult,
              executionTrace
            );
            return;
          }

          agentResult.replyText = String.isBlank(replyInspection.replyText)
            ? Label.AI_Chat_Fallback_Default
            : replyInspection.replyText;

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

          AIMessagingDataService.insertAsPackage(
            new List<SObject>{ replyMessage }
          );

          // Regenerate: an earlier reply to the same message is replaced now that the new one is saved, so a regenerate that failed would have left the old answer standing.
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

          closeWaitingMessages(
            responseContext,
            AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE,
            null,
            'recordAiResponseOutcome'
          );

          AIExecutionStepRecorder.recordExecutionSteps(
            replyMessage.Id,
            executionTrace,
            responseContext.providerName,
            responseContext.modelIdentifier
          );

          // Adds the turn to the user's usage for the day. Bookkeeping: a failure is logged and the turn stands.
          try {
            if (responseContext.userId != null) {
              AIMessagingDataService.UsageDelta successUsageDelta = new AIMessagingDataService.UsageDelta();
              successUsageDelta.userId = responseContext.userId;
              successUsageDelta.agentId = responseContext.agentId;
              successUsageDelta.modelConfigurationId = responseContext.modelConfigurationId;
              successUsageDelta.messages = 1;
              successUsageDelta.failedTurns = 0;
              successUsageDelta.inputTokens = inputTokens;
              successUsageDelta.outputTokens = outputTokens;

              AIMessagingDataService.addToDailyUsage(successUsageDelta);
            }
          } catch (Exception usageException) {
            AIPlatformLogManager.logException(
              usageException,
              'AIMessageOutcomeService',
              'recordAiResponseOutcome'
            );
          }

          // Published and checked: a refused publish (event limits) would leave the chat window waiting for a reply that never announces itself. Events are optional: when they are off, or the org is near a limit, the window polls and nothing is published.
          Database.SaveResult replyPublishResult = AIOrgLimitMonitor.isEventNotificationAllowed()
            ? EventBus.publish(
                new AIMessageReadyEvent__e(
                  AIConversationId__c = responseContext.conversationId,
                  AIConversationMessageId__c = replyMessage.Id,
                  IsSuccess__c = true
                )
              )
            : null;
          if (replyPublishResult != null && !replyPublishResult.isSuccess())
            AIPlatformLogManager.logCustomMessage(
              'AIMessageReadyEvent__e was not published.',
              replyPublishResult.getErrors()[0].getMessage(),
              'AIMessageOutcomeService',
              'recordResult',
              null
            );
          return;
        } catch (Exception replyException) {
          // Without the reply record the turn has not succeeded: it becomes a failed turn, with the cause in the log.
          AIPlatformLogManager.logException(
            replyException,
            'AIMessageOutcomeService',
            'recordAiResponseOutcome'
          );
          fail(
            responseContext,
            AIAssistApplicationConstants.FAILURE_REASON_OTHER,
            replyException.getMessage(),
            agentResult,
            executionTrace
          );
          return;
        }
      }

      fail(
        responseContext,
        agentResult == null || String.isBlank(agentResult.failureReason)
          ? AIAssistApplicationConstants.FAILURE_REASON_OTHER
          : agentResult.failureReason,
        agentResult == null ? null : agentResult.errorMessage,
        agentResult,
        executionTrace
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageOutcomeService',
        'recordAiResponseOutcome'
      ); // The bookkeeping itself threw. Still release the chat window.
      publishMessageFailure(
        responseContext == null ? null : responseContext.conversationId,
        AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }

  // A job that died before it could report: an uncatchable governor limit, a stale lock, or a data source write the job rolled back on purpose. Never throws.
  public static void recordAiResponseFailure(
    AIResponseContext responseContext,
    Decimal tokensSpent,
    String detail,
    String failureReason
  ) {
    try {
      AIAgentManager.AgentResult agentResult = new AIAgentManager.AgentResult();
      agentResult.totalTokensUsed = tokensSpent == null ? 0 : tokensSpent;

      fail(responseContext, failureReason, detail, agentResult, null);
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageOutcomeService',
        'recordAiResponseFailure'
      );
      publishMessageFailure(
        responseContext == null ? null : responseContext.conversationId,
        AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }

  // Tells the chat window a turn failed, with the Custom Label that matches the reason, and returns the text it sent. Safe to show: a label, never provider or configuration detail. Never throws.
  public static String publishMessageFailure(
    Id conversationId,
    String failureReason
  ) {
    String userMessage = Label.AI_Error_Generic;

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

    try {
      if (conversationId != null) {
        // Published and checked: a refused publish (event limits) would leave the chat window waiting.
        Database.SaveResult failurePublishResult = AIOrgLimitMonitor.isEventNotificationAllowed()
          ? EventBus.publish(
              new AIMessageReadyEvent__e(
                AIConversationId__c = conversationId,
                IsSuccess__c = false,
                ErrorMessage__c = userMessage.left(
                  AIAssistApplicationConstants.EVENT_ERROR_MESSAGE_LENGTH
                )
              )
            )
          : null;
        if (failurePublishResult != null && !failurePublishResult.isSuccess())
          AIPlatformLogManager.logCustomMessage(
            'AIMessageReadyEvent__e was not published.',
            failurePublishResult.getErrors()[0].getMessage(),
            'AIMessageOutcomeService',
            'notifyFailure',
            null
          );
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageOutcomeService',
        'publishMessageFailure'
      );
    }

    return userMessage;
  }

  // Records a failed turn: the log, the tokens it spent, the user's message, the evidence, the usage, and the chat window.
  private static void fail(
    AIResponseContext responseContext,
    String failureReason,
    String detail,
    AIAgentManager.AgentResult agentResult,
    AIExecutionStepTracker executionTrace
  ) {
    String reason = String.isBlank(failureReason)
      ? AIAssistApplicationConstants.FAILURE_REASON_OTHER
      : failureReason;

    // The real error is for administrators, in the platform log; never on a record the user reads.
    AIPlatformLogManager.logCustomMessage(
      'AI responseContext failed: ' + reason,
      detail,
      'AIMessageOutcomeService',
      'fail',
      responseContext.triggeringMessageId
    );

    Decimal tokensSpent = agentResult == null ||
      agentResult.totalTokensUsed == null
      ? 0
      : agentResult.totalTokensUsed;
    Decimal inputTokens = agentResult == null ||
      agentResult.inputTokens == null
      ? 0
      : agentResult.inputTokens;
    Decimal outputTokens = agentResult == null ||
      agentResult.outputTokens == null
      ? 0
      : agentResult.outputTokens;
    if (inputTokens + outputTokens == 0)
      inputTokens = tokensSpent;

    // The tokens a failed turn spent still count towards the conversation's total and the user's limits. A System message is never sent to the model or shown in the chat.
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

    // Masking that failed, or a setup that is wrong, is a violation the agent's rules may be waiting for.
    if (
      reason == AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED
    )
      AIViolationService.recordDeterministicViolation(
        AIAssistApplicationConstants.VIOLATION_TYPE_PII_MASKING_FAILURE,
        responseContext.agentId,
        responseContext.userId,
        responseContext.conversationId,
        responseContext.triggeringMessageId
      );
    else if (
      reason == AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
    )
      AIViolationService.recordDeterministicViolation(
        AIAssistApplicationConstants.VIOLATION_TYPE_CONFIGURATION,
        responseContext.agentId,
        responseContext.userId,
        responseContext.conversationId,
        responseContext.triggeringMessageId
      );

    closeWaitingMessages(
      responseContext,
      AIAssistApplicationConstants.PROCESSING_STATUS_FAILED,
      reason,
      'fail'
    );

    AIExecutionStepRecorder.recordExecutionSteps(
      responseContext.triggeringMessageId,
      executionTrace,
      responseContext.providerName,
      responseContext.modelIdentifier
    );

    // Adds the turn to the user's usage for the day. Bookkeeping: a failure is logged and the turn stands.
    try {
      if (responseContext.userId != null) {
        AIMessagingDataService.UsageDelta failedUsageDelta = new AIMessagingDataService.UsageDelta();
        failedUsageDelta.userId = responseContext.userId;
        failedUsageDelta.agentId = responseContext.agentId;
        failedUsageDelta.modelConfigurationId = responseContext.modelConfigurationId;
        failedUsageDelta.messages = 1;
        failedUsageDelta.failedTurns = 1;
        failedUsageDelta.inputTokens = inputTokens;
        failedUsageDelta.outputTokens = outputTokens;

        AIMessagingDataService.addToDailyUsage(failedUsageDelta);
      }
    } catch (Exception usageException) {
      AIPlatformLogManager.logException(
        usageException,
        'AIMessageOutcomeService',
        'fail'
      );
    }

    publishMessageFailure(responseContext.conversationId, reason);
  }

  // Ends the turn's message, and with it every user message in the conversation still Queued that was sent at or before it. Only the newest waiting message is answered (the finalizer hands the lock to the newest), so an older one sent while a reply was being prepared would otherwise stay Queued for ever. Bookkeeping: a failure is logged, never thrown.
  private static void closeWaitingMessages(
    AIResponseContext responseContext,
    String processingStatus,
    String failureReason,
    String methodName
  ) {
    try {
      if (responseContext.triggeringMessageId == null)
        return;

      // "At or before" by time and, within the same second, by Id: the order the history is read in.
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
      for (AIConversationMessage__c candidate : candidates) {
        if (candidate.Id == responseContext.triggeringMessageId)
          triggeredAt = candidate.CreatedDate;
      }
      for (AIConversationMessage__c candidate : candidates) {
        if (
          candidate.Id == responseContext.triggeringMessageId ||
          (triggeredAt != null &&
          (candidate.CreatedDate < triggeredAt ||
          (candidate.CreatedDate == triggeredAt &&
          candidate.Id < responseContext.triggeringMessageId)))
        )
          endedMessages.add(
            new AIConversationMessage__c(
              Id = candidate.Id,
              ProcessingStatus__c = processingStatus,
              FailureReason__c = failureReason,
              IsAwaitingCapacity__c = false
            )
          );
      }

      AIMessagingDataService.updateAndLogFailures(
        endedMessages,
        'AIMessageOutcomeService',
        methodName
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageOutcomeService',
        methodName
      );
    }
  }
}
