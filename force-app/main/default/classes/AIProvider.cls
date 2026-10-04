/*
Class Name: AIProvider

=================================================================
=================================================================

Description: Everything shared between AIAgentManager and the provider classes (the
IAIProviderRequestBuilder/IAIProviderResponseHandler implementations):
- The canonical, provider-agnostic data types - Request/ToolDefinition going out, Response/ToolCall
  coming back. No provider-specific field names live on these; each provider class converts to
  and from its own JSON shape.
- The provider lookup - which request builder and response handler serve each
  AIModelConfiguration__c.AIProvider__c value.

Adding a provider: add its AIProvider__c picklist value and AI_PROVIDER_* constant, write its
request builder and response handler, then add one line to each map below. AIAgentManager never
changes.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development - Request/ToolDefinition/Response/ToolCall and stringifyToolResult moved from AIAgentManager, plus the provider lookup.
2.0          Chandler Stuart          Azure OpenAI, provider presets for the credential set-up, and getFailureReason.
*/

public inherited sharing class AIProvider {
  public class AIProviderException extends Exception {
  }

  // Keyed by the lower-cased AIProvider__c value, so the match is case-insensitive.
  private static final Map<String, Type> REQUEST_BUILDER_BY_PROVIDER = new Map<String, Type>{
    AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicRequestBuilder.class, // Anthropic - Messages API
    AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase() => AIOpenAiRequestBuilder.class, // OpenAI, and any service with an OpenAI-compatible Chat Completions API: the base URL is the Named Credential's
    AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI.toLowerCase() => AIAzureOpenAiRequestBuilder.class // Azure OpenAI - the deployment is in the URL
  };

  private static final Map<String, Type> RESPONSE_HANDLER_BY_PROVIDER = new Map<String, Type>{
    AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC.toLowerCase() => AIAnthropicResponseHandler.class,
    AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase() => AIOpenAiResponseHandler.class,
    AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI.toLowerCase() => AIOpenAiResponseHandler.class // The same reply shape as OpenAI
  };

  // How a provider is connected to: what a Named Credential and a Model Configuration for it start from. The key itself is never here; headerValue is the formula that reads it from the External Credential named in {0}.
  public class Preset {
    public String baseUrl; // Null when the customer has their own (Azure: https://{resource}.openai.azure.com).
    public String apiPath;
    public String headerName;
    public String headerValue;
    public String versionHeaderName;
    public String versionHeaderValue;
  }

  // The preset for a provider, or null for one this package does not know. modelIdentifier is the Azure deployment name; other providers ignore it. An OpenAI-compatible service uses the OpenAI preset with its own base URL.
  public static Preset getPreset(String providerName, String modelIdentifier) {
    if (!isSupported(providerName))
      return null;

    Preset preset = new Preset();
    if (
      providerName.equalsIgnoreCase(
        AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
      )
    ) {
      preset.baseUrl = 'https://api.anthropic.com';
      preset.apiPath = '/v1/messages';
      preset.headerName = 'x-api-key';
      preset.headerValue = '{!$Credential.{0}.ApiKey}';
      preset.versionHeaderName = 'anthropic-version';
      preset.versionHeaderValue = '2023-06-01';
    } else if (
      providerName.equalsIgnoreCase(
        AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI
      )
    ) {
      preset.apiPath =
        '/openai/deployments/' +
        (String.isBlank(modelIdentifier)
          ? 'deployment'
          : EncodingUtil.urlEncode(modelIdentifier.trim(), 'UTF-8')) +
        '/chat/completions?api-version=' +
        AIAssistApplicationConstants.AZURE_OPEN_AI_DEFAULT_API_VERSION;
      preset.headerName = 'api-key';
      preset.headerValue = '{!$Credential.{0}.ApiKey}';
    } else {
      preset.baseUrl = 'https://api.openai.com';
      preset.apiPath = '/v1/chat/completions';
      preset.headerName = 'Authorization';
      preset.headerValue = 'Bearer {!$Credential.{0}.ApiKey}';
    }

    return preset;
  }

  // The canonical shape of one outbound request to an AI provider. Built by AIAgentManager from
  // AIModelConfiguration__c, the assembled system prompt, and conversation history/tools - an
  // IAIProviderRequestBuilder then converts it into its provider's exact JSON shape.
  public class Request {
    public String modelIdentifier;
    public Integer maxOutputTokens;
    public Decimal temperature;
    public String systemPromptText;
    public List<Map<String, Object>> messages;
    public List<ToolDefinition> tools;
    // false on the last allowed iteration - tools are still listed (providers reject a conversation containing tool calls without them) but the model may not call one, so it must answer.
    public Boolean allowToolCalls = true;
  }

  // Apex doesn't allow a nested type to itself declare a nested type, so ToolDefinition sits
  // alongside Request rather than inside it, even though it only ever appears as Request.tools.
  public class ToolDefinition {
    public String name;
    public String description;
    public Map<String, Object> inputSchema;
  }

  // The canonical shape of one parsed AI provider response. Each IAIProviderResponseHandler
  // converts its provider's raw HttpResponse into this shape (and appends its own provider-shaped
  // representation of "what the assistant said" directly onto providerMessages itself) -
  // AIAgentManager's tool-calling loop reads only this shape, never a provider's raw JSON.
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

  // True when AIProvider__c names a provider with a request builder and response handler.
  public static Boolean isSupported(String providerName) {
    if (String.isBlank(providerName))
      return false;
    return REQUEST_BUILDER_BY_PROVIDER.containsKey(
        providerName.toLowerCase()
      ) && RESPONSE_HANDLER_BY_PROVIDER.containsKey(providerName.toLowerCase());
  }

  // Throws for an unsupported provider - check isSupported first for a clearer error.
  public static IAIProviderRequestBuilder getRequestBuilder(
    String providerName
  ) {
    if (!isSupported(providerName))
      throw new AIProviderException(
        'Unsupported AI Provider "' + providerName + '".'
      );
    return (IAIProviderRequestBuilder) REQUEST_BUILDER_BY_PROVIDER.get(
        providerName.toLowerCase()
      )
      .newInstance();
  }

  // Throws for an unsupported provider - check isSupported first for a clearer error.
  public static IAIProviderResponseHandler getResponseHandler(
    String providerName
  ) {
    if (!isSupported(providerName))
      throw new AIProviderException(
        'Unsupported AI Provider "' + providerName + '".'
      );
    return (IAIProviderResponseHandler) RESPONSE_HANDLER_BY_PROVIDER.get(
        providerName.toLowerCase()
      )
      .newInstance();
  }

  // Why a provider refused a request, from its HTTP status and what its error body says, as an AIConversationMessage__c.FailureReason__c value. The body is checked because providers reuse statuses: OpenAI answers 429 for an exhausted quota (which waiting does not fix) and 404 for a retired model.
  public static String getFailureReason(
    Integer statusCode,
    String responseBody
  ) {
    String body = responseBody == null ? '' : responseBody.toLowerCase();

    if (
      statusCode == 401 ||
      statusCode == 403 ||
      body.contains('invalid_api_key') ||
      body.contains('authentication_error') ||
      body.contains('permission_error') ||
      body.contains('insufficient_quota')
    )
      return AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED;

    if (
      statusCode == 410 ||
      body.contains('model_not_found') ||
      body.contains('deprecated') ||
      body.contains('decommissioned') ||
      (statusCode == 404 && body.contains('model'))
    )
      return AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED;

    if (statusCode == 429)
      return AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED;

    if (statusCode == 408 || statusCode == 504)
      return AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;

    return AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR;
  }

  // Tool results are fed back to the provider as text either way - a String passes through untouched, anything else is JSON-serialized.
  public static String stringifyToolResult(Object toolResult) {
    if (toolResult instanceof String)
      return (String) toolResult;
    try {
      return JSON.serialize(toolResult);
    } catch (Exception caughtException) {
      return String.valueOf(toolResult); // Not serializable - fall back to its plain text form rather than losing the result.
    }
  }
}
