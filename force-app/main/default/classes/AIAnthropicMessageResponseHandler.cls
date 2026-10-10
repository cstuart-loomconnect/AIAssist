/*
Class Name: AIAnthropicMessageResponseHandler

=================================================================
=================================================================

Description: Reads Anthropic's Messages API response and adds it to the conversation.

Step 1: If tools were run last time, add their results to the conversation
Step 2: Stop if there is no response to read
Step 3: Throw an error if Anthropic says the call failed
Step 4: Read the text and tool calls from the reply
Step 5: Work out the token usage
Step 6: Add the reply to the conversation and return the answer

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAnthropicMessageResponseHandler implements IAIProviderResponseHandler {

    public class AIAnthropicMessageResponseHandlerException extends Exception {}

    // Reads the reply from Anthropic and adds it to the conversation. If tools were run last time, it also adds their results to the conversation first.
    public AIProvider.Response handleResponse(List<Map<String, Object>> providerMessages, HttpResponse anthropicHttpResponse, List<AIProvider.ToolCall> previousToolCalls, List<Object> previousToolResults, AIProvider.Request request) {

        try {

            // [1] If tools were run last time, send their results back to Anthropic
            if (previousToolCalls != null) {

                if (previousToolResults == null || previousToolResults.size() != previousToolCalls.size()) throw new AIAnthropicMessageResponseHandlerException('Tool result count does not match tool call count - every tool_use block needs exactly one tool_result.');

                // [2] Make one result entry for each tool that ran, tagged with that tool's id so Anthropic knows which is which
                List<Object> toolResultBlocks = new List<Object>();

                for (Integer toolIndex = 0; toolIndex < previousToolCalls.size(); toolIndex++) {

                    toolResultBlocks.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE => AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_RESULT,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_RESULT_ID => previousToolCalls[toolIndex].id,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => AIProvider.stringifyToolResult(previousToolResults[toolIndex])
                    });
                }

                // [3] Add all the results to the conversation as a single user message
                providerMessages.add(new Map<String, Object>{
                    AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_USER,
                    AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => toolResultBlocks
                });
            }

            // [4] If there is no reply to read, stop here
            if (anthropicHttpResponse == null) return null;

            String rawResponseBody = anthropicHttpResponse.getBody();

            // [5] If Anthropic says the call failed, throw an error with its message (or the raw reply if it has none)
            if (!buildIntegerSet(AIAssistSettingsService.getSettings().AIProviderSuccessStatusCodes__c).contains(anthropicHttpResponse.getStatusCode())) {

                String providerErrorDetail = rawResponseBody;
                Boolean isJsonObjectBody = String.isNotBlank(rawResponseBody) && rawResponseBody.trim().startsWith('{') && rawResponseBody.trim().endsWith('}');
                Object errorResponseBody = isJsonObjectBody ? JSON.deserializeUntyped(rawResponseBody) : null;
                Object errorDetails = errorResponseBody instanceof Map<String, Object> ? ((Map<String, Object>) errorResponseBody).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR) : null;

                if (errorDetails instanceof Map<String, Object>) {

                    Object providerErrorType = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR_TYPE);
                    Object providerErrorMessage = ((Map<String, Object>) errorDetails).get(AIAssistApplicationConstants.ANTHROPIC_FIELD_ERROR_MESSAGE);

                    if (providerErrorMessage != null) providerErrorDetail = (providerErrorType == null ? '' : providerErrorType + ' - ') + providerErrorMessage;
                }

                throw new AIAnthropicMessageResponseHandlerException('AI provider returned HTTP ' + anthropicHttpResponse.getStatusCode() + ': ' + providerErrorDetail);
            }

            // [6] The call worked, so read the reply
            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(rawResponseBody);
            List<Object> contentBlocks = (List<Object>) responseBody.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT);

            if (contentBlocks == null) contentBlocks = new List<Object>();

            AIProvider.Response agentResponse = new AIProvider.Response();
            List<String> responseTextLines = new List<String>();

            // [7] Go through the reply: text goes into the answer, tool requests go into the list of tool calls, anything else is skipped
            for (Object contentBlockObject : contentBlocks) {

                Map<String, Object> contentBlock = (Map<String, Object>) contentBlockObject;
                String contentBlockType = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_BLOCK_TYPE);

                if (contentBlockType == AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TEXT) {

                    String blockText = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TEXT);
                    responseTextLines.add(blockText);
                }

                if (contentBlockType == AIAssistApplicationConstants.ANTHROPIC_BLOCK_TYPE_TOOL_USE) {

                    Map<String, Object> toolArguments = (Map<String, Object>) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_INPUT);

                    AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
                    toolCall.id = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_USE_ID);
                    toolCall.name = (String) contentBlock.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_NAME);
                    toolCall.arguments = toolArguments != null ? toolArguments : new Map<String, Object>();

                    agentResponse.toolCalls.add(toolCall);
                }
            }

            agentResponse.textContent = String.join(responseTextLines, '\n');

            // [8] Work out how many tokens were used (anything missing counts as 0)
            Map<String, Object> tokenUsage = (Map<String, Object>) responseBody.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE);

            if (tokenUsage != null) {

                Integer inputTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE_INPUT_TOKENS);
                Integer outputTokens = (Integer) tokenUsage.get(AIAssistApplicationConstants.ANTHROPIC_FIELD_USAGE_OUTPUT_TOKENS);

                agentResponse.inputTokens = inputTokens != null ? inputTokens : 0;
                agentResponse.outputTokens = outputTokens != null ? outputTokens : 0;
                agentResponse.totalTokens = agentResponse.inputTokens + agentResponse.outputTokens;
            }

            // [9] Add Anthropic's reply to the conversation so the next request includes it
            providerMessages.add(new Map<String, Object>{
                AIAssistApplicationConstants.ANTHROPIC_ROLE_KEY => AIAssistApplicationConstants.ANTHROPIC_ROLE_ASSISTANT,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_CONTENT => contentBlocks
            });

            // [10] Hand back the answer and any tool calls
            return agentResponse;

        } catch (Exception ex) {

            // [11] Anything that goes wrong ends up here. Not logged here because AIAgentManager logs it, so it is only logged once. Our own errors are passed on as they are; anything else is wrapped with a clear message.
            if (ex instanceof AIAnthropicMessageResponseHandlerException) throw ex;
            throw new AIAnthropicMessageResponseHandlerException('Failed to handle the Anthropic response: ' + ex.getMessage(), ex);
        }
    }

    // Turns a setting like "200,201" into a set of numbers. Anything that is not a number is skipped.
    private static Set<Integer> buildIntegerSet(String commaSeparatedNumbers) {

        // [1] Start with an empty set
        Set<Integer> numbers = new Set<Integer>();

        // [2] Nothing to read when the setting is blank
        if (String.isBlank(commaSeparatedNumbers)) return numbers;

        // [3] Keep each entry that is a number
        for (String entry : commaSeparatedNumbers.split(',')) {

            if (entry.trim().isNumeric()) numbers.add(Integer.valueOf(entry.trim()));
        }

        // [4] Return the numbers
        return numbers;
    }
}
