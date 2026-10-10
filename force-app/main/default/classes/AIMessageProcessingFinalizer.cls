/*
Class Name: AIMessageProcessingFinalizer

=================================================================
=================================================================

Description: Finalizer attached to every AIMessageProcessingQueueable job. It runs after the job however it ended and owns everything that must happen once a turn is over.

Step 1: Work out how the job ended, including a kill by an uncatchable governor limit
Step 2: If the job started after its lock expired, fail the stale turn and leave the lock alone
Step 3: If the job was killed, log it, record the tokens spent, fail the message and tell the chat window
Step 4: If the job asked for a retry, enqueue it (delayed after the first retry) and keep the lock
Step 5: Otherwise hand the lock to the user's newest waiting message, or release it
Step 6: With nothing to hand on, start a message that was held at the cap on messages in flight
Step 7: If the next job cannot be enqueued, fail the turn, free the lock and tell the chat window

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIMessageProcessingFinalizer implements Finalizer {
  public class AIMessageProcessingFinalizerException extends Exception {
  }

  private Id triggeringMessageId;
  private Id conversationId;
  private Integer attemptNumber;
  private AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();

  // Set by AIMessageProcessingQueueable while the job runs.
  @TestVisible
  private Boolean shouldRetry = false;
  @TestVisible
  private Boolean isLockStale = false;
  @TestVisible
  private Decimal inputTokens = 0;
  @TestVisible
  private Decimal outputTokens = 0;

  // Keeps the details of the turn so the finalizer can finish it whatever happened to the job.
  public AIMessageProcessingFinalizer(
    Id triggeringMessageId,
    Id conversationId,
    Integer attemptNumber,
    Id userId
  ) {
    this.triggeringMessageId = triggeringMessageId;
    this.conversationId = conversationId;
    this.attemptNumber = attemptNumber == null ? 1 : attemptNumber;

    this.responseContext.conversationId = conversationId;
    this.responseContext.triggeringMessageId = triggeringMessageId;
    this.responseContext.userId = userId;
  }

  // Returns the turn's context, which the job fills in as it learns the agent and model, so a job killed halfway still reports against the right agent.
  public AIMessageOutcomeService.AIResponseContext getResponseContext() {
    return responseContext;
  }

  // Stores the tokens spent so far, so they are still recorded if the job dies on an unhandled error.
  public void recordTokensSpent(Decimal inputTokens, Decimal outputTokens) {
    this.inputTokens = inputTokens == null ? 0 : inputTokens;
    this.outputTokens = outputTokens == null ? 0 : outputTokens;
  }

  // Asks for a retry because the agent manager returned a retryable result. The tokens cover every attempt so far, so the retry carries them forward.
  public void scheduleRetry(Decimal inputTokens, Decimal outputTokens) {
    this.shouldRetry = true;
    recordTokensSpent(inputTokens, outputTokens);
  }

  // Notes that the job started after its processing lock had expired.
  public void markLockExpired() {
    this.isLockStale = true;
  }

  // Finishes the turn once the job has ended. It never throws, so a failure here cannot hide the job's own result.
  public void execute(FinalizerContext finalizerContext) {
    try {
      // [1] Work out how the job ended. The context is null only when a test calls execute directly
      Boolean isJobFailed =
        finalizerContext != null &&
        finalizerContext.getResult() == ParentJobResult.UNHANDLED_EXCEPTION;
      Decimal totalTokens = inputTokens + outputTokens;

      // [2] The job never ran its turn, so fail it as a timeout and leave the lock alone as it now belongs to another message
      if (isLockStale) {
        AIMessageOutcomeService.recordAiResponseFailure(
          responseContext,
          totalTokens,
          'The job started after its processing lock had expired.',
          AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
        );
        return;
      }

      // [3] The job was killed before it could report anything, usually by a governor limit, so log it and fail the message
      if (isJobFailed) {
        Exception jobException = finalizerContext.getException();
        AIPlatformLogManager.logException(
          jobException,
          'AIMessageProcessingQueueable',
          'execute'
        );
        AIMessageOutcomeService.recordAiResponseFailure(
          responseContext,
          totalTokens,
          jobException == null ? null : jobException.getMessage(),
          AIAssistApplicationConstants.FAILURE_REASON_OTHER
        );
      }

      // [4] Only trust a retry if the job finished normally. It re-runs the same message as a new job with fresh limits and keeps the conversation locked. Returning here means no second job is enqueued, as going over a finalizer's one-job limit is an uncatchable error
      if (shouldRetry && !isJobFailed) {
        try {
          // [5] Check the chained job depth first, as trial and developer orgs stop at a fixed depth. It can only be asked inside a queueable or finalizer, so anywhere else there is no chain
          Boolean isRetryAtMaximumDepth = false;
          try {
            isRetryAtMaximumDepth = AsyncInfo.hasMaxStackDepth();
          } catch (AsyncException ex) {
            isRetryAtMaximumDepth = false;
          }

          if (isRetryAtMaximumDepth) {
            AIPlatformLogManager.logCustomMessage(
              'The maximum chained queueable depth has been reached.',
              null,
              'AIMessageProcessingFinalizer',
              'execute',
              null
            );
            throw new AIMessageProcessingFinalizerException(
              Label.AI_Error_Generic
            );
          }

          // [6] Check the queueable limit before adding the job, as going past it is an uncatchable error
          if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            AIPlatformLogManager.logCustomMessage(
              'The asynchronous queueable limit for this transaction has been reached.',
              null,
              'AIMessageProcessingFinalizer',
              'execute',
              null
            );
            throw new AIMessageProcessingFinalizerException(
              Label.AI_Error_Generic
            );
          }

          // [7] Enqueue the retry straight away the first time, then after a delay so a rate-limited provider is not hit again at once
          System.enqueueJob(
            new AIMessageProcessingQueueable(
              triggeringMessageId,
              conversationId,
              attemptNumber + 1,
              inputTokens,
              outputTokens
            ),
            attemptNumber >= 2
              ? AIAssistApplicationConstants.RETRY_DELAY_MINUTES
              : 0
          );
          AIConversationLockService.extendLock(conversationId);
          return;
        } catch (Exception ex) {
          // [8] The retry cannot run, so this turn ends here. Fall through to hand the lock on
          AIPlatformLogManager.logException(
            ex,
            'AIMessageProcessingFinalizer',
            'execute'
          );
          AIMessageOutcomeService.recordAiResponseFailure(
            responseContext,
            totalTokens,
            ex.getMessage(),
            AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
          );
        }
      }

      // [9] The turn is over, so hand the lock to the user's newest waiting message, or release it
      Id nextMessageId = AIConversationLockService.releaseOrHandOffLock(
        conversationId,
        triggeringMessageId
      );

      if (nextMessageId != null) {
        try {
          // [10] Run the same depth check as for a retry
          Boolean isNextAtMaximumDepth = false;
          try {
            isNextAtMaximumDepth = AsyncInfo.hasMaxStackDepth();
          } catch (AsyncException ex) {
            isNextAtMaximumDepth = false;
          }

          if (isNextAtMaximumDepth) {
            AIPlatformLogManager.logCustomMessage(
              'The maximum chained queueable depth has been reached.',
              null,
              'AIMessageProcessingFinalizer',
              'execute',
              null
            );
            throw new AIMessageProcessingFinalizerException(
              Label.AI_Error_Generic
            );
          }

          // [11] Run the same queueable limit check as for a retry
          if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            AIPlatformLogManager.logCustomMessage(
              'The asynchronous queueable limit for this transaction has been reached.',
              null,
              'AIMessageProcessingFinalizer',
              'execute',
              null
            );
            throw new AIMessageProcessingFinalizerException(
              Label.AI_Error_Generic
            );
          }

          // [12] Start the waiting message
          System.enqueueJob(
            new AIMessageProcessingQueueable(nextMessageId, conversationId),
            0
          );
        } catch (Exception ex) {
          // [13] The waiting message would sit behind a lock nobody is working on, so free it and tell the user. Try again re-runs the newest message
          AIPlatformLogManager.logException(
            ex,
            'AIMessageProcessingFinalizer',
            'execute'
          );
          AIConversationLockService.releaseLock(conversationId);
          AIMessageOutcomeService.publishMessageFailure(
            conversationId,
            AIAssistApplicationConstants.FAILURE_REASON_OTHER
          );
        }
      } else {
        // [14] This turn's place is free, so start a message of this user's that was held at the cap on messages in flight. This branch has queued no job, so the finalizer's one-job limit is safe
        AIConversationMessageService.startHeldMessage();
      }
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIMessageProcessingFinalizer',
        'execute'
      );
    }
  }
}
