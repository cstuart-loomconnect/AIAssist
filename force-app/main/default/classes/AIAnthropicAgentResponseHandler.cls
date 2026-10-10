/*
Class Name: AIAnthropicAgentResponseHandler

=================================================================
=================================================================

Description: Waits for an Anthropic Agent API session to finish what it was sent, then reads what it did and adds it to the conversation.

Step 1: If tools were run last time, add their results to the conversation
Step 2: Stop if there is no response to read
Step 3: Throw an error if sending the events failed
Step 4: Fetch the session's events until it goes idle or ended, or the time or callout allowance runs out
Step 5: Read the agent's text and custom tool calls from the events, and add up the token usage
Step 6: Throw an error if the session errored, ended, or is waiting on something this package cannot give
Step 7: Add the reply to the conversation and return the answer

Apex cannot hold a stream open or sleep between calls, so the event list is fetched again straight away. The session, its endpoint and the time allowed come from the request the events were built from.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAnthropicAgentResponseHandler implements IAIProviderResponseHandler {

    public class AIAnthropicAgentResponseHandlerException extends Exception {}

    private static final String METHOD_GET = 'GET';
    private static final Integer CALLOUTS_KEPT_IN_RESERVE = 5; // Each fetch is a callout and a transaction may make 100, so the last few are kept for the interrupt and for the tool-calling passes that follow.

    // Reads the events of one request and adds them to the conversation. If tools were run last time, it first adds their results to the conversation.
    public AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse agentHttpResponse, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults, AIProvider.Request request) {

        try {

            // [1] If tools were run last time, add their results as one user message, each tagged with the id of the call it answers
            if (previousToolCalls != null) {

                if (previousToolResults == null || previousToolResults.size() != previousToolCalls.size()) throw new AIAnthropicAgentResponseHandlerException('Tool result count does not match tool call count - every custom tool call needs exactly one result.');

                List<Object> toolResultBlocks = new List<Object>();

                for (Integer toolIndex = 0; toolIndex < previousToolCalls.size(); toolIndex++) {

                    toolResultBlocks.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE => AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_RESULT,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_RESULT_ID => previousToolCalls[toolIndex].id,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => AIProvider.stringifyToolResult(previousToolResults[toolIndex])
                    });
                }

                providerMessages.add(new Map<String, Object>{
                    AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_USER,
                    AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => toolResultBlocks
                });
            }

            // [2] If there is no reply to read, stop here
            if (agentHttpResponse == null) return null;

            // [3] If the call failed, throw an error with the provider's message (or the raw reply if it has none)
            if (agentHttpResponse.getStatusCode() < 200 || agentHttpResponse.getStatusCode() > 299) throw new AIAnthropicAgentResponseHandlerException('AI provider returned HTTP ' + agentHttpResponse.getStatusCode() + ': ' + getErrorDetail(agentHttpResponse.getBody()));

            // [4] Fetch the session's events until the agent has finished what it was sent
            List<Object> events = getSettledEvents(request);

            AIProvider.Response agentResponse = new AIProvider.Response();
            List<String> responseTextLines = new List<String>();
            List<Object> assistantBlocks = new List<Object>();
            String stopReasonType;

            // [5] Go through the events: agent text goes into the answer, custom tool calls go into the list of tool calls, usage is added up, and anything else is skipped
            for (Object eventObject : events) {

                Map<String, Object> agentEvent = (Map<String, Object>) eventObject;
                String eventType = (String) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE);

                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_AGENT_MESSAGE) {

                    List<Object> messageBlocks = (List<Object>) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_CONTENT);

                    for (Object blockObject : messageBlocks == null ? new List<Object>() : messageBlocks) {

                        Map<String, Object> block = (Map<String, Object>) blockObject;

                        if (block.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE) != AIAssistApplicationConstants.ANTHROPIC_AGENT_CONTENT_TYPE_TEXT) continue;

                        responseTextLines.add((String) block.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TEXT));
                        assistantBlocks.add(new Map<String, Object>{
                            AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE => AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TEXT,
                            AIAssistApplicationConstants.ANTHROPIC_FIELD_TEXT => block.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TEXT)
                        });
                    }
                }

                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_AGENT_TOOL_USE) {

                    Map<String, Object> toolArguments = (Map<String, Object>) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TOOL_INPUT);

                    AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
                    toolCall.id = (String) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ID);
                    toolCall.name = (String) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TOOL_NAME);
                    toolCall.arguments = toolArguments != null ? toolArguments : new Map<String, Object>();

                    agentResponse.toolCalls.add(toolCall);
                    assistantBlocks.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE => AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_USE,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_ID => toolCall.id,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_NAME => toolCall.name,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_INPUT => toolCall.arguments
                    });
                }

                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_MODEL_REQUEST_END) {

                    Map<String, Object> modelUsage = (Map<String, Object>) agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_MODEL_USAGE);

                    if (modelUsage != null) {

                        agentResponse.inputTokens += getNumber(modelUsage.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_USAGE_INPUT_TOKENS)) + getNumber(modelUsage.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_USAGE_CACHE_CREATION_TOKENS)) + getNumber(modelUsage.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_USAGE_CACHE_READ_TOKENS));
                        agentResponse.outputTokens += getNumber(modelUsage.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_USAGE_OUTPUT_TOKENS));
                    }
                }

                // [6] A session that errored or ended cannot answer, so say why
                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_SESSION_ERROR) throw new AIAnthropicAgentResponseHandlerException('The agent session reported an error: ' + getErrorDetail(JSON.serialize(agentEvent)));
                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_STATUS_TERMINATED) throw new AIAnthropicAgentResponseHandlerException('The agent session ended before it answered.');

                if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_STATUS_IDLE) {

                    Object stopReason = agentEvent.get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_STOP_REASON);
                    stopReasonType = stopReason instanceof Map<String, Object> ? (String) ((Map<String, Object>) stopReason).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE) : null;
                }
            }

            // [7] An agent waiting on something other than a custom tool (for example approval of a built-in tool) never answers on its own, so fail with a message that says what to change
            if (stopReasonType == AIAssistApplicationConstants.ANTHROPIC_AGENT_STOP_REASON_REQUIRES_ACTION && agentResponse.toolCalls.isEmpty()) throw new AIAnthropicAgentResponseHandlerException('The agent is waiting for an approval this package cannot give. Set the agent\'s tool permission policy to always_allow or auto, or remove the tool that asks.');

            agentResponse.textContent = String.join(responseTextLines, '\n');
            agentResponse.totalTokens = agentResponse.inputTokens + agentResponse.outputTokens;

            // [8] Add what the agent did to the conversation so the next request includes it
            providerMessages.add(new Map<String, Object>{
                AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_ASSISTANT,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => assistantBlocks
            });

            // [9] Hand back the answer and any tool calls
            return agentResponse;

        } catch (Exception ex) {

            // [10] Not logged here because AIAgentManager logs it, so it is only logged once. Our own errors are passed on as they are; anything else is wrapped with a clear message.
            if (ex instanceof AIAnthropicAgentResponseHandlerException) throw ex;
            throw new AIAnthropicAgentResponseHandlerException('Failed to handle the Anthropic Agent response: ' + ex.getMessage(), ex);
        }
    }

    // Fetches the session's event list until the events after the last one sent include an idle or ended status. If time or callouts run out first, the agent is told to stop and an error says so.
    private static List<Object> getSettledEvents(AIProvider.Request request) {

        // [1] Without a session there is nothing to fetch
        if (request == null || request.session == null || request.session.endpoint == null) throw new AIAnthropicAgentResponseHandlerException('There is no agent session to read the answer from.');

        Long startMilliseconds = System.currentTimeMillis();
        Integer maxWaitMilliseconds = request.maxWaitMilliseconds == null ? AIAssistApplicationConstants.ANTHROPIC_AGENT_MAX_CALLOUT_MILLISECONDS : request.maxWaitMilliseconds;

        // [2] Fetch again straight away until the agent has settled, keeping a few callouts back for the interrupt and the passes that follow
        while (System.currentTimeMillis() - startMilliseconds < maxWaitMilliseconds && Limits.getCallouts() < Limits.getLimitCallouts() - CALLOUTS_KEPT_IN_RESERVE) {

            Long remaining = maxWaitMilliseconds - (System.currentTimeMillis() - startMilliseconds);
            HttpResponse listResponse = AIAnthropicAgentRequestBuilder.sendRequest(request.session.endpoint, METHOD_GET, null, remaining.intValue());

            if (listResponse.getStatusCode() < 200 || listResponse.getStatusCode() > 299) throw new AIAnthropicAgentResponseHandlerException('AI provider returned HTTP ' + listResponse.getStatusCode() + ': ' + getErrorDetail(listResponse.getBody()));

            List<Object> newEvents = getEventsSinceLastSent(listResponse.getBody());

            if (isSettled(newEvents)) return newEvents;
        }

        // [3] Out of time or callouts: stop the agent so it does not carry on unseen, then report it
        AIAnthropicAgentRequestBuilder.sendRequest(request.session.endpoint, AIAssistApplicationConstants.HTTP_METHOD_POST, JSON.serialize(new Map<String, Object>{AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_EVENTS => new List<Object>{new Map<String, Object>{AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE => AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_USER_INTERRUPT}}}), AIAssistApplicationConstants.ANTHROPIC_AGENT_MIN_CALLOUT_MILLISECONDS);

        throw new AIAnthropicAgentResponseHandlerException('The agent did not finish within ' + maxWaitMilliseconds + ' milliseconds or the callouts allowed.');
    }

    // The events after the last one this turn sent. Events from earlier requests, and the idle that ended them, are left out. When the sent event is not listed yet nothing is returned, so the caller asks again.
    private static List<Object> getEventsSinceLastSent(String listBody) {

        // [1] Read the whole list
        List<Object> allEvents = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(listBody)).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_DATA);
        List<Object> newEvents = new List<Object>();

        if (allEvents == null) return newEvents;

        // [2] Find the last event we sent
        Integer lastSentIndex = -1;

        for (Integer eventIndex = 0; eventIndex < allEvents.size(); eventIndex++) {

            Object eventType = ((Map<String, Object>) allEvents[eventIndex]).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE);

            if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_USER_MESSAGE || eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_USER_TOOL_RESULT) lastSentIndex = eventIndex;
        }

        // [3] Everything after it belongs to this request
        for (Integer eventIndex = lastSentIndex + 1; lastSentIndex >= 0 && eventIndex < allEvents.size(); eventIndex++) {

            newEvents.add(allEvents[eventIndex]);
        }

        return newEvents;
    }

    // True once the session has gone idle or ended since the request was sent.
    private static Boolean isSettled(List<Object> newEvents) {

        // [1] Look for an idle or ended status
        for (Object eventObject : newEvents) {

            Object eventType = ((Map<String, Object>) eventObject).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE);

            if (eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_STATUS_IDLE || eventType == AIAssistApplicationConstants.ANTHROPIC_AGENT_EVENT_STATUS_TERMINATED) return true;
        }

        return false;
    }

    // The provider's own error message when the body has one, otherwise the body itself.
    private static String getErrorDetail(String rawBody) {

        // [1] Without a JSON object there is nothing to pick apart
        Boolean isJsonObject = String.isNotBlank(rawBody) && rawBody.trim().startsWith('{') && rawBody.trim().endsWith('}');

        if (!isJsonObject) return rawBody;

        // [2] Look for { error: { type, message } } at the top, or inside an error event
        Object parsedBody = JSON.deserializeUntyped(rawBody);
        Object errorDetails = parsedBody instanceof Map<String, Object> ? ((Map<String, Object>) parsedBody).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_ERROR) : null;

        if (!(errorDetails instanceof Map<String, Object>)) return rawBody;

        Object errorType = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_TYPE);
        Object errorMessage = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_AGENT_FIELD_MESSAGE);

        // [3] Return type and message, or the raw body when there is no message
        return errorMessage == null ? rawBody : (errorType == null ? '' : errorType + ' - ') + errorMessage;
    }

    // A number from parsed JSON, or 0 when it is missing.
    private static Decimal getNumber(Object value) {

        // [1] Missing counts as 0
        if (value == null) return 0;

        // [2] Parsed JSON gives an Integer, Long or Decimal, so read it through its text
        return Decimal.valueOf(String.valueOf(value));
    }
}
