/*
Class Name: AIAgentManager

=================================================================
=================================================================

Description: Runs one conversation turn with the AI provider. It only makes the callouts and returns an AgentResult; it never inserts, updates or publishes a record.

Step 1: Check the model configuration and get the provider's request builder and response handler
Step 2: Turn the data sources (and, when the user chose no template, the other prompt templates) into tools, the conversation into provider messages and the prompt template into the system prompt
Step 3: Work out the run limits (tool-calling iterations, tool calls per reply, retry attempts, callout timeout)
Step 4: Send the request in a loop, running any tools the model asks for, until it gives a final reply
Step 5: Return an AgentResult saying whether the turn worked, failed, or can be retried

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentManager {

    public class AIAgentManagerException extends Exception {}

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
        public Id selectedPromptTemplateId; // Set only when the model switched to another prompt template, so the reply records the one that produced it.
        public Decimal selectedPromptTemplateVersion;
        public String externalReference; // Set only when the provider keeps the conversation (the Anthropic Agent API session id), so the caller can save it on the conversation. Null for every other provider.
    }

    private static final Integer DEFAULT_MAX_OUTPUT_TOKENS = 1024;

    // Runs one turn, starting at attemptNumber (1 for the first; the caller adds one for each retry). Every argument is loaded by the caller, so this class issues no SOQL. routingPromptTemplates are the other templates the model may switch to (none when the user chose a template). messageHistory must end with the message being answered. trace is filled in as the turn runs.
    public static AgentResult executeAiMessage(AIAgent__c agent, AIModelConfiguration__c modelConfiguration, AIPromptTemplate__c promptTemplate, List<AIPromptTemplate__c> routingPromptTemplates, AIConversation__c conversation, List<AIConversationMessage__c> messageHistory, List<AIDataSource__c> availableDataSources, List<AIWorkflowAction__c> availableWorkflowActions, Integer attemptNumber, AIExecutionStepTracker trace) {

        Long turnStartMilliseconds = System.currentTimeMillis();
        Decimal totalTokensUsed = 0; // Declared outside the try so every failure result reports the tokens already spent.
        Decimal inputTokensUsed = 0;
        Decimal outputTokensUsed = 0;
        AIPromptTemplate__c selectedPromptTemplate; // Set when the model switches template, and recorded on the reply.
        AIProvider.Session providerSession = new AIProvider.Session(); // Stays empty for a provider answered by one callout. Declared outside the try so every result can carry the session id.

        try {

            // [1] Hold back PII mapping saves while the loop runs, because unsaved changes would block the next callout. The caller saves them afterwards.
            AIPiiMappingService.isDeferringWrites = true;

            // [2] Make a tracker if the caller did not pass one
            if (trace == null) trace = new AIExecutionStepTracker(conversation == null ? null : conversation.Id, null, false, false);

            // [3] Check the agent and model configuration are usable, and that the Named Credential and API path look right
            if (agent == null || modelConfiguration == null) throw new AIAgentManagerException('The agent or its model configuration is missing.');
            if (String.isBlank(modelConfiguration.NamedCredential__c) || String.isBlank(modelConfiguration.ApiPath__c)) throw new AIAgentManagerException('Model configuration "' + modelConfiguration.Name + '" has no Named Credential or API path.');
            if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', modelConfiguration.NamedCredential__c)) throw new AIAgentManagerException('Model configuration "' + modelConfiguration.Name + '" has a Named Credential name of the wrong shape.');
            if (!Pattern.matches('^/[A-Za-z0-9/_.~%?=&:-]*$', modelConfiguration.ApiPath__c) || modelConfiguration.ApiPath__c.contains('..') || modelConfiguration.ApiPath__c.contains('//')) throw new AIAgentManagerException('Model configuration "' + modelConfiguration.Name + '" has an API path of the wrong shape.');
            if (!AIProvider.isSupported(modelConfiguration.AIProvider__c)) throw new AIAgentManagerException('Model configuration "' + modelConfiguration.Name + '" has an unsupported provider "' + modelConfiguration.AIProvider__c + '".');

            // [4] Get the request builder and response handler for this provider
            IAIProviderRequestBuilder providerRequestBuilder = AIProvider.getRequestBuilder(modelConfiguration.AIProvider__c);
            IAIProviderResponseHandler providerResponseHandler = AIProvider.getResponseHandler(modelConfiguration.AIProvider__c);

            // [5] Turn each data source into a tool the model can ask for by name. The input schema is only passed on here; the dispatcher refuses bad input later.
            Map<String, AIDataSource__c> dataSourceByToolName = new Map<String, AIDataSource__c>();
            List<AIProvider.ToolDefinition> toolDefinitions = new List<AIProvider.ToolDefinition>();

            for (AIDataSource__c dataSource : availableDataSources == null ? new List<AIDataSource__c>() : availableDataSources) {

                if (String.isBlank(dataSource.DeveloperName__c) || dataSourceByToolName.containsKey(dataSource.DeveloperName__c)) continue;

                dataSourceByToolName.put(dataSource.DeveloperName__c, dataSource);

                AIProvider.ToolDefinition toolDefinition = new AIProvider.ToolDefinition();
                toolDefinition.name = dataSource.DeveloperName__c;
                toolDefinition.description = String.isNotBlank(dataSource.Description__c) ? dataSource.Description__c : (String.isNotBlank(dataSource.OutputDescription__c) ? dataSource.OutputDescription__c : dataSource.DeveloperName__c); // Providers expect a string.
                toolDefinition.inputSchema = String.isNotBlank(dataSource.InputSchema__c) ? (Map<String, Object>) JSON.deserializeUntyped(dataSource.InputSchema__c) : new Map<String, Object>{'type' => 'object', 'properties' => new Map<String, Object>()};

                toolDefinitions.add(toolDefinition);
            }

            // [6] Build the conversation the model sees. System messages are internal records and blank messages are rejected by providers, so both are left out. The response handler adds the model's replies and tool results to this same list as the loop runs.
            List<Map<String, Object>> providerMessages = new List<Map<String, Object>>();

            for (AIConversationMessage__c historyMessage : messageHistory == null ? new List<AIConversationMessage__c>() : messageHistory) {

                if (historyMessage.Sender__c == AIAssistApplicationConstants.SENDER_SYSTEM || String.isBlank(historyMessage.MessageBody__c)) continue;

                providerMessages.add(new Map<String, Object>{
                    AIAssistApplicationConstants.CANONICAL_ROLE_KEY => historyMessage.Sender__c == AIAssistApplicationConstants.SENDER_USER ? AIAssistApplicationConstants.CANONICAL_ROLE_USER : AIAssistApplicationConstants.CANONICAL_ROLE_ASSISTANT,
                    AIAssistApplicationConstants.CANONICAL_CONTENT_KEY => historyMessage.MessageBody__c
                });
            }

            // [7] Offer the model the other prompt templates as one tool, so it can switch when the request fits one. Only templates with a name and a description can be told apart
            Map<String, AIPromptTemplate__c> routingTemplateByDeveloperName = new Map<String, AIPromptTemplate__c>();
            List<AIPromptTemplate__c> offeredRoutingTemplates = new List<AIPromptTemplate__c>();
            List<String> offeredRoutingNames = new List<String>();

            for (AIPromptTemplate__c routingTemplate : routingPromptTemplates == null ? new List<AIPromptTemplate__c>() : routingPromptTemplates) {

                if (String.isBlank(routingTemplate.DeveloperName__c) || String.isBlank(routingTemplate.Description__c) || routingTemplateByDeveloperName.containsKey(routingTemplate.DeveloperName__c)) continue;

                routingTemplateByDeveloperName.put(routingTemplate.DeveloperName__c, routingTemplate);
                offeredRoutingTemplates.add(routingTemplate);
                offeredRoutingNames.add(routingTemplate.DeveloperName__c);
            }

            if (!routingTemplateByDeveloperName.isEmpty()) {

                AIProvider.ToolDefinition routingToolDefinition = new AIProvider.ToolDefinition();
                routingToolDefinition.name = AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_NAME;
                routingToolDefinition.description = AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_DESCRIPTION;
                routingToolDefinition.inputSchema = new Map<String, Object>{
                    'type' => 'object',
                    'properties' => new Map<String, Object>{AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_ARGUMENT => new Map<String, Object>{'type' => 'string', 'enum' => offeredRoutingNames}},
                    'required' => new List<String>{AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_ARGUMENT}
                };

                toolDefinitions.add(routingToolDefinition);
            }

            // [8] Build the system prompt from the agent persona, the prompt template, the templates the model may switch to and the workflow actions
            Long assemblyStartedAt = System.currentTimeMillis();
            String systemPromptText = buildSystemPromptText(agent, promptTemplate, offeredRoutingTemplates, availableWorkflowActions);
            trace.addStep(AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY, true, System.currentTimeMillis() - assemblyStartedAt, getPromptAssemblyDetail('Built', agent, promptTemplate, offeredRoutingTemplates, availableWorkflowActions));

            // [9] Work out the run limits. The iteration limit is the agent's own, else the org default, kept between 1 and the cap (0 would skip the callout and no limit risks the 100 callout limit).
            AIAssistSettings__c settings = AIAssistSettingsService.getSettings();
            Integer maxToolCallingIterations = Math.max(1, Math.min(agent.MaxToolCallingIterations__c == null ? settings.DefaultMaxToolCallingIterations__c.intValue() : agent.MaxToolCallingIterations__c.intValue(), settings.MaxToolCallingIterationsCap__c.intValue()));
            Integer maxAttempts = 1 + settings.RetryAttempts__c.intValue();
            Integer maxToolCallsPerIteration = settings.MaxToolCallsPerIteration__c.intValue();
            Integer maxOutputTokens = modelConfiguration.MaximumOutputTokens__c == null ? DEFAULT_MAX_OUTPUT_TOKENS : modelConfiguration.MaximumOutputTokens__c.intValue();
            Integer configuredTimeoutMilliseconds = settings.CalloutTimeoutMilliseconds__c.intValue();
            String endpoint = 'callout:' + modelConfiguration.NamedCredential__c + modelConfiguration.ApiPath__c;

            // Only the Anthropic Agent API keeps the conversation at the provider, so only it continues the session saved on the conversation. A retry starts a new session, because the failed attempt may already have sent the message to the old one.
            if (modelConfiguration.AIProvider__c.equalsIgnoreCase(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT) && conversation != null && (attemptNumber == null || attemptNumber <= 1)) providerSession.resumeId = conversation.ExternalReference__c;

            trace.toolCallingIterationsMax = maxToolCallingIterations;
            trace.attemptNumber = attemptNumber;

            // [10] Set up what is carried between passes: the tool calls just finished (handed to the response handler at the top of the next pass), and what was sent and masked since the last provider call (the evidence for the next provider call step)
            List<AIProvider.ToolCall> previousToolCalls = null;
            List<Object> previousToolResults = null;

            Integer recordsSent = 0;
            Set<String> objectsSent = new Set<String>();
            Set<String> fieldsSent = new Set<String>();
            List<AIPiiPseudonymizationService.MaskingTally> pendingMasking = new List<AIPiiPseudonymizationService.MaskingTally>();

            // [11] Set up the callout error details. They are filled in when a callout cannot complete; the loop then stops and one failed or retryable result is returned after it.
            String calloutErrorMessage = null;
            String calloutFailureReason = AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
            Boolean isCalloutErrorRetryable = true;

            // [12] Send requests until the model gives a final reply or a limit is hit
            for (Integer iteration = 0; iteration < maxToolCallingIterations; iteration++) {

                Boolean isLastIteration = iteration == maxToolCallingIterations - 1;

                // [13] Add the previous pass's tool calls and results to the conversation before building this request
                if (previousToolCalls != null) {

                    providerResponseHandler.handleResponse(providerMessages, null, previousToolCalls, previousToolResults, null);

                    previousToolCalls = null;
                    previousToolResults = null;
                }

                // [14] Record what was masked as its own step, and never send a request if masking failed for any value in it
                pendingMasking.addAll(AIPiiPseudonymizationService.takeTallies());

                if (!pendingMasking.isEmpty()) {

                    AIPiiPseudonymizationService.MaskingTally failedTally = null;

                    for (AIPiiPseudonymizationService.MaskingTally tally : pendingMasking) {

                        if (tally.outcome == AIAssistApplicationConstants.MASKING_OUTCOME_FAILED && failedTally == null) failedTally = tally;
                    }

                    AIExecutionStepTracker.StepEntry maskingStep = trace.addStep(AIAssistApplicationConstants.STEP_TYPE_PII_MASKING, failedTally == null, null, getMaskingDetail(pendingMasking, iteration == 0, failedTally));
                    trace.addMaskingTallies(maskingStep, pendingMasking);

                    pendingMasking = new List<AIPiiPseudonymizationService.MaskingTally>();

                    if (failedTally != null) {

                        AgentResult maskingFailure = new AgentResult();
                        maskingFailure.errorMessage = 'Masking failed for ' + failedTally.sourceObject + '.' + failedTally.sourceField + '; the request was not sent.';
                        maskingFailure.failureReason = AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED;
                        maskingFailure.totalTokensUsed = totalTokensUsed;
                        maskingFailure.inputTokens = inputTokensUsed;
                        maskingFailure.outputTokens = outputTokensUsed;
                        maskingFailure.externalReference = providerSession.id;

                        return maskingFailure;
                    }
                }

                // [15] Build the request in the provider's own format. On the last pass tool calls are switched off, so the model must answer with what it has.
                AIProvider.Request canonicalRequest = new AIProvider.Request();
                canonicalRequest.modelIdentifier = modelConfiguration.ModelIdentifier__c;
                canonicalRequest.maxOutputTokens = maxOutputTokens;
                canonicalRequest.temperature = modelConfiguration.Temperature__c;
                canonicalRequest.systemPromptText = systemPromptText;
                canonicalRequest.messages = providerMessages;
                canonicalRequest.tools = toolDefinitions;
                canonicalRequest.allowToolCalls = !isLastIteration;
                canonicalRequest.endpoint = endpoint;
                canonicalRequest.environmentId = modelConfiguration.EnvironmentId__c;
                canonicalRequest.maxWaitMilliseconds = configuredTimeoutMilliseconds;
                canonicalRequest.session = providerSession;

                String requestBody = JSON.serialize(providerRequestBuilder.buildRequestBody(canonicalRequest));

                // [16] Keep the request and a preview of the last user message on the trace, only when debug mode is on, because they are customer data (already masked)
                if (trace.captureFullDetail) {

                    trace.lastRequestJson = requestBody;

                    for (Integer messageIndex = providerMessages.size() - 1; messageIndex >= 0; messageIndex--) {

                        Map<String, Object> message = providerMessages[messageIndex];

                        if (String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_ROLE_KEY)) == AIAssistApplicationConstants.CANONICAL_ROLE_USER) {

                            trace.sentPreviewText = String.isBlank(String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY))) ? null : String.valueOf(message.get(AIAssistApplicationConstants.CANONICAL_CONTENT_KEY)).abbreviate(200);

                            break;
                        }
                    }
                }

                // [17] Build the HTTP request for the Named Credential endpoint
                HttpRequest httpRequest = new HttpRequest();
                httpRequest.setEndpoint(providerSession.endpoint == null ? endpoint : providerSession.endpoint);
                httpRequest.setMethod(AIAssistApplicationConstants.HTTP_METHOD_POST);
                httpRequest.setHeader(AIAssistApplicationConstants.HTTP_HEADER_CONTENT_TYPE, AIAssistApplicationConstants.CONTENT_TYPE_JSON);

                if (String.isNotBlank(modelConfiguration.ApiVersionHeaderName__c)) httpRequest.setHeader(modelConfiguration.ApiVersionHeaderName__c, modelConfiguration.ApiVersionHeaderValue__c);

                for (String headerName : providerSession.headers.keySet()) {

                    httpRequest.setHeader(headerName, providerSession.headers.get(headerName));
                }

                httpRequest.setTimeout(configuredTimeoutMilliseconds);
                httpRequest.setBody(requestBody);

                // [18] Call the provider. If the callout fails, work out the error, whether it can be retried, and stop the loop.
                HttpResponse httpResponse;
                trace.startStep(Label.AI_Step_Calling_Model, null);

                try {

                    httpResponse = new Http().send(httpRequest);

                } catch (Exception ex) {

                    AIExecutionStepTracker.StepEntry failedStep = trace.endStep(false);

                    if (failedStep != null) {

                        failedStep.provider = modelConfiguration.AIProvider__c;
                        failedStep.modelIdentifier = modelConfiguration.ModelIdentifier__c;
                        failedStep.stepDetail = 'The call to the provider failed before a reply came back.';
                    }

                    // [19] Log it here, because it becomes a result rather than being thrown again
                    AIPlatformLogManager.logException(ex, 'AIAgentManager', 'executeAiMessage');

                    // [20] Tell a setup problem (an endpoint the org does not allow, or a missing Named Credential) from a temporary one. A setup problem fails the same way every time, so it is not retried.
                    String calloutDetail = ex.getMessage() == null ? '' : ex.getMessage();
                    Boolean isSetupProblem = calloutDetail.containsIgnoreCase('unauthorized endpoint') || calloutDetail.containsIgnoreCase('named credential');

                    calloutErrorMessage = isSetupProblem ? 'The AI provider could not be called: ' + calloutDetail + ' Check Named Credential "' + modelConfiguration.NamedCredential__c + '" on AI Model Configuration ' + modelConfiguration.Id + '.' : 'AI provider callout failed: ' + calloutDetail;
                    calloutFailureReason = isSetupProblem ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR : (calloutDetail.containsIgnoreCase('timed out') ? AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT : AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR);
                    isCalloutErrorRetryable = !isSetupProblem;

                    break;
                }

                // [21] Record the provider call step: what was sent (names and counts, never values), under which model, and what was masked
                AIExecutionStepTracker.StepEntry providerStep = trace.endStep(true);
                providerStep.provider = modelConfiguration.AIProvider__c;
                providerStep.modelIdentifier = modelConfiguration.ModelIdentifier__c;
                providerStep.recordsSentCount = recordsSent;
                providerStep.fieldsSentCount = fieldsSent.size();
                providerStep.objectsSent = String.join(new List<String>(objectsSent), ', ');
                providerStep.fieldsSent = String.join(new List<String>(fieldsSent), ', ');

                recordsSent = 0;
                objectsSent.clear();
                fieldsSent.clear();

                trace.toolCallingIterationsUsed = iteration + 1;

                if (trace.captureFullDetail) trace.lastResponseJson = httpResponse.getBody();

                // [22] If the status is not a success, end this attempt with a reason the user can be told and a message saying which record to fix. It is only retried when the status is listed in AIAssistSettings__c.RetryableStatusCodes__c and could work next time; a rejected credential, a retired model, an exhausted quota and a bad request never are.
                Integer statusCode = httpResponse.getStatusCode();

                if (!buildIntegerSet(settings.AIProviderSuccessStatusCodes__c).contains(statusCode)) {

                    providerStep.isSuccess = false;
                    calloutFailureReason = AIProvider.getFailureReason(statusCode, httpResponse.getBody());
                    providerStep.stepDetail = 'The provider returned HTTP status ' + statusCode + ' (' + calloutFailureReason + ').';

                    Boolean isCredentialRejected = calloutFailureReason == AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED;
                    Boolean isModelRetired = calloutFailureReason == AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED;

                    isCalloutErrorRetryable = buildIntegerSet(settings.RetryableStatusCodes__c).contains(statusCode) && !AIAssistApplicationConstants.NEVER_RETRIED_STATUS_CODES.contains(statusCode) && !isCredentialRejected && !isModelRetired;
                    calloutErrorMessage = 'AI provider returned ' + (isCalloutErrorRetryable ? 'a retryable ' : '') + 'HTTP status ' + statusCode + ' (' + calloutFailureReason + '). ' + (isCredentialRejected ? 'The credential or the account was rejected: check the API key and billing behind Named Credential "' + modelConfiguration.NamedCredential__c + '" on AI Model Configuration ' + modelConfiguration.Id + '. ' : (isModelRetired ? 'Model "' + modelConfiguration.ModelIdentifier__c + '" is not available: update Model Identifier on AI Model Configuration ' + modelConfiguration.Id + '. ' : '')) + 'Provider said: ' + (String.isBlank(httpResponse.getBody()) ? '(nothing)' : httpResponse.getBody().abbreviate(1000));

                    break;
                }

                // [23] Read the reply and add up the tokens used. A badly formed body throws, which is caught and logged below as a hard failure.
                AIProvider.Response modelResponse = providerResponseHandler.handleResponse(providerMessages, httpResponse, null, null, canonicalRequest);
                totalTokensUsed += modelResponse.totalTokens;
                inputTokensUsed += modelResponse.inputTokens;
                outputTokensUsed += modelResponse.outputTokens;

                // [24] If the model asked for no tools, this is its final reply
                if (modelResponse.toolCalls.isEmpty()) {

                    AgentResult successResult = new AgentResult();
                    successResult.totalTokensUsed = totalTokensUsed;
                    successResult.inputTokens = inputTokensUsed;
                    successResult.outputTokens = outputTokensUsed;
                    successResult.latencyMilliseconds = System.currentTimeMillis() - turnStartMilliseconds;
                    successResult.replyText = modelResponse.textContent;
                    successResult.selectedPromptTemplateId = selectedPromptTemplate == null ? null : selectedPromptTemplate.Id;
                    successResult.selectedPromptTemplateVersion = selectedPromptTemplate == null ? null : selectedPromptTemplate.Version__c;
                    successResult.externalReference = providerSession.id;

                    providerStep.stepDetail = 'Final reply.';

                    // [25] An empty reply counts as a failure
                    if (String.isBlank(modelResponse.textContent)) {

                        providerStep.isSuccess = false;
                        providerStep.stepDetail = 'The provider returned an empty reply.';

                        successResult.errorMessage = 'The provider returned an empty reply.';
                        successResult.failureReason = AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;

                        return successResult;
                    }

                    successResult.isSuccessful = true;

                    // [26] Look for a trailing {"suggested_workflow_action": "<DeveloperName>"} line. Only an action that was offered is accepted. The line is removed from the visible reply unless it was the whole reply (a blank reply would be rejected by the next request). Anything wrong leaves the reply as it is.
                    Integer suggestionStart = modelResponse.textContent.lastIndexOf('{');

                    if (suggestionStart >= 0 && modelResponse.textContent.substring(suggestionStart).contains(AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY) && availableWorkflowActions != null) {

                        try {

                            Map<String, Object> suggestion = (Map<String, Object>) JSON.deserializeUntyped(modelResponse.textContent.substring(suggestionStart));
                            String suggestedDeveloperName = (String) suggestion.get(AIAssistApplicationConstants.SUGGESTED_WORKFLOW_ACTION_JSON_KEY);

                            for (AIWorkflowAction__c workflowAction : availableWorkflowActions) {

                                if (workflowAction.DeveloperName__c == suggestedDeveloperName) {

                                    successResult.suggestedWorkflowActionId = workflowAction.Id;

                                    String replyWithoutSuggestion = modelResponse.textContent.substring(0, suggestionStart).trim();
                                    successResult.replyText = String.isNotBlank(replyWithoutSuggestion) ? replyWithoutSuggestion : Label.AI_Chat_Suggested_Actions_Heading;

                                    break;
                                }
                            }

                        } catch (Exception ex) {

                            AIPlatformLogManager.logException(ex, 'AIAgentManager', 'executeAiMessage');
                        }
                    }

                    // [27] Return the final reply
                    return successResult;
                }

                // Say what the model asked for, by name
                List<String> requestedNames = new List<String>();

                for (AIProvider.ToolCall requestedCall : modelResponse.toolCalls) {

                    if (requestedCall.name == AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_NAME) requestedNames.add('a prompt template switch');
                    else if (dataSourceByToolName.containsKey(requestedCall.name)) requestedNames.add('the data source ' + AIChatDataStructure.humanise(requestedCall.name));
                    else requestedNames.add('an unknown tool');
                }

                providerStep.stepDetail = 'The model asked for ' + String.join(requestedNames, ', ') + '.';

                // [28] Stop if this was the last pass. Tool calls were switched off, so this only happens if the provider ignored that, and their results could never be sent back.
                if (isLastIteration) break;

                // [29] Run the tools the model asked for. Every call gets a result because providers reject a reply that leaves one unanswered; a skipped call gets an explanation instead.
                List<Object> toolResults = new List<Object>();

                for (Integer toolIndex = 0; toolIndex < modelResponse.toolCalls.size(); toolIndex++) {

                    AIProvider.ToolCall toolCall = modelResponse.toolCalls[toolIndex];

                    if (toolIndex >= maxToolCallsPerIteration) {

                        toolResults.add(AIAssistApplicationConstants.TOOL_RESULT_SKIPPED_TOO_MANY_CALLS);

                        continue;
                    }

                    // [30] Switch to the prompt template the model chose, and rebuild the system prompt without the list of choices so the next pass answers with the chosen template alone. A name that is not on the list changes nothing
                    if (toolCall.name == AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_NAME && !routingTemplateByDeveloperName.isEmpty()) {

                        AIPromptTemplate__c chosenTemplate = toolCall.arguments == null ? null : routingTemplateByDeveloperName.get(String.valueOf(toolCall.arguments.get(AIAssistApplicationConstants.PROMPT_TEMPLATE_TOOL_ARGUMENT)));

                        if (chosenTemplate == null) {

                            AIExecutionStepTracker.StepEntry unknownTemplateStep = trace.addStep(AIAssistApplicationConstants.STEP_TYPE_TEMPLATE_MATCH, true, 0L, 'The model asked for a template that is not offered, so nothing changed.');
                            unknownTemplateStep.status = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED;
                            toolResults.add(AIAssistApplicationConstants.TOOL_RESULT_PROMPT_TEMPLATE_UNKNOWN);

                            continue;
                        }

                        trace.addStep(AIAssistApplicationConstants.STEP_TYPE_TEMPLATE_MATCH, true, 0L, 'Switched from ' + getTemplateName(promptTemplate) + ' to ' + getTemplateName(chosenTemplate) + '.');

                        promptTemplate = chosenTemplate;
                        selectedPromptTemplate = chosenTemplate;

                        Long rebuildStartedAt = System.currentTimeMillis();
                        systemPromptText = buildSystemPromptText(agent, promptTemplate, new List<AIPromptTemplate__c>(), availableWorkflowActions);
                        trace.addStep(AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY, true, System.currentTimeMillis() - rebuildStartedAt, getPromptAssemblyDetail('Rebuilt', agent, promptTemplate, new List<AIPromptTemplate__c>(), availableWorkflowActions));
                        toolResults.add(AIAssistApplicationConstants.TOOL_RESULT_PROMPT_TEMPLATE_SELECTED);

                        continue;
                    }

                    AIDataSource__c dataSource = dataSourceByToolName.get(toolCall.name);
                    trace.startStep(Label.AI_Step_Reading_Data, dataSource == null ? null : dataSource.Id);

                    Object toolResult;
                    Boolean toolSucceeded = true;
                    Integer recordsReturned = 0;

                    // [31] Run the data source. A failing tool does not end the turn: it is logged and the model is only told it failed, so it can react without seeing the real error.
                    try {

                        if (dataSource == null) throw new AIAgentManagerException('The model requested an unknown tool "' + toolCall.name + '".');

                        List<Object> toolRecords = AIDataSourceDispatcher.runDataSource(dataSource.Id, agent.Id, String.isBlank(conversation.RelatedRecordId__c) ? null : (Id) conversation.RelatedRecordId__c, toolCall.arguments, conversation.Id);

                        // [32] Say so plainly when nothing was found, so the model stops retrying. Otherwise keep the records and note which objects and fields were sent.
                        if (toolRecords == null || toolRecords.isEmpty()) {

                            toolResult = AIAssistApplicationConstants.TOOL_RESULT_NO_RECORDS_FOUND;

                        } else {

                            toolResult = toolRecords;
                            recordsSent += toolRecords.size();
                            recordsReturned = toolRecords.size();

                            if (String.isNotBlank(dataSource.TargetObject__c)) objectsSent.add(dataSource.TargetObject__c);

                            for (Object toolRecord : toolRecords) {

                                if (toolRecord instanceof Map<String, Object>) {

                                    for (String fieldName : ((Map<String, Object>) toolRecord).keySet()) {

                                        fieldsSent.add((String.isBlank(dataSource.TargetObject__c) ? '' : dataSource.TargetObject__c + '.') + fieldName);
                                    }
                                }
                            }
                        }

                    } catch (Exception ex) {

                        AIPlatformLogManager.logException(ex, 'AIAgentManager', 'executeAiMessage');

                        toolResult = AIAssistApplicationConstants.TOOL_RESULT_FAILED;
                        toolSucceeded = false;
                    }

                    // [33] Close the tool step. A tool the model made up still counts as a data source step, not a provider call.
                    AIExecutionStepTracker.StepEntry toolStep = trace.endStep(toolSucceeded);

                    if (toolStep != null) {

                        toolStep.stepType = AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE;
                        toolStep.targetObject = dataSource == null ? null : dataSource.TargetObject__c;
                        toolStep.dataSourceName = dataSource == null ? null : dataSource.DeveloperName__c;

                        if (dataSource == null) toolStep.stepDetail = 'The model asked for a data source that does not exist.';
                        else if (!toolSucceeded) toolStep.stepDetail = AIChatDataStructure.humanise(dataSource.DeveloperName__c) + ' failed. The model carried on without it.';
                        else toolStep.stepDetail = 'Ran ' + AIChatDataStructure.humanise(dataSource.DeveloperName__c) + (String.isBlank(dataSource.TargetObject__c) ? '' : ' on ' + dataSource.TargetObject__c) + '. ' + recordsReturned + (recordsReturned == 1 ? ' record' : ' records') + ' returned.';
                    }

                    toolResults.add(toolResult);
                }

                // [34] Keep the tool calls and results to add to the conversation on the next pass
                previousToolCalls = modelResponse.toolCalls;
                previousToolResults = toolResults;
            }

            // [35] If a callout could not complete, return a failure that is retryable while attempts remain. It carries the tokens already spent so a retry adds to them.
            if (calloutErrorMessage != null) {

                AgentResult calloutFailure = new AgentResult();
                calloutFailure.errorMessage = calloutErrorMessage;
                calloutFailure.failureReason = calloutFailureReason;
                calloutFailure.totalTokensUsed = totalTokensUsed;
                calloutFailure.inputTokens = inputTokensUsed;
                calloutFailure.outputTokens = outputTokensUsed;
                calloutFailure.isRetryable = isCalloutErrorRetryable && attemptNumber < maxAttempts;
                calloutFailure.externalReference = providerSession.id;

                return calloutFailure;
            }

            // [36] The loop ended without a final reply, so return a limit failure
            AgentResult limitFailure = new AgentResult();
            limitFailure.errorMessage = 'Reached the maximum of ' + maxToolCallingIterations + ' tool-calling iterations without a final response.';
            limitFailure.failureReason = AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED;
            limitFailure.totalTokensUsed = totalTokensUsed;
            limitFailure.inputTokens = inputTokensUsed;
            limitFailure.outputTokens = outputTokensUsed;
            limitFailure.externalReference = providerSession.id;

            return limitFailure;

        } catch (Exception ex) {

            // [37] Anything unexpected is logged and returned as a failed result. Tokens already spent are still billed, so they are included.
            AIPlatformLogManager.logException(ex, 'AIAgentManager', 'executeAiMessage');

            AgentResult failure = new AgentResult();
            failure.errorMessage = 'Failed to get a response from the AI provider: ' + ex.getMessage();
            failure.totalTokensUsed = totalTokensUsed;
            failure.inputTokens = inputTokensUsed;
            failure.outputTokens = outputTokensUsed;
            failure.externalReference = providerSession.id;
            failure.failureReason = ex instanceof AIAgentManagerException || ex instanceof AIAssistSettingsService.AIAssistSettingsServiceException ? AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR : (ex.getTypeName().contains('ResponseHandlerException') || ex instanceof AIProvider.AIProviderException ? AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR : AIAssistApplicationConstants.FAILURE_REASON_OTHER);

            return failure;

        } finally {

            // [38] Stop holding back PII mapping saves. The mappings stay cached in memory; the caller must still save them.
            AIPiiMappingService.isDeferringWrites = false;
        }
    }

    // The name to show for a prompt template: its name, else its developer name tidied.
    private static String getTemplateName(AIPromptTemplate__c template) {

        // [1] Use the name, else the developer name tidied
        if (template == null) return 'no template';
        return String.isNotBlank(template.Name) ? template.Name : AIChatDataStructure.humanise(template.DeveloperName__c);
    }

    // The plain wording for a prompt assembly step: the agent, the template, the templates the model may switch to and the workflow actions offered. Names only.
    private static String getPromptAssemblyDetail(String verb, AIAgent__c agent, AIPromptTemplate__c promptTemplate, List<AIPromptTemplate__c> offeredRoutingTemplates, List<AIWorkflowAction__c> availableWorkflowActions) {

        // [1] Name the agent and the template
        String detail = verb + ' the prompt for agent ' + (agent == null || String.isBlank(agent.Name) ? 'unknown' : agent.Name) + ' using prompt template ' + getTemplateName(promptTemplate) + '.';

        // [2] Name the templates the model may switch to
        List<String> routingNames = new List<String>();

        for (AIPromptTemplate__c routingTemplate : offeredRoutingTemplates) routingNames.add(getTemplateName(routingTemplate));

        detail += routingNames.isEmpty() ? ' No other templates offered.' : ' Other templates offered: ' + String.join(routingNames, ', ') + '.';

        // [3] Name the workflow actions the model may suggest
        List<String> actionNames = new List<String>();

        for (AIWorkflowAction__c offeredAction : availableWorkflowActions == null ? new List<AIWorkflowAction__c>() : availableWorkflowActions) actionNames.add(AIChatDataStructure.humanise(offeredAction.DeveloperName__c));

        detail += actionNames.isEmpty() ? ' No workflow actions offered.' : ' Workflow actions offered: ' + String.join(actionNames, ', ') + '.';

        return detail;
    }

    // The plain wording for a masking step: how many values were masked, and which fields, naming the type and count of each. Never the values.
    private static String getMaskingDetail(List<AIPiiPseudonymizationService.MaskingTally> tallies, Boolean isRequest, AIPiiPseudonymizationService.MaskingTally failedTally) {

        // [1] A failure names the field and says nothing was sent
        if (failedTally != null) return 'Masking failed for ' + failedTally.sourceObject + '.' + failedTally.sourceField + '. The request was not sent.';

        // [2] Add up the values and describe each field
        Decimal valuesMasked = 0;
        List<String> fieldDescriptions = new List<String>();

        for (AIPiiPseudonymizationService.MaskingTally tally : tallies) {

            valuesMasked += tally.valuesMasked == null ? 0 : tally.valuesMasked;
            fieldDescriptions.add(tally.sourceObject + '.' + tally.sourceField + ' (' + tally.piiFieldType + ', ' + (tally.valuesMasked == null ? 0 : tally.valuesMasked.intValue()) + (tally.outcome == AIAssistApplicationConstants.MASKING_OUTCOME_MASKED ? '' : ', ' + tally.outcome.toLowerCase()) + ')');
        }

        // [3] Say it
        return 'Masked ' + valuesMasked.intValue() + (valuesMasked == 1 ? ' value' : ' values') + (isRequest ? ' in the request: ' : ' in the data returned: ') + String.join(fieldDescriptions, ', ') + '.';
    }

    // Builds the system prompt: the agent's persona, the prompt template, the templates the model may switch to, the language and the workflow actions it may suggest. Returns null when there is nothing to say.
    private static String buildSystemPromptText(AIAgent__c agent, AIPromptTemplate__c promptTemplate, List<AIPromptTemplate__c> routingTemplates, List<AIWorkflowAction__c> availableWorkflowActions) {

        // [1] Start with the agent persona
        List<String> systemPromptParts = new List<String>();

        if (String.isNotBlank(agent.AIAgentPersona__c)) systemPromptParts.add('Persona: ' + agent.AIAgentPersona__c);

        // [2] Add the prompt template's wording
        if (promptTemplate != null) {

            if (String.isNotBlank(promptTemplate.AISystemContext__c)) systemPromptParts.add(promptTemplate.AISystemContext__c);
            if (String.isNotBlank(promptTemplate.AIPrompt__c)) systemPromptParts.add(promptTemplate.AIPrompt__c);
            if (String.isNotBlank(promptTemplate.AITone__c)) systemPromptParts.add('Tone: ' + promptTemplate.AITone__c);
            if (String.isNotBlank(promptTemplate.AIExclusionRules__c)) systemPromptParts.add('Do not: ' + promptTemplate.AIExclusionRules__c);
        }

        // [3] List the other templates the model may switch to, with what each is for
        if (routingTemplates != null && !routingTemplates.isEmpty()) {

            systemPromptParts.add(AIAssistApplicationConstants.PROMPT_TEMPLATE_PROMPT_INSTRUCTION);

            for (AIPromptTemplate__c routingTemplate : routingTemplates) {

                systemPromptParts.add(routingTemplate.DeveloperName__c + ': ' + routingTemplate.Description__c);
            }
        }

        // [4] Tell the model to reply in the user's language. Labels are translated by the platform but agent text is not. A turn runs as the user who sent the message, so this is their language.
        systemPromptParts.add(String.format(AIAssistApplicationConstants.LANGUAGE_PROMPT_INSTRUCTION, new List<String>{UserInfo.getLanguage()}));

        // [5] List the workflow actions the model may suggest (never run) and how to name one
        if (availableWorkflowActions != null && !availableWorkflowActions.isEmpty()) {

            systemPromptParts.add(AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_INSTRUCTION);

            for (AIWorkflowAction__c workflowAction : availableWorkflowActions) {

                systemPromptParts.add(workflowAction.DeveloperName__c + ': ' + (String.isNotBlank(workflowAction.Description__c) ? workflowAction.Description__c : workflowAction.OutputDescription__c));
            }

            systemPromptParts.add(AIAssistApplicationConstants.WORKFLOW_ACTION_PROMPT_JSON_INSTRUCTION);
        }

        // [6] Join the prompt and remove blank lines and repeated spaces to save tokens on every pass. Single line breaks stay so authored lists remain readable.
        return systemPromptParts.isEmpty() ? null : String.join(systemPromptParts, '\n').replaceAll('[ \\t]*\\n\\s*', '\n').replaceAll('[ \\t]+', ' ').trim();
    }

    // Turns a setting like "200,201" into a set of numbers. Anything that is not a number is skipped.
    private static Set<Integer> buildIntegerSet(String commaSeparatedNumbers) {

        // [1] Start with an empty set
        Set<Integer> numbers = new Set<Integer>();

        // [2] Nothing to read, so return the empty set
        if (String.isBlank(commaSeparatedNumbers)) return numbers;

        // [3] Add each entry that is a number
        for (String entry : commaSeparatedNumbers.split(',')) {

            if (entry.trim().isNumeric()) numbers.add(Integer.valueOf(entry.trim()));
        }

        // [4] Return the numbers
        return numbers;
    }
}
