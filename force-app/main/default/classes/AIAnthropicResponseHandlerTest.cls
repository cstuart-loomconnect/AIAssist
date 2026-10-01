/*
Class Name: AIAnthropicResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicResponseHandler: the Anthropic response becomes the canonical response, and the conversation sent back is shaped the way Anthropic expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicResponseHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAnthropicResponseHandlerTest {
  // testScenario1: A text reply becomes the reply text with input and output tokens split, and the assistant's content is appended to the conversation as returned.
  // testScenario2: tool_use blocks become tool calls with their id, name and arguments, and a reply with only tool calls has no text.
  // testScenario3: Tool results from the previous pass are batched into one user message with a tool_result per call, and passing no response returns null.
  // testScenario4: A different number of results than calls throws, because Anthropic rejects a tool_use with no tool_result.
  // testScenario5: A status outside the success codes throws with the provider's own error, falling back to the raw body when it is not JSON.
  // testScenario6: A status listed in the success codes setting is accepted, and a body that is not valid JSON throws the adapter's own exception.

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
      '{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"there"}],"usage":{"input_tokens":10,"output_tokens":5}}'
    );

    Test.startTest();
    AIProvider.Response result = new AIAnthropicResponseHandler()
      .handleResponse(messages, response, null, null);
    Test.stopTest();

    Assert.areEqual(
      'Hello\nthere',
      result.textContent,
      'Text blocks are joined.'
    );
    Assert.areEqual(10, result.inputTokens, 'Input tokens.');
    Assert.areEqual(5, result.outputTokens, 'Output tokens.');
    Assert.areEqual(15, result.totalTokens, 'The total is input plus output.');
    Assert.isTrue(result.toolCalls.isEmpty(), 'No tool calls.');
    Assert.areEqual(1, messages.size(), 'The assistant turn is appended.');
    Assert.areEqual(
      'assistant',
      messages[0].get('role'),
      'With the assistant role.'
    );
  }

  @IsTest
  static void testScenario2() {
    List<Map<String, Object>> messages = new List<Map<String, Object>>();
    HttpResponse response = buildResponse(
      200,
      '{"content":[{"type":"tool_use","id":"t1","name":"lookup","input":{"q":"x"}},{"type":"tool_use","id":"t2","name":"other"}],"usage":{"input_tokens":4,"output_tokens":2}}'
    );

    Test.startTest();
    AIProvider.Response result = new AIAnthropicResponseHandler()
      .handleResponse(messages, response, null, null);
    Test.stopTest();

    Assert.areEqual(2, result.toolCalls.size(), 'Both tool calls.');
    Assert.areEqual(
      't1',
      result.toolCalls[0].id,
      'The id is kept so the result can be paired.'
    );
    Assert.areEqual('lookup', result.toolCalls[0].name, 'The tool name.');
    Assert.areEqual(
      'x',
      result.toolCalls[0].arguments.get('q'),
      'The arguments.'
    );
    Assert.isTrue(
      result.toolCalls[1].arguments.isEmpty(),
      'Missing arguments become an empty map.'
    );
    Assert.areEqual('', result.textContent, 'No text blocks, no text.');
  }

  @IsTest
  static void testScenario3() {
    List<Map<String, Object>> messages = new List<Map<String, Object>>();
    List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{
      buildToolCall('t1'),
      buildToolCall('t2')
    };

    Test.startTest();
    AIProvider.Response result = new AIAnthropicResponseHandler()
      .handleResponse(
        messages,
        null,
        calls,
        new List<Object>{ 'first result', new List<Object>{ 'a' } }
      );
    Test.stopTest();

    List<Object> blocks = (List<Object>) messages[0].get('content');

    Assert.isNull(result, 'With no response there is nothing to parse.');
    Assert.areEqual(1, messages.size(), 'Every result goes in one message.');
    Assert.areEqual(
      'user',
      messages[0].get('role'),
      'Anthropic has no tool role: results come back as a user message.'
    );
    Assert.areEqual(2, blocks.size(), 'One block per tool call.');
    Assert.areEqual(
      't1',
      ((Map<String, Object>) blocks[0]).get('tool_use_id'),
      'Each result names the call it answers.'
    );
    Assert.areEqual(
      '["a"]',
      ((Map<String, Object>) blocks[1]).get('content'),
      'A non-text result is serialised.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      new AIAnthropicResponseHandler()
        .handleResponse(
          new List<Map<String, Object>>(),
          null,
          new List<AIProvider.ToolCall>{ buildToolCall('t1') },
          new List<Object>()
        );
      Assert.fail('A result count mismatch should have thrown.');
    } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
      Assert.isTrue(
        ex.getMessage().contains('does not match'),
        'The error says the counts differ.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void testScenario5() {
    HttpResponse jsonError = buildResponse(
      400,
      '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens is too large"}}'
    );
    HttpResponse rawError = buildResponse(502, 'Bad gateway');
    List<String> messages = new List<String>();

    Test.startTest();
    for (
      HttpResponse response : new List<HttpResponse>{ jsonError, rawError }
    ) {
      try {
        new AIAnthropicResponseHandler()
          .handleResponse(
            new List<Map<String, Object>>(),
            response,
            null,
            null
          );
        Assert.fail('A failure status should have thrown.');
      } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
        messages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    Assert.areEqual(
      'AI provider returned HTTP 400: invalid_request_error - max_tokens is too large',
      messages[0],
      'The provider\'s error type and message.'
    );
    Assert.areEqual(
      'AI provider returned HTTP 502: Bad gateway',
      messages[1],
      'The raw body when it is not JSON.'
    );
  }

  @IsTest
  static void testScenario6() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.AIProviderSuccessStatusCodes__c = '200,201';
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    HttpResponse created = buildResponse(
      201,
      '{"content":[{"type":"text","text":"Created"}]}'
    );
    HttpResponse malformed = buildResponse(200, 'not json at all');
    AIProvider.Response result;
    String malformedMessage;

    Test.startTest();
    result = new AIAnthropicResponseHandler()
      .handleResponse(new List<Map<String, Object>>(), created, null, null);

    try {
      new AIAnthropicResponseHandler()
        .handleResponse(new List<Map<String, Object>>(), malformed, null, null);
      Assert.fail('A malformed body should have thrown.');
    } catch (AIAnthropicResponseHandler.AIAnthropicResponseHandlerException ex) {
      malformedMessage = ex.getMessage();
    }
    Test.stopTest();

    Assert.areEqual(
      'Created',
      result.textContent,
      'A 201 is a success when the setting says so.'
    );
    Assert.isTrue(
      malformedMessage.startsWith('Failed to handle the Anthropic response'),
      'An unexpected error is wrapped with the original as its cause.'
    );
  }
}
