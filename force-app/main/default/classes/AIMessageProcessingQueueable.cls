/*
Class Name: AIMessageProcessingQueueable

=================================================================
=================================================================

Description: The asynchronous worker that does the heavy lifting for one message, run outside the
user's original transaction so the chat UI is not blocked on a live callout. Runs as the user who
sent the message.

Flow:
[0] Attach AIMessageProcessingFinalizer, which runs after this job however it ends: it schedules
    retries, starts the next waiting message, releases the conversation's lock, and reports a job
    killed by an uncatchable governor limit.
[1] Load everything for the turn. The user's own data (the message, the conversation, the history)
    is read in user mode. Configuration the user cannot read (agent, model connection, prompt,
    tools) is read by AIMessagingSelector.
[2] Run the turn through IAIResponseExecutor (AIAgentManager). It only makes the callouts and returns
    a result. PII mappings its tool calls create are held in memory and saved here once every
    callout is done.
[3] A retryable result is handed to the finalizer to schedule. Anything else goes to
    AIMessageOutcomeService, which completes or fails the turn.

No DML happens before the callout: an uncommitted write makes every later callout in the
transaction fail. That is why the job checks the conversation's lock read-only, and why it does not
mark the message "Processing".

A job can wait in a busy org's queue longer than the lock lasts. If the lock has expired when the
job starts, the job stands down rather than run beside whatever took the conversation over; the
finalizer then fails the stale turn and leaves the lock alone.

A failure is caught here, recorded as a failed turn and reported to the chat UI. The conversation Id is passed in up front, so
that works even when the triggering message was deleted before the job ran.

How much is loaded is bounded: at most MAX_HISTORY_MESSAGES of history within MAX_HISTORY_CHARACTERS,
and MAX_TOOLS_PER_KIND tools of each kind, so one chat cannot exhaust the asynchronous heap or bloat
every request.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Runs with sharing. User data read in user mode, configuration through AIMessagingSelector. Turn executor seam for tests. History bounded by characters and cut off at the triggering message by Id as well as time. Lock checked before the callout. Outcome handling in AIMessageOutcomeService. Input and output tokens carried across retries. Loaders inlined.
*/

public with sharing class AIMessageProcessingQueueable implements Queueable, Database.AllowsCallouts {
  // Everything AIAgentManager needs for one attempt of one turn.
  public class AIResponseRequest {
    public AIAgent__c agent;
    public AIModelConfiguration__c modelConfiguration;
    public AIPromptTemplate__c promptTemplate;
    public AIConversation__c conversation;
    public List<AIConversationMessage__c> messageHistory;
    public List<AIDataSource__c> dataSources;
    public List<AIWorkflowAction__c> workflowActions;
    public Integer attemptNumber;
    public AIExecutionStepTracker trace;
  }

  // The seam between the messaging layer and the AI Agent Manager. A test replaces it so the messaging layer is tested on its own behaviour, not on a provider's.
  public interface IAIResponseExecutor {
    AIAgentManager.AgentResult execute(AIResponseRequest responseRequest);
  }

  private class AgentManagerResponseExecutor implements IAIResponseExecutor {
    public AIAgentManager.AgentResult execute(
      AIResponseRequest responseRequest
    ) {
      return AIAgentManager.executeAiMessage(
        responseRequest.agent,
        responseRequest.modelConfiguration,
        responseRequest.promptTemplate,
        responseRequest.conversation,
        responseRequest.messageHistory,
        responseRequest.dataSources,
        responseRequest.workflowActions,
        responseRequest.attemptNumber,
        responseRequest.trace
      );
    }
  }

  @TestVisible
  private static IAIResponseExecutor aiResponseExecutor = new AgentManagerResponseExecutor();

  private Id conversationId;
  private Id triggeringMessageId;
  private Integer attemptNumber;
  private Decimal priorInputTokens;
  private Decimal priorOutputTokens;

  // A message's first attempt. Only Ids are stored, since queueable arguments must be serializable and an SObject would go stale by execute time.
  public AIMessageProcessingQueueable(
    Id triggeringMessageId,
    Id conversationId
  ) {
    this(triggeringMessageId, conversationId, 1, 0, 0);
  }

  // A retry, scheduled by the finalizer. The prior tokens are what earlier failed attempts already spent, so the final reply and the usage record cover the whole turn.
  public AIMessageProcessingQueueable(
    Id triggeringMessageId,
    Id conversationId,
    Integer attemptNumber,
    Decimal priorInputTokens,
    Decimal priorOutputTokens
  ) {
    this.triggeringMessageId = triggeringMessageId;
    this.conversationId = conversationId;
    this.attemptNumber = attemptNumber == null ? 1 : attemptNumber;
    this.priorInputTokens = priorInputTokens == null ? 0 : priorInputTokens;
    this.priorOutputTokens = priorOutputTokens == null ? 0 : priorOutputTokens;
  }

  public void execute(QueueableContext queueableContext) {
    Id userId = UserInfo.getUserId();

    // [0] Attached first so it runs however this job ends, even on an uncatchable LimitException. queueableContext is null only when a test calls execute() directly.
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      triggeringMessageId,
      conversationId,
      attemptNumber,
      userId
    );
    if (queueableContext != null)
      System.attachFinalizer(finalizer);

    // Earlier attempts' tokens are known now, so they are recorded even if this job is killed.
    finalizer.recordTokensSpent(priorInputTokens, priorOutputTokens);

    AIMessageOutcomeService.AIResponseContext responseContext = finalizer.getResponseContext();
    Decimal tokensSoFar = priorInputTokens + priorOutputTokens;

    try {
      // [1] The message that triggered this job, re-queried because only its Id crossed the asynchronous boundary. User mode: the job acts for the user who sent it.
      List<AIConversationMessage__c> triggeringMessages = triggeringMessageId ==
        null ||
        triggeringMessageId.getSobjectType() !=
        AIConversationMessage__c.SObjectType
        ? new List<AIConversationMessage__c>()
        : [
            SELECT Id, MessageBody__c, AIConversation__c, CreatedDate
            FROM AIConversationMessage__c
            WHERE Id = :triggeringMessageId
            WITH USER_MODE
            LIMIT 1
          ];

      // Deleted after being enqueued: still tell the chat UI, which is waiting on this turn.
      if (triggeringMessages.isEmpty()) {
        AIMessageOutcomeService.publishMessageFailure(
          conversationId,
          AIAssistApplicationConstants.FAILURE_REASON_MESSAGE_MISSING
        );
        return;
      }

      AIConversationMessage__c triggeringMessage = triggeringMessages[0];

      // Read-only: no DML may happen before the callout.
      if (!AIConversationLockService.isConversationLocked(conversationId)) {
        finalizer.markLockExpired();
        return;
      }

      // Required for the turn: a missing record is a setup problem, thrown for the catch below to log once and report as a configuration error.
      List<AIConversation__c> conversationRows = [
        SELECT Id, AIAgent__c, RelatedObjectAPIName__c, RelatedRecordId__c
        FROM AIConversation__c
        WHERE Id = :triggeringMessage.AIConversation__c
        WITH USER_MODE
        LIMIT 1
      ];
      if (conversationRows.isEmpty())
        throw AIMessagingException.newFailure(
          'AI Conversation not found for Id: ' +
          triggeringMessage.AIConversation__c,
          null
        );

      AIConversation__c conversation = conversationRows[0];
      AIAgent__c agent = AIMessagingSelector.getAgent(conversation.AIAgent__c);
      if (agent == null)
        throw AIMessagingException.newFailure(
          'AI Agent not found for Id: ' + conversation.AIAgent__c,
          null
        );

      AIModelConfiguration__c modelConfiguration = AIMessagingSelector.getModelConfiguration(
        agent.AIModelConfiguration__c
      );
      if (modelConfiguration == null)
        throw AIMessagingException.newFailure(
          'The AI Agent has no AI Model Configuration assigned.',
          null
        );

      AIPromptTemplate__c promptTemplate = AIMessagingSelector.getActivePromptTemplate(
        agent.Id
      ); // None is valid: no system prompt is assembled.

      responseContext.agentId = agent.Id;
      responseContext.modelConfigurationId = modelConfiguration.Id;
      responseContext.providerName = modelConfiguration.AIProvider__c;
      responseContext.modelIdentifier = modelConfiguration.ModelIdentifier__c;
      responseContext.promptTemplateId = promptTemplate == null
        ? null
        : promptTemplate.Id;
      responseContext.promptTemplateVersion = promptTemplate == null
        ? null
        : promptTemplate.Version__c;
      responseContext.tokenTrackingMethod = agent.TokenTrackingMethod__c;

      // The newest messages up to and including the one being answered, within the count and character budgets. Queried newest first so the cap keeps the latest, then reversed for the model. It stops at the triggering message by time and, within the same second, by Id, so the history always ends with the question being answered even if the user has sent more since. System messages (the record of a failed turn's tokens) are never part of what the model sees.
      List<AIConversationMessage__c> newestFirst = [
        SELECT Id, Sender__c, MessageBody__c
        FROM AIConversationMessage__c
        WHERE
          AIConversation__c = :triggeringMessage.AIConversation__c
          AND (CreatedDate < :triggeringMessage.CreatedDate
          OR (CreatedDate = :triggeringMessage.CreatedDate
          AND Id <= :triggeringMessage.Id))
          AND Sender__c != :AIAssistApplicationConstants.SENDER_SYSTEM
          AND IsSuperseded__c = FALSE
        WITH USER_MODE
        ORDER BY CreatedDate DESC, Id DESC
        LIMIT :AIAssistApplicationConstants.MAX_HISTORY_MESSAGES
      ];

      List<AIConversationMessage__c> keptMessages = new List<AIConversationMessage__c>();
      Integer charactersKept = 0;

      // The newest message is kept whatever its size; older ones are kept while they fit.
      for (AIConversationMessage__c historyMessage : newestFirst) {
        Integer messageLength = historyMessage.MessageBody__c == null
          ? 0
          : historyMessage.MessageBody__c.length();
        if (
          !keptMessages.isEmpty() &&
          charactersKept + messageLength >
          AIAssistApplicationConstants.MAX_HISTORY_CHARACTERS
        )
          break;
        keptMessages.add(historyMessage);
        charactersKept += messageLength;
      }

      // Walked backwards to put it oldest first: Apex has no List.reverse(), and add(0, x) throws on an empty list.
      List<AIConversationMessage__c> orderedHistory = new List<AIConversationMessage__c>();
      for (
        Integer keptIndex = keptMessages.size() - 1; keptIndex >= 0; keptIndex--
      )
        orderedHistory.add(keptMessages[keptIndex]);

      AIResponseRequest responseRequest = new AIResponseRequest();
      responseRequest.agent = agent;
      responseRequest.modelConfiguration = modelConfiguration;
      responseRequest.promptTemplate = promptTemplate;
      responseRequest.conversation = conversation;
      responseRequest.messageHistory = orderedHistory;
      responseRequest.dataSources = AIMessagingSelector.getAssignedDataSources(
        agent.Id
      );
      responseRequest.workflowActions = AIMessagingSelector.getAssignedActions(
        agent.Id
      );
      responseRequest.attemptNumber = attemptNumber;

      // Live progress follows the org-wide setting. Request and response payloads are captured only when the step capture mode is Full.
      responseRequest.trace = new AIExecutionStepTracker(
        conversationId,
        triggeringMessageId,
        AIAssistSettingsService.getUiSettings().ShowExecutionTraceToUser__c ==
        true,
        AIAssistSettingsService.getSettings().StepCaptureMode__c ==
        AIAssistApplicationConstants.STEP_CAPTURE_FULL
      );

      // [2]
      AIAgentManager.AgentResult agentResult = aiResponseExecutor.execute(
        responseRequest
      );

      agentResult.totalTokensUsed =
        (agentResult.totalTokensUsed == null
          ? 0
          : agentResult.totalTokensUsed) +
        priorInputTokens +
        priorOutputTokens;
      agentResult.inputTokens =
        (agentResult.inputTokens == null ? 0 : agentResult.inputTokens) +
        priorInputTokens;
      agentResult.outputTokens =
        (agentResult.outputTokens == null ? 0 : agentResult.outputTokens) +
        priorOutputTokens;
      tokensSoFar = agentResult.totalTokensUsed;
      finalizer.recordTokensSpent(
        agentResult.inputTokens,
        agentResult.outputTokens
      );

      // PII mappings created by tool calls were held in memory so they could not block the next callout. Every callout is done now, so save them before any other DML.
      AIPiiMappingService.isDeferringWrites = false;
      AIPiiMappingService.saveCached();

      // [3] A retry is scheduled by the finalizer once this job ends: a fresh job has fresh governor limits.
      if (agentResult.isRetryable) {
        finalizer.scheduleRetry(
          agentResult.inputTokens,
          agentResult.outputTokens
        );
        return;
      }

      AIMessageOutcomeService.recordAiResponseOutcome(
        responseContext,
        agentResult,
        responseRequest.trace
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIMessageProcessingQueueable',
        'execute'
      );
      AIMessageOutcomeService.recordAiResponseFailure(
        responseContext,
        tokensSoFar,
        caughtException.getMessage(),
        caughtException instanceof AIMessagingException
          ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
          : AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }
}
