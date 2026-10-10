/*
Class Name: AIAnthropicMessageRequestBuilder

=================================================================
=================================================================

Description: Builds the request body for Anthropic's Messages API.

Step 1: Add the required fields (model, max tokens, messages)
Step 2: Add the optional fields only when they are set (temperature, system prompt)
Step 3: Add the tool definitions, and stop the model calling tools on the last iteration
Step 4: Return the request body

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAnthropicMessageRequestBuilder implements IAIProviderRequestBuilder {

    public class AIAnthropicMessageRequestBuilderException extends Exception {}

    // Builds { model, max_tokens, messages, [temperature], [system], [tools] } - optional keys are left out entirely when unset, never sent as null.
    public Map<String, Object> buildRequestBody(AIProvider.Request request) {

        try {

            // [1] Add the required fields - Anthropic rejects a request missing any of these
            Map<String, Object> requestBody = new Map<String, Object>{
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MODEL => request.modelIdentifier,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MAX_TOKENS => request.maxOutputTokens,
                AIAssistApplicationConstants.ANTHROPIC_FIELD_MESSAGES => request.messages
            };

            // [2] Add the temperature only when it is set, so Anthropic's own default applies otherwise
            if (request.temperature != null) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TEMPERATURE, request.temperature);

            // [3] Add the system prompt as a top-level field (unlike OpenAI, where it is a system-role message)
            if (String.isNotBlank(request.systemPromptText)) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_SYSTEM, request.systemPromptText);

            // [4] Add one { name, description, input_schema } entry per tool, in Anthropic's flat tool shape with no OpenAI-style "function" wrapper
            if (request.tools != null && !request.tools.isEmpty()) {

                List<Object> toolDefinitions = new List<Object>();

                for (AIProvider.ToolDefinition tool : request.tools) {

                    toolDefinitions.add(new Map<String, Object>{
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_NAME => tool.name,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_DESCRIPTION => tool.description,
                        AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_INPUT_SCHEMA => tool.inputSchema
                    });
                }

                requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOLS, toolDefinitions);

                // [5] On the last tool-calling iteration keep the tools listed (Anthropic rejects tool_use blocks without tools) but tell the model not to call one
                if (request.allowToolCalls == false) requestBody.put(AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_CHOICE, new Map<String, Object>{AIAssistApplicationConstants.ANTHROPIC_FIELD_TOOL_CHOICE_TYPE => AIAssistApplicationConstants.ANTHROPIC_TOOL_CHOICE_NONE});
            }

            // [6] Return the request body
            return requestBody;

        } catch (Exception ex) {
            throw new AIAnthropicMessageRequestBuilderException('Failed to build the Anthropic request body: ' + ex.getMessage(), ex);
        }
    }
}
