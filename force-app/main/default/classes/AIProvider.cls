/*
Class Name: AIProvider

=================================================================
=================================================================

Description: Everything shared between AIAgentManager and the provider classes: the provider-agnostic data types and the provider lookup.

Step 1: Hold the canonical Request, ToolDefinition, Response and ToolCall types, with no provider-specific field names
Step 2: Look up the request builder and response handler for an AIModelConfiguration__c.AIProvider__c value
Step 3: Supply the connection preset for a provider and the failure reason for a refused request

Adding a provider: add its AIProvider__c picklist value and AI_PROVIDER_* constant, write its request builder and response handler, then add one line to each map below. AIAgentManager never changes.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIProvider {

    public class AIProviderException extends Exception {}

    // How a provider is connected to: what a Named Credential and a Model Configuration for it start from. The key itself is never here; headerValue is the formula that reads it from the External Credential named in {0}.
    public class Preset {
        public String baseUrl; // Null when the customer has their own.
        public String apiPath;
        public String headerName;
        public String headerValue;
        public String versionHeaderName;
        public String versionHeaderValue;
    }

    // The canonical shape of one outbound request to an AI provider. Built by AIAgentManager from AIModelConfiguration__c, the assembled system prompt, and conversation history and tools; an IAIProviderRequestBuilder then converts it into its provider's exact JSON shape.
    public class Request {
        public String modelIdentifier;
        public Integer maxOutputTokens;
        public Decimal temperature;
        public String systemPromptText;
        public List<Map<String, Object>> messages;
        public List<ToolDefinition> tools;
        // False on the last allowed iteration. Tools are still listed (providers reject a conversation containing tool calls without them) but the model may not call one, so it must answer.
        public Boolean allowToolCalls = true;
        // Only for a provider that answers over a session of several callouts (Anthropic Agent). The manager sets them; the request builder starts the session and the response handler reads the answer from it.
        public String endpoint; // Where the request is sent from the Named Credential and API path. The session's own endpoint, once it has one, replaces it.
        public String environmentId;
        public Integer maxWaitMilliseconds;
        public Session session;
    }

    // What a session-based provider keeps between the request builder, the response handler and the next pass of one turn. AIAgentManager makes one per turn and passes it on every request; it is empty for a provider that does not use it.
    public class Session {
        public String id;
        public String resumeId; // A session saved from an earlier turn of this conversation, set by the manager only for a provider that keeps the conversation. The request builder continues it when it can, else starts a new one.
        public Boolean isResumed = false; // True when the request builder continued resumeId, so the provider already holds the earlier messages and only the new one is sent.
        public String endpoint; // Where this session's requests are sent. Null until the session exists.
        public Map<String, String> headers = new Map<String, String>(); // Extra headers every request in this session needs.
    }

    // Apex does not allow a nested type to declare a nested type, so ToolDefinition sits alongside Request rather than inside it, even though it only ever appears as Request.tools.
    public class ToolDefinition {
        public String name;
        public String description;
        public Map<String, Object> inputSchema;
    }

    // The canonical shape of one parsed AI provider response. Each IAIProviderResponseHandler converts its provider's raw HttpResponse into this shape and appends its own provider-shaped copy of what the assistant said onto providerMessages. AIAgentManager reads only this shape, never a provider's raw JSON.
    public class Response {
        public String textContent;
        public List<ToolCall> toolCalls = new List<ToolCall>();
        public Decimal totalTokens = 0;
        public Decimal inputTokens = 0;
        public Decimal outputTokens = 0;
    }

    // Sits alongside Response for the same reason ToolDefinition sits alongside Request.
    public class ToolCall {
        public String id;
        public String name;
        public Map<String, Object> arguments;
    }

    // Keyed by the lower-cased AIProvider__c value, so the match is case-insensitive. Anthropic uses the Messages API; Anthropic Agent uses the Agent API (sessions and events); OpenAI also serves any OpenAI-compatible Chat Completions service, where the base URL is the Named Credential's.
    private static final Map<String, Type> REQUEST_BUILDER_BY_PROVIDER = new Map<String, Type>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicMessageRequestBuilder.class,
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT.toLowerCase() => AIAnthropicAgentRequestBuilder.class,
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase() => AIOpenAiRequestBuilder.class
    };

    private static final Map<String, Type> RESPONSE_HANDLER_BY_PROVIDER = new Map<String, Type>{
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicMessageResponseHandler.class,
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT.toLowerCase() => AIAnthropicAgentResponseHandler.class,
        AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase() => AIOpenAiResponseHandler.class
    };

    // The preset for a provider, or null for one this package does not know. An OpenAI-compatible service uses the OpenAI preset with its own base URL.
    public static Preset getPreset(String providerName, String modelIdentifier) {

        // [1] Nothing to build for a provider this package does not know
        if (!isSupported(providerName)) return null;

        // [2] Start an empty preset
        Preset preset = new Preset();

        // [3] Fill it in for Anthropic or Anthropic Agent, otherwise for OpenAI
        if (providerName.equalsIgnoreCase(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT)) {

            preset.baseUrl = 'https://api.anthropic.com';
            preset.apiPath = '/v1/sessions';
            preset.headerName = 'x-api-key';
            preset.headerValue = '{!$Credential.{0}.ApiKey}';
            preset.versionHeaderName = AIAssistApplicationConstants.ANTHROPIC_AGENT_VERSION_HEADER_NAME;
            preset.versionHeaderValue = AIAssistApplicationConstants.ANTHROPIC_AGENT_VERSION_HEADER_VALUE;

        } else if (providerName.equalsIgnoreCase(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC)) {

            preset.baseUrl = 'https://api.anthropic.com';
            preset.apiPath = '/v1/messages';
            preset.headerName = 'x-api-key';
            preset.headerValue = '{!$Credential.{0}.ApiKey}';
            preset.versionHeaderName = 'anthropic-version';
            preset.versionHeaderValue = '2023-06-01';

        } else {

            preset.baseUrl = 'https://api.openai.com';
            preset.apiPath = '/v1/chat/completions';
            preset.headerName = 'Authorization';
            preset.headerValue = 'Bearer {!$Credential.{0}.ApiKey}';
        }

        // [4] Return the preset
        return preset;
    }

    // True when AIProvider__c names a provider with a request builder and a response handler.
    public static Boolean isSupported(String providerName) {

        // [1] A blank name is never a provider
        if (String.isBlank(providerName)) return false;

        // [2] Supported only when both lookups know the provider
        return REQUEST_BUILDER_BY_PROVIDER.containsKey(providerName.toLowerCase()) && RESPONSE_HANDLER_BY_PROVIDER.containsKey(providerName.toLowerCase());
    }

    // The request builder for a provider. Throws for an unsupported provider - check isSupported first for a clearer error.
    public static IAIProviderRequestBuilder getRequestBuilder(String providerName) {

        // [1] Refuse a provider this package does not know
        if (!isSupported(providerName)) throw new AIProviderException('Unsupported AI Provider "' + providerName + '".');

        // [2] Create and return a new builder
        return (IAIProviderRequestBuilder) REQUEST_BUILDER_BY_PROVIDER.get(providerName.toLowerCase()).newInstance();
    }

    // The response handler for a provider. Throws for an unsupported provider - check isSupported first for a clearer error.
    public static IAIProviderResponseHandler getResponseHandler(String providerName) {

        // [1] Refuse a provider this package does not know
        if (!isSupported(providerName)) throw new AIProviderException('Unsupported AI Provider "' + providerName + '".');

        // [2] Create and return a new handler
        return (IAIProviderResponseHandler) RESPONSE_HANDLER_BY_PROVIDER.get(providerName.toLowerCase()).newInstance();
    }

    // Why a provider refused a request, from its HTTP status and what its error body says, as an AIConversationMessage__c.FailureReason__c value. The body is checked because providers reuse statuses: OpenAI answers 429 for an exhausted quota (which waiting does not fix) and 404 for a retired model.
    public static String getFailureReason(Integer statusCode, String responseBody) {

        // [1] Lower-case the body so the text checks ignore case
        String body = responseBody == null ? '' : responseBody.toLowerCase();

        // [2] A rejected or unpaid credential
        if (statusCode == 401 || statusCode == 403 || body.contains('invalid_api_key') || body.contains('authentication_error') || body.contains('permission_error') || body.contains('insufficient_quota')) return AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED;

        // [3] A model that has been retired or removed
        if (statusCode == 410 || body.contains('model_not_found') || body.contains('deprecated') || body.contains('decommissioned') || (statusCode == 404 && body.contains('model'))) return AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED;

        // [4] Too many requests
        if (statusCode == 429) return AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED;

        // [5] The provider took too long
        if (statusCode == 408 || statusCode == 504) return AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;

        // [6] Anything else is a provider error
        return AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
    }

    // Tool results are fed back to the provider as text either way - a String passes through untouched, anything else is JSON-serialized.
    public static String stringifyToolResult(Object toolResult) {

        // [1] A String needs no conversion
        if (toolResult instanceof String) return (String) toolResult;

        try {

            // [2] Turn anything else into JSON text
            return JSON.serialize(toolResult);

        } catch (Exception ex) {
            // [3] Not serializable, so fall back to its plain text rather than losing the result
            return String.valueOf(toolResult);
        }
    }
}
