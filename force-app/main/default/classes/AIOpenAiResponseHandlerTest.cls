/*
Class Name: AIOpenAiResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiResponseHandler: the OpenAI response becomes the canonical response, and the conversation sent back is shaped the way OpenAI expects.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiResponseHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIOpenAiResponseHandlerTest {
  // testScenario1: A reply becomes the reply text with prompt and completion tokens split, and the assistant message is appended as returned.
  // testScenario2: Tool calls are read from the function object, with their JSON argument string deserialised, and a null content becomes blank text.
  // testScenario3: Tool results from the previous pass become one tool-role message per call, each keyed by its tool_call_id.
  // testScenario4: A different number of results than calls throws.
  // testScenario5: A failure status throws with the provider's own error or the raw body, and a response with no choices or no message throws.
  // testScenario6: A malformed body throws the adapter's own exception with the original as its cause.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static HttpResponse buildResponse(Integer statusCode, String body) {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(statusCode);
    response.setBody(body);

    return response;
  }

  private static AIProvider.ToolCall buildToolCall(String id) {
    AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
    toolCall.id = id;
    toolCall.name = 'lookup';
    toolCall.arguments = new Map<String, Object>();

    return toolCall;
  }

  @IsTest
  static void testScenario1() {
    List<Map<String, Object>> messages = new List<Map<String, Object>>();
    HttpResponse response = buildResponse(
      200,
      '{"choices":[{"message":{"role":"assistant","content":"Hello"}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}'
    );

    Test.startTest();
    AIProvider.Response result = new AIOpenAiResponseHandler()
      .handleResponse(messages, response, null, null);
    Test.stopTest();

    Assert.areEqual('Hello', result.textContent, 'The reply text.');
    Assert.areEqual(10, result.inputTokens, 'Prompt tokens are the input.');
    Assert.areEqual(
      5,
      result.outputTokens,
      'Completion tokens are the output.'
    );
    Assert.areEqual(15, result.totalTokens, 'The total is OpenAI\'s own.');
    Assert.areEqual(1, messages.size(), 'The assistant message is appended.');
  }

  @IsTest
  static void testScenario2() {
    List<Map<String, Object>> messages = new List<Map<String, Object>>();
    HttpResponse response = buildResponse(
      200,
      '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"lookup","arguments":"{\\"q\\":\\"x\\"}"}},{"id":"c2","type":"function","function":{"name":"other","arguments":""}}]}}],"usage":{"total_tokens":9}}'
    );

    Test.startTest();
    AIProvider.Response result = new AIOpenAiResponseHandler()
      .handleResponse(messages, response, null, null);
    Test.stopTest();

    Assert.areEqual(2, result.toolCalls.size(), 'Both tool calls.');
    Assert.areEqual('c1', result.toolCalls[0].id, 'The id.');
    Assert.areEqual(
      'x',
      result.toolCalls[0].arguments.get('q'),
      'The argument string is deserialised.'
    );
    Assert.isTrue(
      result.toolCalls[1].arguments.isEmpty(),
      'A blank argument string means no arguments.'
    );
    Assert.areEqual('', result.textContent, 'Null content is blank text.');
    Assert.areEqual(9, result.totalTokens, 'The total tokens.');
    Assert.areEqual(
      0,
      result.inputTokens,
      'With no prompt tokens reported the input is zero.'
    );
  }

  @IsTest
  static void testScenario3() {
    List<Map<String, Object>> messages = new List<Map<String, Object>>();
    List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{
      buildToolCall('c1'),
      buildToolCall('c2')
    };

    Test.startTest();
    AIProvider.Response result = new AIOpenAiResponseHandler()
      .handleResponse(
        messages,
        null,
        calls,
        new List<Object>{ 'first', 'second' }
      );
    Test.stopTest();

    Assert.isNull(result, 'With no response there is nothing to parse.');
    Assert.areEqual(
      2,
      messages.size(),
      'OpenAI wants a message per tool call, not one batch.'
    );
    Assert.areEqual('tool', messages[0].get('role'), 'Each has the tool role.');
    Assert.areEqual(
      'c2',
      messages[1].get('tool_call_id'),
      'Each names the call it answers.'
    );
    Assert.areEqual(
      'second',
      messages[1].get('content'),
      'And carries its result.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      new AIOpenAiResponseHandler()
        .handleResponse(
          new List<Map<String, Object>>(),
          null,
          new List<AIProvider.ToolCall>{ buildToolCall('c1') },
          null
        );
      Assert.fail('A result count mismatch should have thrown.');
    } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
      Assert.isTrue(
        ex.getMessage().contains('does not match'),
        'The error says the counts differ.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario5() {
    List<HttpResponse> responses = new List<HttpResponse>{
      buildResponse(
        429,
        '{"error":{"type":"rate_limit_exceeded","message":"Slow down"}}'
      ),
      buildResponse(500, 'Server error'),
      buildResponse(200, '{"choices":[]}'),
      buildResponse(200, '{"choices":[{"index":0}]}')
    };
    List<String> messages = new List<String>();

    Test.startTest();
    for (HttpResponse response : responses) {
      try {
        new AIOpenAiResponseHandler()
          .handleResponse(
            new List<Map<String, Object>>(),
            response,
            null,
            null
          );
        Assert.fail('Each of these should have thrown.');
      } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
        messages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(
      'AI provider returned HTTP 429: rate_limit_exceeded - Slow down',
      messages[0],
      'The provider\'s error type and message.'
    );
    Assert.areEqual(
      'AI provider returned HTTP 500: Server error',
      messages[1],
      'The raw body when it is not JSON.'
    );
    Assert.isTrue(
      messages[2].contains('no choices'),
      'A response with no choices is refused.'
    );
    Assert.isTrue(
      messages[3].contains('no message'),
      'A choice with no message is refused.'
    );
  }

  @IsTest
  static void testScenario6() {
    Test.startTest();
    try {
      new AIOpenAiResponseHandler()
        .handleResponse(
          new List<Map<String, Object>>(),
          buildResponse(200, 'not json'),
          null,
          null
        );
      Assert.fail('A malformed body should have thrown.');
    } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {
      Assert.isTrue(
        ex.getMessage().startsWith('Failed to handle the OpenAI response'),
        'The error names the adapter.'
      );
      Assert.isNotNull(ex.getCause(), 'The original error is kept.');
    }
    Test.stopTest();
  }
}
