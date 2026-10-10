/*
Class Name: AIAgentManager

=================================================================
=================================================================

Description: Owns the conversation with the AI provider for one turn. It only makes the
callouts and returns an AgentResult describing what happened. It never inserts, updates or
publishes a record; the caller (AIMessageProcessingQueueable) hands the result to
AIMessageOutcomeService, which does.

Flow (the numbered comments in executeAiMessage):
[1] Check the model configuration and get the provider's request builder and response handler
    (AIProvider): the only classes that know a provider's JSON shape.
[2] Turn the agent's data sources into tools, the conversation into the provider's messages and
    the prompt template into the system prompt.
[3] Resolve the run limits: tool-calling iterations, tool calls per reply, retry attempts, callout
    timeout.
[4] Tool-calling loop: send the request; either return the final reply, or run the tools the
    model asked for and send their results back on the next pass. A callout that fails or comes
    back with a retryable status, with attempts left, returns isRetryable = true. This class
    never schedules a retry (AIMessageProcessingFinalizer does).

On the last allowed iteration the model is sent the request with tool calls disabled, so it
must answer with what it has.

What the model is sent, and what it is not:
- The callout is pinned to the Named Credential on the agent's model configuration. Nothing the
  user or the model says can change the endpoint, and the credential name and path are checked
  for shape again here.
- A request is never sent if masking failed for any value in it.
- A failed tool reaches the model only as a generic message; the real error, which can hold
  SOQL, record Ids or field values, stays in the log.
- Workflow actions are described as suggestions only. They are never run here.

Evidence: every data source read and provider call is a step on the tracker. A provider call
step records the provider and model, how many records and fields went (names only), and which
fields were masked, by what strategy.

PII mappings are deferred while the loop runs; the caller must call AIPiiMappingService.saveCached()
after this returns, or they are lost.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model: failure reasons, input and output tokens, latency, provider and masking evidence on the steps, masking failure stops the request, data sources checked against the agent, user-facing step text from Custom Labels, single-use helpers inlined.
3.0          Chandler Stuart          The system prompt tells the model to reply in the user's Salesforce language.
*/

public inherited sharing class AIAgentManager {
  private static final Integer DEFAULT_MAX_OUTPUT_TOKENS = 1024;

  public class AIAgentManagerException extends Exception {
  }

  // Always returned, never null. isSuccessful and isRetryable tell the caller which update to make; this class makes none.
  public class AgentResult {
    public Boolean isSuccessful = false;
    public String replyText;
    public Decimal totalTokensUsed = 0;
    public Decimal inputTokens = 0;
    public Decimal outputTokens = 0;
    public Decimal latencyMilliseconds;
    public Boolean isRetryable = false;
    public String errorMessage; // For the log only: it can hold configuration or provider text and must never reach the user.
    public String failureReason; // An AIConversationMessage__c.FailureReason__c value.
    public String suggestedWorkflowActionId;
  }

  // Runs one turn, starting at attemptNumber (1 for the first; the caller adds one for each retry). Every argument is loaded by the caller: this class issues no SOQL.
  // messageHistory must end with the message being answered. trace is filled in as the turn runs; the caller already holds it.
  public static AgentResult executeAiMessage(
    AIAgent__c agent,
    AIModelConfiguration__c modelConfiguration,
    AIPromptTemplate__c promptTemplate,
    AIConversation__c conversation,
    List<AIConversationMessage__c> messageHistory,
    List<AIDataSource__c> availableDataSources,
    List<AIWorkflowAction__c> availableWorkflowActions,
    Integer attemptNumber,
    AIExecutionStepTracker trace
  ) {
    Long turnStartMilliseconds = System.currentTimeMillis();
    Decimal totalTokensUsed = 0; // Declared outside the try so every failure result reports the tokens already spent.
    Decimal inputTokensUsed = 0;
    Decimal outputTokensUsed = 0;

    try {
      // PII masked by tool calls must not be written mid-loop: uncommitted DML blocks the next callout. The caller saves them afterwards.
      AIPiiMappingService.isDeferringWrites = true;

      if (trace == null)
        trace = new AIExecutionStepTracker(
          conversation == null ? null : conversation.Id,
          null,
          false,
          false
        );

      // [1] Configuration.
      if (agent == null || modelConfiguration == null)
        throw new AIAgentManagerException(
          'The agent or its model configuration is missing.'
        );
      if (
        String.isBlank(modelConfiguration.NamedCredential__c) ||
        String.isBlank(modelConfiguration.ApiPath__c)
      )
        throw new AIAgentManagerException(
          'Model configuration "' +
            modelConfiguration.Name +
            '" has no Named Credential or API path.'
        );
      if (
        !Pattern.matches(
          '^[A-Za-z][A-Za-z0-9_]*$',
          modelConfiguration.NamedCredential__c
        )
      )
        throw new AIAgentManagerException(
          'Model configuration "' +
            modelConfiguration.Name +
            '" has a Named Credential name of the wrong shape.'
        );
      if (
        !Pattern.matches(
          '^/[A-Za-z0-9/_.~%?=&:-]*$',
          modelConfiguration.ApiPath__c
        ) ||
        modelConfiguration.ApiPath__c.contains('..') ||
        modelConfiguration.ApiPath__c.contains('//')
      )
        throw new AIAgentManagerException(
          'Model configuration "' +
            modelConfiguration.Name +
            '" has an API path of the wrong shape.'
        );
      if (!AIProvider.isSupported(modelConfiguration.AIProvider__c))
        throw new AIAgentManagerException(
          'Model configuration "' +
            modelConfiguration.Name +
            '" has an unsupported provider "' +
            modelConfiguration.AIProvider__c +
            '".'
        );

      IAIProviderRequestBuilder providerRequestBuilder = AIProvider.getRequestBuilder(
        modelConfiguration.AIProvider__c
      );
      IAIProviderResponseHandler providerResponseHandler = AIProvider.getResponseHandler(
        modelConfiguration.AIProvider__c
      );

      // [2] Tools: each data source, advertised by name. InputSchema__c is only advertised here; the dispatcher refuses bad input.
      Map<String, AIDataSource__c> dataSourceByToolName = new Map<String, AIDataSource__c>();
      List<AIProvider.ToolDefinition> toolDefinitions = new List<AIProvider.ToolDefinition>();

      for (
        AIDataSource__c dataSource : availableDataSources == null
          ? new List<AIDataSource__c>()
          : availableDataSources
      ) {
        if (
          String.isBlank(dataSource.DeveloperName__c) ||
          dataSourceByToolName.containsKey(dataSource.DeveloperName__c)
        )
          continue;
        dataSourceByToolName.put(dataSource.DeveloperName__c, dataSource);

        AIProvider.ToolDefinition toolDefinition = new AIProvider.ToolDefinition();
        toolDefinition.name = dataSource.DeveloperName__c;
        toolDefinition.description = String.isNotBlank(
            dataSource.Description__c
          )
          ? dataSource.Description__c
          : (String.isNotBlank(dataSource.OutputDescription__c)
              ? dataSource.OutputDescription__c
              : dataSource.DeveloperName__c); // Providers expect a string.
        toolDefinition.inputSchema = String.isNotBlank(
            dataSource.InputSchema__c
          )
          ? (Map<String, Object>) JSON.deserializeUntyped(
              dataSource.InputSchema__c
            )
          : new Map<String, Object>{
              'type' => 'object',
              'properties' => new Map<String, Object>()
            };
        toolDefinitions.add(toolDefinition);
      }

      // The conversation the model sees. System messages are internal records, not something the user or model said, and a provider rejects a blank message, so one blank message would fail every later turn.
      // The response handler appends the model's replies and tool results to this same list as the loop runs.
      List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

      for (
        AIConversationMessage__c historyMessage : messageHistory == null
          ? new List<AIConversationMessage__c>()
          : messageHistory
      ) {
        if (
          historyMessage.Sender__c ==
          AIAssistApplicationConstants.SENDER_SYSTEM ||
          String.isBlank(historyMessage.MessageBody__c)
        )
          continue;

        providerMessages.add(
          new Map<String, Object>{
            AIAssistApplicationConstants.CANONICAL_ROLE_KEY => historyMessage.Sender__c ==
              AIAssistApplicationConstants.SENDER_USER
              ? AIAssistApplicationConstants.CANONICAL_ROLE_USER
              : AIAssistApplicationConstants.CANONICAL_ROLE_ASSISTANT,
            AIAssistApplicationConstants.CANONICAL_CONTENT_KEY => historyMessage.MessageBody__c
          }
        );
      }

      // The system prompt: who the agent is, the template, then a compact list of workflow actions the model may suggest, never run.
      List<String> systemPromptParts = new List<String>();

      if (String.isNotBlank(agent.AIAgentPersona__c))
        systemPromptParts.add('Persona: ' + agent.AIAgentPersona__c);

      if (promptTemplate != null) {
        if (String.isNotBlank(promptTemplate.AISystemContext__c))
          systemPromptParts.add(promptTemplate.AISystemContext__c);
        if (String.isNotBlank(promptTemplate.AIPrompt__c))
          systemPromptParts.add(promptTemplate.AIPrompt__c);
        if (String.isNotBlank(promptTemplate.AITone__c))
          systemPromptParts.add('Tone: ' + promptTemplate.AITone__c);
        if (String.isNotBlank(promptTemplate.AIExclusionRules__c))
          systemPromptParts.add(
            'Do not: ' + promptTemplate.AIExclusionRules__c
          );
      }

      // Replies match the user. Labels are translated by the platform; agent text is not, so the model is told. A turn runs as the user who sent the message, so this is their language.
      systemPromptParts.add(
        String.format(
          AIAssistApplicationConstants.LANGUAGE_PROMPT_INSTRUCTION,
          new List<String>{ UserInfo.getLanguage() }
        )
      );

      if (
        availableWorkflowActions != null && !availableWorkflowActions.isEmpty()
      ) {
        systemPromptParts.add(
          AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_INSTRUCTION
        );
        for (AIWorkflowAction__c workflowAction : availableWorkflowActions)
          systemPromptParts.add(
            workflowAction.DeveloperName__c +
              ': ' +
              (String.isNotBlank(workflowAction.Description__c)
                ? workflowAction.Description__c
                : workflowAction.OutputDescription__c)
          );
        systemPromptParts.add(
          AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION
        );
      }

      // Blank lines and repeated spaces collapsed to keep token usage down on every pass; single line breaks stay so authored lists remain readable.
      String systemPromptText = systemPromptParts.isEmpty()
        ? null
        : String.join(systemPromptParts, '\n')
            .replaceAll('[ \\t]*\\n\\s*', '\n')
            .replaceAll('[ \\t]+', ' ')
            .trim();

      // [3] Run limits. Iterations: the agent's own, else the org default, clamped to 1..cap (0 would skip the callout; unbounded risks the 100 callout limit).
      AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
      Integer maxToolCallingIterations = Math.max(
        1,
        Math.min(
          agent.MaxToolCallingIterations__c == null
            ? settings.DefaultMaxToolCallingIterations__c.intValue()
            : agent.MaxToolCallingIterations__c.intValue(),
          settings.MaxToolCallingIterationsCap__c.intValue()
        )
      );
      Integer maxAttempts = 1 + settings.RetryAttempts__c.intValue();
      Integer maxToolCallsPerIteration = settings.MaxToolCallsPerIteration__c.intValue();
      Integer maxOutputTokens = modelConfiguration.MaximumOutputTokens__c ==
        null
        ? DEFAULT_MAX_OUTPUT_TOKENS
        : modelConfiguration.MaximumOutputTokens__c.intValue();
      Integer configuredTimeoutMilliseconds = settings.CalloutTimeoutMilliseconds__c.intValue();
      String endpoint =
        'callout:' +
        modelConfiguration.NamedCredential__c +
        modelConfiguration.ApiPath__c;

      trace.toolCallingIterationsMax = maxToolCallingIterations;
      trace.attemptNumber = attemptNumber;

      // Tool calls from the pass just finished, handed to the response handler at the top of the next pass because they join providerMessages before that pass's request is built.
      List<AIProvider.ToolCall> previousToolCalls = null;
      List<Object> previousToolResults = null;

      // What the tools returned and what was masked since the last provider call: the evidence on the next provider call step.
      Integer recordsSent = 0;
      Set<String> objectsSent = new Set<String>();
      Set<String> fieldsSent = new Set<String>();
      List<AIPiiPseudonymizationService.MaskingTally> pendingMasking = new List<AIPiiPseudonymizationService.MaskingTally>();

      // Set when a callout cannot complete; the loop breaks and one retryable-or-failed result is returned after it.
      String calloutErrorMessage = null;
      String calloutFailureReason = AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
      Boolean isCalloutErrorRetryable = true;

      // [4] Tool-calling loop.
      for (
        Integer iteration = 0; iteration < maxToolCallingIterations; iteration++
      ) {
        Boolean isLastIteration = iteration == maxToolCallingIterations - 1;

        if (previousToolCalls != null) {
          providerResponseHandler.handleResponse(
            providerMessages,
            null,
            previousToolCalls,
            previousToolResults
          );
          previousToolCalls = null;
          previousToolResults = null;
        }

        // A request is never sent if masking failed for any value in it.
        pendingMasking.addAll(AIPiiPseudonymizationService.takeTallies());
        for (AIPiiPseudonymizationService.MaskingTally tally : pendingMasking) {
          if (
            tally.outcome == AIAssistApplicationConstants.MASKING_OUTCOME_FAILED
          ) {
            AgentResult maskingFailure = new AgentResult();
            maskingFailure.errorMessage =
              'Masking failed for ' +
              tally.sourceObject +
              '.' +
              tally.sourceField +
              '; the request was not sent.';
            maskingFailure.failureReason = AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED;
            maskingFailure.totalTokensUsed = totalTokensUsed;
            maskingFailure.inputTokens = inputTokensUsed;
            maskingFailure.outputTokens = outputTokensUsed;
            return maskingFailure;
          }
        }

        AIProvider.Request canonicalRequest = new AIProvider.Request();
        canonicalRequest.modelIdentifier = modelConfiguration.ModelIdentifier__c;
        canonicalRequest.maxOutputTokens = maxOutputTokens;
        canonicalRequest.temperature = modelConfiguration.Temperature__c;
        canonicalRequest.systemPromptText = systemPromptText;
        canonicalRequest.messages = providerMessages;
        canonicalRequest.tools = toolDefinitions;
        canonicalRequest.allowToolCalls = !isLastIteration; // The last chance: the model must answer with what it has.

        String requestBody = JSON.serialize(
          providerRequestBuilder.buildRequestBody(canonicalRequest)
        );

        // Payloads are customer data, kept only for a user with debug mode on. They are already masked.
        if (trace.captureFullDetail) {
          trace.lastRequestJson = requestBody;

          for (
            Integer messageIndex = providerMessages.size() - 1;
            messageIndex >= 0;
            messageIndex--
          ) {
            Map<String, Object> message = providerMessages[messageIndex];
            if (
              String.valueOf(
                message.get(AIAssistApplicationConstants.CANONICAL_ROLE_KEY)
              ) == AIAssistApplicationConstants.CANONICAL_ROLE_USER
            ) {
              trace.sentPreviewText = String.isBlank(
                  String.valueOf(
                    message.get(
                      AIAssistApplicationConstants.CANONICAL_CONTENT_KEY
                    )
                  )
                )
                ? null
                : String.valueOf(
                      message.get(
                        AIAssistApplicationConstants.CANONICAL_CONTENT_KEY
                      )
                    )
                    .abbreviate(200);
              break;
            }
          }
        }

        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint(endpoint);
        httpRequest.setMethod(AIAssistApplicationConstants.HTTP_METHOD_POST);
        httpRequest.setHeader(
          AIAssistApplicationConstants.HTTP_HEADER_CONTENT_TYPE,
          AIAssistApplicationConstants.CONTENT_TYPE_JSON
        );
        if (String.isNotBlank(modelConfiguration.ApiVersionHeaderName__c))
          httpRequest.setHeader(
            modelConfiguration.ApiVersionHeaderName__c,
            modelConfiguration.ApiVersionHeaderValue__c
          );
        httpRequest.setTimeout(configuredTimeoutMilliseconds);
        httpRequest.setBody(requestBody);

        HttpResponse httpResponse;
        trace.startStep(Label.AI_Step_Calling_Model, null);

        try {
          httpResponse = new Http().send(httpRequest);
        } catch (Exception calloutException) {
          AIExecutionStepTracker.StepEntry failedStep = trace.endStep(false);
          if (failedStep != null) {
            failedStep.provider = modelConfiguration.AIProvider__c;
            failedStep.modelIdentifier = modelConfiguration.ModelIdentifier__c;
          }

          // Logged here because it becomes a result rather than being rethrown.
          AIPlatformLogManager.logException(
            calloutException,
            'AIAgentManager',
            'executeAiMessage'
          );
          String calloutDetail = calloutException.getMessage() == null
            ? ''
            : calloutException.getMessage();
          // An endpoint the org does not allow, or a Named Credential that is missing, fails the same way every time: a setup problem, not retried.
          Boolean isSetupProblem =
            calloutDetail.containsIgnoreCase('unauthorized endpoint') ||
            calloutDetail.containsIgnoreCase('named credential');
          calloutErrorMessage = isSetupProblem
            ? 'The AI provider could not be called: ' +
              calloutDetail +
              ' Check Named Credential "' +
              modelConfiguration.NamedCredential__c +
              '" on AI Model Configuration ' +
              modelConfiguration.Id +
              '.'
            : 'AI provider callout failed: ' + calloutDetail;
          calloutFailureReason = isSetupProblem
            ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
            : (calloutDetail.containsIgnoreCase('timed out')
                ? AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
                : AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR);
          isCalloutErrorRetryable = !isSetupProblem;
          break;
        }

        // The provider call step: what was sent (names and counts, never values), under which model, and what was masked.
        AIExecutionStepTracker.StepEntry providerStep = trace.endStep(true);
        providerStep.provider = modelConfiguration.AIProvider__c;
        providerStep.modelIdentifier = modelConfiguration.ModelIdentifier__c;
        providerStep.recordsSentCount = recordsSent;
        providerStep.fieldsSentCount = fieldsSent.size();
        providerStep.objectsSent = String.join(
          new List<String>(objectsSent),
          ', '
        );
        providerStep.fieldsSent = String.join(
          new List<String>(fieldsSent),
          ', '
        );
        trace.addMaskingTallies(providerStep, pendingMasking);
        pendingMasking = new List<AIPiiPseudonymizationService.MaskingTally>();
        recordsSent = 0;
        objectsSent.clear();
        fieldsSent.clear();

        trace.toolCallingIterationsUsed = iteration + 1;
        if (trace.captureFullDetail)
          trace.lastResponseJson = httpResponse.getBody();

        // Any status that is not a success ends this attempt with a reason the user can be told and a message that says which record to fix. It is retried only when the status is listed in AIAssistSettings__c.RetryableStatusCodes__c and could succeed next time: a rejected credential, a retired model, an exhausted quota and a bad request never are.
        Integer statusCode = httpResponse.getStatusCode();
        if (
          !toIntegerSet(settings.AIProviderSuccessStatusCodes__c)
            .contains(statusCode)
        ) {
          providerStep.isSuccess = false;
          calloutFailureReason = AIProvider.getFailureReason(
            statusCode,
            httpResponse.getBody()
          );
          Boolean isCredentialRejected =
            calloutFailureReason ==
            AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED;
          Boolean isModelRetired =
            calloutFailureReason ==
            AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED;
          isCalloutErrorRetryable =
            toIntegerSet(settings.RetryableStatusCodes__c)
              .contains(statusCode) &&
            !AIAssistApplicationConstants.NEVER_RETRIED_STATUS_CODES.contains(
              statusCode
            ) &&
            !isCredentialRejected &&
            !isModelRetired;
          calloutErrorMessage =
            'AI provider returned ' +
            (isCalloutErrorRetryable ? 'a retryable ' : '') +
            'HTTP status ' +
            statusCode +
            ' (' +
            calloutFailureReason +
            '). ' +
            (isCredentialRejected
              ? 'The credential or the account was rejected: check the API key and billing behind Named Credential "' +
                modelConfiguration.NamedCredential__c +
                '" on AI Model Configuration ' +
                modelConfiguration.Id +
                '. '
              : (isModelRetired
                  ? 'Model "' +
                    modelConfiguration.ModelIdentifier__c +
                    '" is not available: update Model Identifier on AI Model Configuration ' +
                    modelConfiguration.Id +
                    '. '
                  : '')) +
            'Provider said: ' +
            (String.isBlank(httpResponse.getBody())
              ? '(nothing)'
              : httpResponse.getBody().abbreviate(1000));
          break;
        }

        // Parse the reply. A malformed body throws: a hard failure, caught and logged below.
        AIProvider.Response modelResponse = providerResponseHandler.handleResponse(
          providerMessages,
          httpResponse,
          null,
          null
        );
        totalTokensUsed += modelResponse.totalTokens;
        inputTokensUsed += modelResponse.inputTokens;
        outputTokensUsed += modelResponse.outputTokens;

        // No tool calls: this is the model's final reply.
        if (modelResponse.toolCalls.isEmpty()) {
          AgentResult successResult = new AgentResult();
          successResult.totalTokensUsed = totalTokensUsed;
          successResult.inputTokens = inputTokensUsed;
          successResult.outputTokens = outputTokensUsed;
          successResult.latencyMilliseconds =
            System.currentTimeMillis() - turnStartMilliseconds;
          successResult.replyText = modelResponse.textContent;

          if (String.isBlank(modelResponse.textContent)) {
            successResult.errorMessage = 'The provider returned an empty reply.';
            successResult.failureReason = AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
            return successResult;
          }

          successResult.isSuccessful = true;

          // A trailing {"suggested_workflow_action": "<DeveloperName>"} line names a workflow action. Only one that was offered is accepted; the line is stripped from the visible reply unless it was the whole reply (a blank reply would be rejected by the next request). Anything wrong leaves the reply untouched.
          Integer suggestionStart = modelResponse.textContent.lastIndexOf('{');

          if (
            suggestionStart >= 0 &&
            modelResponse.textContent.substring(suggestionStart)
              .contains(
                AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY
              ) &&
            availableWorkflowActions != null
          ) {
            try {
              Map<String, Object> suggestion = (Map<String, Object>) JSON.deserializeUntyped(
                modelResponse.textContent.substring(suggestionStart)
              );
              String suggestedDeveloperName = (String) suggestion.get(
                AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY
              );

              for (
                AIWorkflowAction__c workflowAction : availableWorkflowActions
              ) {
                if (workflowAction.DeveloperName__c == suggestedDeveloperName) {
                  successResult.suggestedWorkflowActionId = workflowAction.Id;
                  String replyWithoutSuggestion = modelResponse.textContent.substring(
                      0,
                      suggestionStart
                    )
                    .trim();
                  successResult.replyText = String.isNotBlank(
                      replyWithoutSuggestion
                    )
                    ? replyWithoutSuggestion
                    : Label.AI_Chat_Suggested_Actions_Heading;
                  break;
                }
              }
            } catch (Exception suggestionException) {
              AIPlatformLogManager.logException(
                suggestionException,
                'AIAgentManager',
                'executeAiMessage'
              );
            }
          }

          return successResult;
        }

        // Tool calls were disabled on the last iteration, so this only happens if the provider ignored that. Their results could never be sent back.
        if (isLastIteration)
          break;

        // Run the requested tools. Every call gets a result, because providers reject a reply that leaves one unanswered; a skipped call gets an explanation instead of being dropped.
        List<Object> toolResults = new List<Object>();

        for (
          Integer toolIndex = 0;
          toolIndex < modelResponse.toolCalls.size();
          toolIndex++
        ) {
          AIProvider.ToolCall toolCall = modelResponse.toolCalls[toolIndex];

          if (toolIndex >= maxToolCallsPerIteration) {
            toolResults.add(
              AIAssistApplicationConstants.TOOL_RESULT_SKIPPED_TOO_MANY_CALLS
            );
            continue;
          }
          AIDataSource__c dataSource = dataSourceByToolName.get(toolCall.name);
          trace.startStep(
            Label.AI_Step_Reading_Data,
            dataSource == null ? null : dataSource.Id
          );

          Object toolResult;
          Boolean toolSucceeded = true;

          // A failing tool does not end the turn: it is logged and the model is told it failed, so it can react. The model gets only a generic message because it is a third party.
          try {
            if (dataSource == null)
              throw new AIAgentManagerException(
                'The model requested an unknown tool "' + toolCall.name + '".'
              );

            List<Object> toolRecords = AIDataSourceDispatcher.runDataSource(
              dataSource.Id,
              agent.Id,
              String.isBlank(conversation.RelatedRecordId__c)
                ? null
                : (Id) conversation.RelatedRecordId__c,
              toolCall.arguments,
              conversation.Id
            );

            if (toolRecords == null || toolRecords.isEmpty()) {
              toolResult = AIAssistApplicationConstants.TOOL_RESULT_NO_RECORDS_FOUND; // Explicit, so the model reads a genuine no-match and stops retrying.
            } else {
              toolResult = toolRecords;
              recordsSent += toolRecords.size();
              if (String.isNotBlank(dataSource.TargetObject__c))
                objectsSent.add(dataSource.TargetObject__c);
              for (Object toolRecord : toolRecords) {
                if (toolRecord instanceof Map<String, Object>) {
                  for (
                    String fieldName : ((Map<String, Object>) toolRecord)
                      .keySet()
                  )
                    fieldsSent.add(
                      (String.isBlank(dataSource.TargetObject__c)
                        ? ''
                        : dataSource.TargetObject__c + '.') + fieldName
                    );
                }
              }
            }
          } catch (Exception toolException) {
            AIPlatformLogManager.logException(
              toolException,
              'AIAgentManager',
              'executeAiMessage'
            );
            toolResult = AIAssistApplicationConstants.TOOL_RESULT_FAILED;
            toolSucceeded = false;
          }

          AIExecutionStepTracker.StepEntry toolStep = trace.endStep(
            toolSucceeded
          );
          if (toolStep != null) {
            toolStep.stepType = AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE; // A tool the model made up still ran as a data source phase, not as a provider call.
            toolStep.targetObject = dataSource == null
              ? null
              : dataSource.TargetObject__c;
          }
          toolResults.add(toolResult);
        }

        previousToolCalls = modelResponse.toolCalls;
        previousToolResults = toolResults;
      }

      // A callout could not complete: retryable while attempts remain. Carries the tokens already spent so the retry adds to them.
      if (calloutErrorMessage != null) {
        AgentResult calloutFailure = new AgentResult();
        calloutFailure.errorMessage = calloutErrorMessage;
        calloutFailure.failureReason = calloutFailureReason;
        calloutFailure.totalTokensUsed = totalTokensUsed;
        calloutFailure.inputTokens = inputTokensUsed;
        calloutFailure.outputTokens = outputTokensUsed;
        calloutFailure.isRetryable =
          isCalloutErrorRetryable && attemptNumber < maxAttempts;
        return calloutFailure;
      }

      AgentResult limitFailure = new AgentResult();
      limitFailure.errorMessage =
        'Reached the maximum of ' +
        maxToolCallingIterations +
        ' tool-calling iterations without a final response.';
      limitFailure.failureReason = AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED;
      limitFailure.totalTokensUsed = totalTokensUsed;
      limitFailure.inputTokens = inputTokensUsed;
      limitFailure.outputTokens = outputTokensUsed;
      return limitFailure;
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIAgentManager',
        'executeAiMessage'
      );

      AgentResult failure = new AgentResult();
      failure.errorMessage =
        'Failed to get a response from the AI provider: ' +
        caughtException.getMessage();
      failure.totalTokensUsed = totalTokensUsed; // Tokens already spent are still billed.
      failure.inputTokens = inputTokensUsed;
      failure.outputTokens = outputTokensUsed;
      failure.failureReason = caughtException instanceof AIAgentManagerException ||
        caughtException instanceof AIAssistSettingsService.AIAssistSettingsServiceException
        ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR
        : (caughtException.getTypeName().contains('ResponseHandlerException') ||
            caughtException instanceof AIProvider.AIProviderException
            ? AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
            : AIAssistApplicationConstants.FAILURE_REASON_OTHER);
      return failure;
    } finally {
      // Deferral only applies while the loop runs. The mappings stay cached in memory; the caller must still save them.
      AIPiiMappingService.isDeferringWrites = false;
    }
  }

  // A comma separated setting such as "200,201" as a set of numbers. Entries that are not numbers are skipped.
  private static Set<Integer> toIntegerSet(String commaSeparatedNumbers) {
    Set<Integer> numbers = new Set<Integer>();

    if (String.isBlank(commaSeparatedNumbers))
      return numbers;

    for (String entry : commaSeparatedNumbers.split(',')) {
      if (entry.trim().isNumeric())
        numbers.add(Integer.valueOf(entry.trim()));
    }

    return numbers;
  }
}
