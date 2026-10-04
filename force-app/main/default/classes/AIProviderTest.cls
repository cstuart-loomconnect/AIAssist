/*
Class Name: AIProviderTest

=================================================================
=================================================================

Description: Testing utility for AIProvider: the provider lookup and the canonical request and response types every provider adapter converts to and from.

=================================================================
=================================================================
Applicable Classes:

AIProvider
IAIProviderRequestBuilder
IAIProviderResponseHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIProviderTest {
  // testScenario1: Both supported providers are recognised in any case and each has a request builder and a response handler of its own.
  // testScenario2: An unknown, blank or null provider is not supported, and asking for its adapters throws.
  // testScenario3: stringifyToolResult passes a String through untouched and serialises anything else to JSON.
  // testScenario4: The canonical types start in a safe state: tool calls allowed on a request, and no tool calls and no tokens on a response.
  // testScenario5: getFailureReason maps a rejected credential, an exhausted quota, a retired model, rate limiting and a timeout to their own reasons, and anything else to a provider error.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    Test.startTest();
    Boolean isAnthropic = AIProvider.isSupported(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    Boolean isOpenAiLowerCase = AIProvider.isSupported(
      AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase()
    );
    IAIProviderRequestBuilder anthropicBuilder = AIProvider.getRequestBuilder(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    IAIProviderResponseHandler anthropicHandler = AIProvider.getResponseHandler(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    IAIProviderRequestBuilder openAiBuilder = AIProvider.getRequestBuilder(
      AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI
    );
    IAIProviderResponseHandler openAiHandler = AIProvider.getResponseHandler(
      AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI
    );
    Test.stopTest();

    Assert.isTrue(isAnthropic, 'Anthropic is supported.');
    Assert.isTrue(isOpenAiLowerCase, 'The match ignores case.');
    Assert.isTrue(
      anthropicBuilder instanceof AIAnthropicRequestBuilder,
      'Anthropic has its own request builder.'
    );
    Assert.isTrue(
      anthropicHandler instanceof AIAnthropicResponseHandler,
      'Anthropic has its own response handler.'
    );
    Assert.isTrue(
      openAiBuilder instanceof AIOpenAiRequestBuilder,
      'OpenAI has its own request builder.'
    );
    Assert.isTrue(
      openAiHandler instanceof AIOpenAiResponseHandler,
      'OpenAI has its own response handler.'
    );
  }

  @IsTest
  static void testScenario2() {
    Test.startTest();
    Boolean isUnknown = AIProvider.isSupported('Skynet');
    Boolean isBlank = AIProvider.isSupported('');
    Boolean isNull = AIProvider.isSupported(null);

    try {
      AIProvider.getRequestBuilder('Skynet');
      Assert.fail('An unsupported provider should have thrown.');
    } catch (AIProvider.AIProviderException ex) {
      Assert.isTrue(
        ex.getMessage().contains('Unsupported AI Provider'),
        'The error says the provider is unsupported.'
      );
    }

    try {
      AIProvider.getResponseHandler(null);
      Assert.fail('A null provider should have thrown.');
    } catch (AIProvider.AIProviderException ex) {
      Assert.isTrue(
        ex.getMessage().contains('Unsupported AI Provider'),
        'The error says the provider is unsupported.'
      );
    }
    Test.stopTest();

    Assert.isFalse(
      isUnknown || isBlank || isNull,
      'None of these is a provider.'
    );
  }

  @IsTest
  static void testScenario3() {
    Test.startTest();
    String fromString = AIProvider.stringifyToolResult('No records found.');
    String fromMap = AIProvider.stringifyToolResult(
      new Map<String, Object>{ 'count' => 2 }
    );
    String fromList = AIProvider.stringifyToolResult(
      new List<Object>{ 'a', 1 }
    );
    Test.stopTest();

    Assert.areEqual(
      'No records found.',
      fromString,
      'A String is passed through.'
    );
    Assert.areEqual('{"count":2}', fromMap, 'A map is serialised.');
    Assert.areEqual('["a",1]', fromList, 'A list is serialised.');
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    AIProvider.Request request = new AIProvider.Request();
    AIProvider.Response response = new AIProvider.Response();
    Test.stopTest();

    Assert.isTrue(
      request.allowToolCalls,
      'A request allows tool calls until the last iteration turns them off.'
    );
    Assert.isTrue(
      response.toolCalls.isEmpty(),
      'A response has no tool calls.'
    );
    Assert.areEqual(0, response.totalTokens, 'And no tokens.');
    Assert.areEqual(0, response.inputTokens, 'Nor input tokens.');
    Assert.areEqual(0, response.outputTokens, 'Nor output tokens.');
  }

  @IsTest
  static void testScenario5() {
    // Status and body, then the reason expected.
    List<List<Object>> cases = new List<List<Object>>{
      new List<Object>{
        401,
        '{"error":{"code":"invalid_api_key"}}',
        AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
      },
      new List<Object>{
        403,
        '{"type":"error","error":{"type":"permission_error"}}',
        AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
      },
      new List<Object>{
        429,
        '{"error":{"code":"insufficient_quota"}}',
        AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
      },
      new List<Object>{
        404,
        '{"error":{"code":"model_not_found"}}',
        AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
      },
      new List<Object>{
        404,
        '{"type":"error","error":{"type":"not_found_error","message":"model: claude-old"}}',
        AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
      },
      new List<Object>{
        410,
        null,
        AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
      },
      new List<Object>{
        400,
        'The model has been deprecated.',
        AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
      },
      new List<Object>{
        429,
        '{"error":{"code":"rate_limit_exceeded"}}',
        AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED
      },
      new List<Object>{
        408,
        '',
        AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
      },
      new List<Object>{
        504,
        'Gateway timeout',
        AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
      },
      new List<Object>{
        503,
        'Unavailable',
        AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
      },
      new List<Object>{
        404,
        'No such path',
        AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
      }
    };
    List<String> reasons = new List<String>();

    Test.startTest();
    for (List<Object> oneCase : cases)
      reasons.add(
        AIProvider.getFailureReason((Integer) oneCase[0], (String) oneCase[1])
      );
    Test.stopTest();

    for (Integer index = 0; index < cases.size(); index++)
      Assert.areEqual(
        cases[index][2],
        reasons[index],
        'HTTP ' + cases[index][0] + ' with ' + cases[index][1]
      );
  }
}
