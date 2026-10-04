/*
Class Name: AIMessageProcessingFinalizer

=================================================================
=================================================================

Description: Attached to every AIMessageProcessingQueueable job, and runs after it however it
ended: successfully, with a caught exception, or killed by an uncatchable LimitException (CPU,
heap, SOQL, callouts). It owns everything that must happen after a turn, so it happens exactly
once and always:

[1] If the job died on an unhandled error, log it, record the tokens it had spent, mark the
    message failed and tell the chat UI. The job never got the chance. This covers an uncatchable
    governor limit, and a data source that wrote to the database (AIDataSourceWriteException),
    which the job lets escape on purpose so the write is rolled back.
[2] If the job found its lock had expired, fail the stale turn and leave the lock alone: it now
    belongs to whatever message took the conversation over.
[3] If the job asked for a retry, enqueue it: straight away for the first retry, after
    RETRY_DELAY_MINUTES for later ones so a rate-limited provider is not hit again at once. The
    conversation stays locked until the retry has run. The agent manager stops asking for retries
    once the model's RetryAttempts__c are used up, and the turn fails.
[4] Otherwise hand the lock on: start the user's newest message if one arrived during this turn,
    or release it.
[5] With nothing to hand on, start a message of the same user's that was held at the org-wide cap on
    messages in flight (AIConversationMessageService.startHeldMessage), after failing any user's
    message that has waited there too long.

If the next job cannot be enqueued (the org is at its asynchronous limit, or this is a trial or
developer org, where chained jobs stop at a fixed depth), the finalizer does not leave the user
waiting for a reply that is not coming: it fails the turn, frees the lock and tells the chat UI.

Runs as the same user as the job, so retries and hand-offs keep the user's access. A finalizer
may enqueue at most one job, and this one never enqueues more than one: a retry takes priority and
the waiting message is picked up by the retry's own finalizer.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Runs with sharing. Failure recorded through AIMessageOutcomeService. Stale-lock handling, delayed later retries, and a graceful path when the next job cannot be enqueued.
3.0          Chandler Stuart          Takes a fresh reading of the org limits when the last is stale, before anything else (AIOrgLimitMonitor).
4.0          Chandler Stuart          Starts a message held at the cap on messages in flight when this turn leaves nothing else to queue.
*/

public with sharing class AIMessageProcessingFinalizer implements Finalizer {
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

  // The turn's context, filled in by the job as it learns the agent and model, so a job killed halfway still reports against the right agent.
  public AIMessageOutcomeService.AIResponseContext getResponseContext() {
    return responseContext;
  }

  // Tokens spent so far, so they are still recorded if the job dies on an unhandled error.
  public void recordTokensSpent(Decimal inputTokens, Decimal outputTokens) {
    this.inputTokens = inputTokens == null ? 0 : inputTokens;
    this.outputTokens = outputTokens == null ? 0 : outputTokens;
  }

  // The agent manager returned a retryable result. The tokens cover every attempt so far, so the retry carries them forward.
  public void scheduleRetry(Decimal inputTokens, Decimal outputTokens) {
    this.shouldRetry = true;
    recordTokensSpent(inputTokens, outputTokens);
  }

  // The job started after its processing lock had expired.
  public void markLockExpired() {
    this.isLockStale = true;
  }

  public void execute(FinalizerContext finalizerContext) {
    AIOrgLimitMonitor.refreshIfStale(); // A finalizer has finished its callout, so writing is safe here. Never throws.
    AIAssistSettingsService.recordActivatedOrg();

    try {
      // finalizerContext is null only when a test calls execute() directly.
      Boolean isJobFailed =
        finalizerContext != null &&
        finalizerContext.getResult() == ParentJobResult.UNHANDLED_EXCEPTION;
      Decimal totalTokens = inputTokens + outputTokens;

      // [2] The job never ran its turn. The lock is not ours to touch.
      if (isLockStale) {
        AIMessageOutcomeService.recordAiResponseFailure(
          responseContext,
          totalTokens,
          'The job started after its processing lock had expired.',
          AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
        );
        return;
      }

      // [1] The job was killed before it could report anything, usually by a governor limit.
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

      // [3] A retry is only trusted if the job finished normally. It re-runs the same message as a new job with fresh limits and keeps the conversation locked until it has run. Returning here means [4] never enqueues a second job: going over a finalizer's one-job limit is an uncatchable error.
      if (shouldRetry && !isJobFailed) {
        try {
          // Trial and developer orgs stop chained jobs at a fixed depth, and any org can be at its asynchronous limit. Say so up front instead of failing deep inside the platform. The depth is only answered inside a queueable or finalizer; anywhere else (a test calling execute() directly) there is no chain.
          Boolean isRetryAtMaximumDepth = false;
          try {
            isRetryAtMaximumDepth = AsyncInfo.hasMaxStackDepth();
          } catch (AsyncException retryNotInAChain) {
            isRetryAtMaximumDepth = false;
          }
          if (isRetryAtMaximumDepth)
            throw AIMessagingException.newFailure(
              'The maximum chained queueable depth has been reached.',
              null
            );

          // The limit is an uncatchable LimitException when passed, so it is checked first.
          if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())
            throw AIMessagingException.newFailure(
              'The asynchronous queueable limit for this transaction has been reached.',
              null
            );

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
        } catch (Exception retryException) {
          // The retry cannot run, so this turn ends here. Fall through to hand the lock on.
          AIPlatformLogManager.logException(
            retryException,
            'AIMessageProcessingFinalizer',
            'execute'
          );
          AIMessageOutcomeService.recordAiResponseFailure(
            responseContext,
            totalTokens,
            retryException.getMessage(),
            AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
          );
        }
      }

      // [4] Turn over: hand the lock to the user's newest waiting message, or release it.
      Id nextMessageId = AIConversationLockService.releaseOrHandOffLock(
        conversationId,
        triggeringMessageId
      );

      if (nextMessageId != null) {
        try {
          // Same depth and limit checks as for a retry above.
          Boolean isNextAtMaximumDepth = false;
          try {
            isNextAtMaximumDepth = AsyncInfo.hasMaxStackDepth();
          } catch (AsyncException nextNotInAChain) {
            isNextAtMaximumDepth = false;
          }
          if (isNextAtMaximumDepth)
            throw AIMessagingException.newFailure(
              'The maximum chained queueable depth has been reached.',
              null
            );

          // The limit is an uncatchable LimitException when passed, so it is checked first.
          if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())
            throw AIMessagingException.newFailure(
              'The asynchronous queueable limit for this transaction has been reached.',
              null
            );

          System.enqueueJob(
            new AIMessageProcessingQueueable(nextMessageId, conversationId),
            0
          );
        } catch (Exception queueException) {
          // The waiting message would sit behind a lock nobody is working on, so free it and tell the user. Try again re-runs the newest message.
          AIPlatformLogManager.logException(
            queueException,
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
        // [5] This turn's place is free: start a message of this user's that was held at the cap on messages in flight. A finalizer may queue one job, and this branch has queued none.
        AIConversationMessageService.startHeldMessage();
      }
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageProcessingFinalizer',
        'execute'
      );
    }
  }
}
