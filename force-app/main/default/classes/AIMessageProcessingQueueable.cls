/*
Class Name: AIMessageProcessingQueueable

=================================================================
=================================================================

Description: The asynchronous worker that answers one message outside the user's transaction, running as the user who sent it.

Step 1: Attach the finalizer so retries, the next message and the lock release happen however the job ends
Step 2: Load the triggering message, and stand down if the conversation's lock has expired
Step 3: Load the conversation, agent, model connection, prompt, bounded history (noting any Suggested Action the user ran) and tools
Step 4: Run the turn through the AI Agent Manager and save any held PII mappings
Step 5: Hand a retryable result to the finalizer, otherwise record the outcome

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
1.1          Chandler Stuart          Message history now notes any Suggested Action the user ran or that failed (in memory only), so the model does not mistake the action's effect for its own earlier error.
*/

public without sharing class AIMessageProcessingQueueable implements Queueable, Database.AllowsCallouts {
  public class AIMessageProcessingQueueableException extends Exception {
  }

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

  // Answers the triggering message: loads the turn, runs it through the AI Agent Manager and records the outcome. No DML happens before the callout, because an uncommitted write makes every later callout in the transaction fail.
  public void execute(QueueableContext queueableContext) {
    Id userId = UserInfo.getUserId();

    // [1] Attach the finalizer first so it runs however this job ends, even on an uncatchable limit error. The context is null only when a test calls execute directly.
    AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(
      triggeringMessageId,
      conversationId,
      attemptNumber,
      userId
    );
    if (queueableContext != null)
      System.attachFinalizer(finalizer);

    // [2] Record the tokens earlier attempts spent now, so they are kept even if this job is killed.
    finalizer.recordTokensSpent(priorInputTokens, priorOutputTokens);

    AIMessageOutcomeService.AIResponseContext responseContext = finalizer.getResponseContext();
    Decimal tokensSoFar = priorInputTokens + priorOutputTokens;

    try {
      // [3] Reload the message that triggered this job, because only its Id crossed the asynchronous boundary. User mode, so the job acts for the user who sent it.
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

      // [4] The message was deleted after it was queued, so tell the chat window, which is still waiting on this turn.
      if (triggeringMessages.isEmpty()) {
        AIMessageOutcomeService.publishMessageFailure(
          conversationId,
          AIAssistApplicationConstants.FAILURE_REASON_MESSAGE_MISSING
        );
        return;
      }

      AIConversationMessage__c triggeringMessage = triggeringMessages[0];

      // [5] Stand down if the conversation's lock has expired, so this job does not run beside whatever took the conversation over. The check is read only.
      if (!AIConversationLockService.isConversationLocked(conversationId)) {
        finalizer.markLockExpired();
        return;
      }

      // [6] Load the conversation. A missing one is a setup problem, so it is logged once and thrown for the catch below to report as a configuration error.
      List<AIConversation__c> conversationRows = [
        SELECT Id, AIAgent__c, RelatedObjectAPIName__c, RelatedRecordId__c
        FROM AIConversation__c
        WHERE Id = :triggeringMessage.AIConversation__c
        WITH USER_MODE
        LIMIT 1
      ];

      if (conversationRows.isEmpty()) {
        AIPlatformLogManager.logCustomMessage(
          'AI Conversation not found for Id: ' +
          triggeringMessage.AIConversation__c,
          null,
          'AIMessageProcessingQueueable',
          'execute',
          null
        );
        throw new AIMessageProcessingQueueableException(Label.AI_Error_Generic);
      }

      AIConversation__c conversation = conversationRows[0];

      // [7] Load the agent, which the user may not be able to read, so it is read in system mode.
      AIAgent__c agent = getAgent(conversation.AIAgent__c);

      if (agent == null) {
        AIPlatformLogManager.logCustomMessage(
          'AI Agent not found for Id: ' + conversation.AIAgent__c,
          null,
          'AIMessageProcessingQueueable',
          'execute',
          null
        );
        throw new AIMessageProcessingQueueableException(Label.AI_Error_Generic);
      }

      // [8] Load the model connection for the agent.
      AIModelConfiguration__c modelConfiguration = getModelConfiguration(
        agent.AIModelConfiguration__c
      );

      if (modelConfiguration == null) {
        AIPlatformLogManager.logCustomMessage(
          'The AI Agent has no AI Model Configuration assigned.',
          null,
          'AIMessageProcessingQueueable',
          'execute',
          null
        );
        throw new AIMessageProcessingQueueableException(Label.AI_Error_Generic);
      }

      // [9] Load the active prompt template. Having none is fine: no system prompt is built.
      AIPromptTemplate__c promptTemplate = getActivePromptTemplate(agent.Id);

      // [10] Pass what is known about this turn to the outcome service, so it can record usage even if the turn fails.
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

      // [11] Load the newest messages up to and including the one being answered, within the count limit. Newest first so the limit keeps the latest. It stops at the triggering message by time and, within the same second, by Id, so the history ends with the question being answered. System messages are never shown to the model.
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

      // [12] Keep the newest message whatever its size, then older ones while they fit the character limit.
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

      // [13] Put the history oldest first by walking it backwards, because Apex has no List.reverse and add(0, x) throws on an empty list.
      List<AIConversationMessage__c> orderedHistory = new List<AIConversationMessage__c>();

      for (
        Integer keptIndex = keptMessages.size() - 1; keptIndex >= 0; keptIndex--
      ) {
        orderedHistory.add(keptMessages[keptIndex]);
      }

      // [14] Tell the model about any Suggested Action the user ran from an earlier reply. In memory only, so nothing saved changes.
      appendActionOutcomes(orderedHistory);

      // [15] Gather everything the AI Agent Manager needs for this attempt.
      AIResponseRequest responseRequest = new AIResponseRequest();
      responseRequest.agent = agent;
      responseRequest.modelConfiguration = modelConfiguration;
      responseRequest.promptTemplate = promptTemplate;
      responseRequest.conversation = conversation;
      responseRequest.messageHistory = orderedHistory;
      responseRequest.dataSources = getAssignedDataSources(agent.Id);
      responseRequest.workflowActions = getAssignedActions(agent.Id);
      responseRequest.attemptNumber = attemptNumber;

      // [16] Show live progress as the org-wide setting says, and capture request and response payloads only when the step capture mode is Full.
      responseRequest.trace = new AIExecutionStepTracker(
        conversationId,
        triggeringMessageId,
        AIAssistSettingsService.getUiSettings().ShowExecutionTraceToUser__c ==
        true,
        AIAssistSettingsService.getSettings().StepCaptureMode__c ==
        AIAssistApplicationConstants.STEP_CAPTURE_FULL
      );

      // [17] Run the turn through the AI Agent Manager.
      AIAgentManager.AgentResult agentResult = AIAgentManager.executeAiMessage(
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

      // [18] Add the tokens earlier attempts spent, so the result covers the whole turn.
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

      // [19] Save the PII mappings tool calls created. They were held in memory so they could not block the next callout, and every callout is done now.
      AIPiiMappingService.isDeferringWrites = false;
      AIPiiMappingService.saveCached();

      // [20] Leave a retryable result to the finalizer, which schedules a fresh job with fresh limits once this one ends.
      if (agentResult.isRetryable) {
        finalizer.scheduleRetry(
          agentResult.inputTokens,
          agentResult.outputTokens
        );
        return;
      }

      // [21] Record the outcome of the turn.
      AIMessageOutcomeService.recordAiResponseOutcome(
        responseContext,
        agentResult,
        responseRequest.trace
      );
    } catch (Exception ex) {
      // [22] Log the error and record the turn as failed. A System exception is Other, anything else is a configuration error.
      AIPlatformLogManager.logException(
        ex,
        'AIMessageProcessingQueueable',
        'execute'
      );
      AIMessageOutcomeService.recordAiResponseFailure(
        responseContext,
        tokensSoFar,
        ex.getMessage(),
        !ex.getTypeName().startsWith('System.')
          ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
          : AIAssistApplicationConstants.FAILURE_REASON_OTHER
      );
    }
  }

  // The model only sees message text, so a Suggested Action the user ran (or that failed) is invisible to it. It would see its own earlier reply next to a record the action has since changed, and wrongly decide the reply was a mistake. This adds the outcome to the end of that reply's body in memory only: the history is never saved, so the stored message does not change.
  @TestVisible
  private static void appendActionOutcomes(
    List<AIConversationMessage__c> historyMessages
  ) {
    // [1] Nothing to note without history
    Map<Id, AIConversationMessage__c> messagesById = new Map<Id, AIConversationMessage__c>(
      historyMessages
    );
    if (messagesById.isEmpty())
      return;

    // [2] Find the action steps recorded on these replies, oldest first, so a later step is noted after an earlier one
    for (AIExecutionStep__c actionStep : [
      SELECT
        AIConversationMessage__c,
        Status__c,
        AIWorkflowAction__r.ActionName__c
      FROM AIExecutionStep__c
      WHERE
        AIConversationMessage__c IN :messagesById.keySet()
        AND StepType__c = :AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION
        AND Status__c IN (
          :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS,
          :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED,
          :AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED
        )
      WITH SYSTEM_MODE
      ORDER BY CreatedDate, Id
    ]) {
      // [3] Name the action, then say whether it changed anything
      AIConversationMessage__c historyMessage = messagesById.get(
        actionStep.AIConversationMessage__c
      );
      String actionName = actionStep.AIWorkflowAction__r == null ||
        String.isBlank(actionStep.AIWorkflowAction__r.ActionName__c)
        ? 'the suggested action'
        : actionStep.AIWorkflowAction__r.ActionName__c;
      Boolean isSuccess =
        actionStep.Status__c ==
        AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;

      historyMessage.MessageBody__c =
        (historyMessage.MessageBody__c == null
          ? ''
          : historyMessage.MessageBody__c) +
        '\n\n[System note: the user ran "' +
        actionName +
        '" from this reply. ' +
        (isSuccess
          ? 'It completed successfully. Any change to the record since this reply is the result of that action, not an error in this reply.]'
          : 'It failed, so nothing was changed.]');
    }
  }

  // Gets the agent's active prompt template. None is valid, and with more than one active the most recently edited wins so the answer is stable.
  @TestVisible
  private static AIPromptTemplate__c getActivePromptTemplate(Id agentId) {
    // [1] Nothing to find without an agent
    if (agentId == null)
      return null;

    // [2] Query the newest active template, ignoring the user's access
    List<AIPromptTemplate__c> templates = [
      SELECT
        Id,
        AISystemContext__c,
        AIPrompt__c,
        AITone__c,
        AIExclusionRules__c,
        MaxResponseLength__c,
        Version__c
      FROM AIPromptTemplate__c
      WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ];

    return templates.isEmpty() ? null : templates[0];
  }

  // Gets the agent, ignoring the user's access.
  @TestVisible
  private static AIAgent__c getAgent(Id agentId) {
    // [1] Nothing to find without an Id
    if (agentId == null)
      return null;

    // [2] Query the agent
    List<AIAgent__c> agents = [
      SELECT
        Id,
        Name,
        DeveloperName__c,
        AIAgentPersona__c,
        IsActive__c,
        AccessMode__c,
        AIModelConfiguration__c,
        MaxMessagesPerConversation__c,
        MaxTokensPerConversation__c,
        MaxToolCallingIterations__c,
        SingleActiveConversationPerRecord__c,
        TokenTrackingMethod__c
      FROM AIAgent__c
      WHERE Id = :agentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return agents.isEmpty() ? null : agents[0];
  }

  // Gets the active workflow actions assigned to the agent, ignoring the user's access.
  @TestVisible
  private static List<AIWorkflowAction__c> getAssignedActions(Id agentId) {
    // [1] Nothing is assigned without an agent
    if (agentId == null)
      return new List<AIWorkflowAction__c>();

    // [2] Query through the junction, capped so an agent with hundreds of links cannot bloat every request
    return [
      SELECT
        Id,
        DeveloperName__c,
        Description__c,
        OutputDescription__c,
        InputSchema__c
      FROM AIWorkflowAction__c
      WHERE
        IsActive__c = TRUE
        AND Id IN (
          SELECT AIWorkflowAction__c
          FROM AIAgentWorkflowAction__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      ORDER BY DeveloperName__c
      LIMIT :AIAssistApplicationConstants.MAX_TOOLS_PER_KIND
    ];
  }

  // Gets the active data sources assigned to the agent, ignoring the user's access.
  @TestVisible
  private static List<AIDataSource__c> getAssignedDataSources(Id agentId) {
    // [1] Nothing is assigned without an agent
    if (agentId == null)
      return new List<AIDataSource__c>();

    // [2] Query through the junction, capped so an agent with hundreds of links cannot bloat every request
    return [
      SELECT
        Id,
        DeveloperName__c,
        Description__c,
        OutputDescription__c,
        InputSchema__c,
        MaxRows__c,
        TargetObject__c
      FROM AIDataSource__c
      WHERE
        IsActive__c = TRUE
        AND Id IN (
          SELECT AIDataSource__c
          FROM AIAgentDataSource__c
          WHERE AIAgent__c = :agentId AND IsActive__c = TRUE
        )
      WITH SYSTEM_MODE
      ORDER BY DeveloperName__c
      LIMIT :AIAssistApplicationConstants.MAX_TOOLS_PER_KIND
    ];
  }

  // Gets the model configuration, ignoring the user's access.
  @TestVisible
  private static AIModelConfiguration__c getModelConfiguration(
    Id modelConfigurationId
  ) {
    // [1] Nothing to find without an Id
    if (modelConfigurationId == null)
      return null;

    // [2] Query the model configuration
    List<AIModelConfiguration__c> configurations = [
      SELECT
        Id,
        Name,
        AIProvider__c,
        ModelIdentifier__c,
        NamedCredential__c,
        ApiPath__c,
        ApiVersionHeaderName__c,
        ApiVersionHeaderValue__c,
        MaximumOutputTokens__c,
        Temperature__c
      FROM AIModelConfiguration__c
      WHERE Id = :modelConfigurationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    return configurations.isEmpty() ? null : configurations[0];
  }
}
