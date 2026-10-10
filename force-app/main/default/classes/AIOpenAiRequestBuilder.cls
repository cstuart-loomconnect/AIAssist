/*
Class Name: AIOpenAiRequestBuilder

=================================================================
=================================================================

Description: Builds the request body for OpenAI's Chat Completions API.

Step 1: Put the system prompt first, as a system-role message, followed by the conversation
Step 2: Add the required fields (model, max tokens, messages) and the temperature if one is set
Step 3: Wrap each tool in a function object and stop the model calling tools on the last pass
Step 4: Return the request body

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIOpenAiRequestBuilder implements IAIProviderRequestBuilder {
  public class AIOpenAiRequestBuilderException extends Exception {
  }

  // Builds the OpenAI request body. Optional keys are left out completely when they are not set, never sent as null.
  public Map<String, Object> buildRequestBody(AIProvider.Request request) {
    try {
      // [1] Put the system prompt first as a system-role message (OpenAI has no top-level system field)
      List<Map<String, Object>> allMessages = new List<Map<String, Object>>();

      if (String.isNotBlank(request.systemPromptText)) {
        Map<String, Object> systemMessage = new Map<String, Object>{
          AIAssistApplicationConstants.OPENAI_ROLE_KEY => AIAssistApplicationConstants.OPENAI_ROLE_SYSTEM,
          AIAssistApplicationConstants.OPENAI_FIELD_CONTENT => request.systemPromptText
        };
        allMessages.add(systemMessage);
      }

      allMessages.addAll(request.messages);

      // [2] Add the fields OpenAI rejects the request without
      Map<String, Object> requestBody = new Map<String, Object>{
        AIAssistApplicationConstants.OPENAI_FIELD_MODEL => request.modelIdentifier,
        AIAssistApplicationConstants.OPENAI_FIELD_MAX_TOKENS => request.maxOutputTokens,
        AIAssistApplicationConstants.OPENAI_FIELD_MESSAGES => allMessages
      };

      // [3] Add the temperature only when one is set
      if (request.temperature != null)
        requestBody.put(
          AIAssistApplicationConstants.OPENAI_FIELD_TEMPERATURE,
          request.temperature
        );

      // [4] Add the tools, each wrapped in a function object as OpenAI expects
      if (request.tools != null && !request.tools.isEmpty()) {
        List<Object> toolDefinitions = new List<Object>();

        for (AIProvider.ToolDefinition tool : request.tools) {
          Map<String, Object> functionDetails = new Map<String, Object>{
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_NAME => tool.name,
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_DESCRIPTION => tool.description,
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_PARAMETERS => tool.inputSchema
          };

          Map<String, Object> toolDefinition = new Map<String, Object>{
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_TYPE => AIAssistApplicationConstants.OPENAI_TOOL_TYPE_FUNCTION,
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_FUNCTION => functionDetails
          };

          toolDefinitions.add(toolDefinition);
        }

        requestBody.put(
          AIAssistApplicationConstants.OPENAI_FIELD_TOOLS,
          toolDefinitions
        );

        // [5] On the last pass keep the tools listed (OpenAI only accepts tool_choice alongside tools) but tell the model not to call one
        if (request.allowToolCalls == false)
          requestBody.put(
            AIAssistApplicationConstants.OPENAI_FIELD_TOOL_CHOICE,
            AIAssistApplicationConstants.OPENAI_TOOL_CHOICE_NONE
          );
      }

      // [6] Return the finished request body
      return requestBody;
    } catch (Exception ex) {
      throw new AIOpenAiRequestBuilderException(
        'Failed to build the OpenAI request body: ' + ex.getMessage(),
        ex
      );
    }
  }
}
