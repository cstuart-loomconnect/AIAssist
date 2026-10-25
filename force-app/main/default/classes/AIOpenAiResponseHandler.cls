/*
Class Name: AIOpenAiResponseHandler

=================================================================
=================================================================

Description: Reads a response from OpenAI's Chat Completions API and keeps the conversation up to date.

Step 1: Add the results of any tools that ran last time to the conversation, one tool message per call
Step 2: Stop if there is no response, or throw an error if OpenAI says the call failed
Step 3: Read the reply text, the tool calls and the token counts
Step 4: Add OpenAI's reply to the conversation and return the answer

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIOpenAiResponseHandler implements IAIProviderResponseHandler {

    public class AIOpenAiResponseHandlerException extends Exception {}

    // Reads the reply from OpenAI and adds it to the conversation. If tools were run last time, it also adds their results to the conversation first.
    public AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse openAiHttpResponse, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults, AIProvider.Request request) {

        try {

            // [1] If tools were run last time, send their results back to OpenAI
            if (previousToolCalls != null) {

                if (previousToolResults == null || previousToolResults.size() != previousToolCalls.size()) throw new AIOpenAiResponseHandlerException('Tool result count does not match tool call count - every tool call needs exactly one tool result.');

                // [2] Add one tool message for each tool that ran, tagged with that tool's id so OpenAI knows which is which
                for (Integer toolIndex = 0; toolIndex < previousToolCalls.size(); toolIndex++) {

                    providerMessages.add(new Map<String, Object>{
                        AIAssistApplicationConstants.OPENAI_ROLE_KEY => AIAssistApplicationConstants.OPENAI_ROLE_TOOL,
                        AIAssistApplicationConstants.OPENAI_FIELD_TOOL_RESULT_ID => previousToolCalls[toolIndex].id,
                        AIAssistApplicationConstants.OPENAI_FIELD_CONTENT => AIProvider.stringifyToolResult(previousToolResults[toolIndex])
                    });
                }
            }

            // [3] If there is no reply to read, stop here
            if (openAiHttpResponse == null) return null;

            String rawResponseBody = openAiHttpResponse.getBody();

            // [4] If OpenAI says the call failed, throw an error with its message (or the raw reply if it has none)
            if (!buildIntegerSet(AIAssistSettingsService.getSettings().AIProviderSuccessStatusCodes__c).contains(openAiHttpResponse.getStatusCode())) {

                String providerErrorDetail = rawResponseBody;
                Boolean isJsonObjectBody = String.isNotBlank(rawResponseBody) && rawResponseBody.trim().startsWith('{') && rawResponseBody.trim().endsWith('}');
                Object errorResponseBody = isJsonObjectBody ? JSON.deserializeUntyped(rawResponseBody) : null;
                Object errorDetails = errorResponseBody instanceof Map<String, Object> ? ((Map<String, Object>) errorResponseBody).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR) : null;

                if (errorDetails instanceof Map<String, Object>) {

                    Object providerErrorType = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR_TYPE);
                    Object providerErrorMessage = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.OPENAI_FIELD_ERROR_MESSAGE);

                    if (providerErrorMessage != null) providerErrorDetail = (providerErrorType == null ? '' : providerErrorType + ' - ') + providerErrorMessage;
                }

                throw new AIOpenAiResponseHandlerException('AI provider returned HTTP ' + openAiHttpResponse.getStatusCode() + ': ' + providerErrorDetail);
            }

            // [5] The call worked, so find the reply (it lives in the first choice)
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(rawResponseBody);
            List<Object> responseChoices = (List<Object>) responseBody.get(AIAssistApplicationConstants.OPENAI_FIELD_CHOICES);

            if (responseChoices == null || responseChoices.isEmpty()) throw new AIOpenAiResponseHandlerException('OpenAI response contained no choices.');

            Map<String, Object> assistantMessage = (Map<String, Object>) ((Map<String, Object>) responseChoices[0]).get(AIAssistApplicationConstants.OPENAI_FIELD_MESSAGE);

            if (assistantMessage == null) throw new AIOpenAiResponseHandlerException('OpenAI response choice contained no message.');

            AIProvider.Response agentResponse = new AIProvider.Response();

            // [6] Read the reply text (it is empty when the assistant only asked to call tools)
            String messageContent = (String) assistantMessage.get(AIAssistApplicationConstants.OPENAI_FIELD_CONTENT);
            agentResponse.textContent = messageContent != null ? messageContent : '';

            List<Object> toolCallItems = (List<Object>) assistantMessage.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALLS);

            if (toolCallItems == null) toolCallItems = new List<Object>();

            // [7] Turn each tool request into a tool call - the name and arguments sit inside its function object
            for (Object toolCallItemObject : toolCallItems) {

                Map<String, Object> toolCallItem = (Map<String, Object>) toolCallItemObject;
                Map<String, Object> toolFunction = (Map<String, Object>) toolCallItem.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_FUNCTION);

                // [8] OpenAI sends the arguments as a JSON string, so read it into a map (blank means no arguments)
                String toolArgumentsJson = (String) toolFunction.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALL_ARGUMENTS);

                AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
                toolCall.id = (String) toolCallItem.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CALL_ID);
                toolCall.name = (String) toolFunction.get(AIAssistApplicationConstants.OPENAI_FIELD_TOOL_NAME);
                toolCall.arguments = String.isBlank(toolArgumentsJson) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(toolArgumentsJson);

                agentResponse.toolCalls.add(toolCall);
            }

            // [9] Work out how many tokens were used (anything missing counts as 0)
            Map<String, Object> tokenUsage = (Map<String, Object>) responseBody.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE);

            if (tokenUsage != null) {

                Integer totalTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE_TOTAL_TOKENS);
                Integer promptTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE_PROMPT_TOKENS);
                Integer completionTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.OPENAI_FIELD_USAGE_COMPLETION_TOKENS);

                agentResponse.totalTokens = totalTokens != null ? totalTokens : 0;
                agentResponse.inputTokens = promptTokens != null ? promptTokens : 0;
                agentResponse.outputTokens = completionTokens != null ? completionTokens : agentResponse.totalTokens - agentResponse.inputTokens;
            }

            // [10] Add OpenAI's reply to the conversation exactly as it came back so the next request includes it
            providerMessages.add(assistantMessage);

            // [11] Hand back the answer and any tool calls
            return agentResponse;

        } catch (Exception ex) {

            // [12] Anything that goes wrong ends up here. Not logged here because AIAgentManager logs it, so it is only logged once. Our own errors are passed on as they are; anything else is wrapped with a clear message
            if (ex instanceof AIOpenAiResponseHandlerException) throw ex;
            throw new AIOpenAiResponseHandlerException('Failed to handle the OpenAI response: ' + ex.getMessage(), ex);
        }
    }

    // Turns a setting like "200,201" into a set of numbers. Anything that is not a number is skipped.
    private static Set<Integer> buildIntegerSet(String commaSeparatedNumbers) {

        // [1] Start with an empty set
        Set<Integer> numbers = new Set<Integer>();

        if (String.isBlank(commaSeparatedNumbers)) return numbers;

        // [2] Keep each entry that is a number
        for (String entry : commaSeparatedNumbers.split(',')) {

            if (entry.trim().isNumeric()) numbers.add(Integer.valueOf(entry.trim()));
        }

        return numbers;
    }
}
