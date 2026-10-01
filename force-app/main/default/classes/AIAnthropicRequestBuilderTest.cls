/*
Class Name: AIAnthropicRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicRequestBuilder: the canonical request becomes the exact JSON body Anthropic expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicRequestBuilder

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAnthropicRequestBuilderTest {
  // testScenario1: The required fields are present, and the optional temperature, system prompt and tools are omitted entirely when unset rather than sent as null.
  // testScenario2: Temperature and the system prompt are sent when set; the system prompt is a top-level field, not a message.
  // testScenario3: Tools are sent in Anthropic's flat shape, and tool_choice none is added only when tool calls are not allowed.
  // testScenario4: A request that cannot be built throws the adapter's own exception with the original as its cause.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private static AIProvider.Request buildRequest() {
    AIProvider.Request request = new AIProvider.Request();
    request.modelIdentifier = 'test-model';
    request.maxOutputTokens = 512;
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
    };

    return request;
  }

  private static AIProvider.ToolDefinition buildTool() {
    AIProvider.ToolDefinition tool = new AIProvider.ToolDefinition();
    tool.name = 'lookup';
    tool.description = 'Looks something up';
    tool.inputSchema = new Map<String, Object>{ 'type' => 'object' };

    return tool;
  }

  @IsTest
  static void testScenario1() {
    AIProvider.Request request = buildRequest();

    Test.startTest();
    Map<String, Object> body = new AIAnthropicRequestBuilder()
      .buildRequestBody(request);
    Test.stopTest();

    Assert.areEqual('test-model', body.get('model'), 'The model.');
    Assert.areEqual(512, body.get('max_tokens'), 'The output cap.');
    Assert.areEqual(request.messages, body.get('messages'), 'The messages.');
    Assert.isFalse(
      body.containsKey('temperature'),
      'No temperature set, so none is sent.'
    );
    Assert.isFalse(
      body.containsKey('system'),
      'No system prompt set, so none is sent.'
    );
    Assert.isFalse(
      body.containsKey('tools'),
      'No tools set, so none are sent.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIProvider.Request request = buildRequest();
    request.temperature = 0.4;
    request.systemPromptText = 'Be brief.';

    Test.startTest();
    Map<String, Object> body = new AIAnthropicRequestBuilder()
      .buildRequestBody(request);
    Test.stopTest();

    Assert.areEqual(0.4, body.get('temperature'), 'The temperature.');
    Assert.areEqual(
      'Be brief.',
      body.get('system'),
      'The system prompt is a top-level field on Anthropic.'
    );
    Assert.areEqual(
      1,
      ((List<Object>) body.get('messages')).size(),
      'And not a message.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIProvider.Request allowed = buildRequest();
    allowed.tools = new List<AIProvider.ToolDefinition>{ buildTool() };
    AIProvider.Request forbidden = buildRequest();
    forbidden.tools = new List<AIProvider.ToolDefinition>{ buildTool() };
    forbidden.allowToolCalls = false;

    Test.startTest();
    Map<String, Object> allowedBody = new AIAnthropicRequestBuilder()
      .buildRequestBody(allowed);
    Map<String, Object> forbiddenBody = new AIAnthropicRequestBuilder()
      .buildRequestBody(forbidden);
    Test.stopTest();

    Map<String, Object> tool = (Map<String, Object>) ((List<Object>) allowedBody.get(
      'tools'
    ))[0];

    Assert.areEqual('lookup', tool.get('name'), 'The tool name.');
    Assert.areEqual(
      'Looks something up',
      tool.get('description'),
      'The description.'
    );
    Assert.isNotNull(
      tool.get('input_schema'),
      'The input schema, flat, with no function wrapper.'
    );
    Assert.isFalse(
      allowedBody.containsKey('tool_choice'),
      'Tool calls are allowed, so nothing is restricted.'
    );
    Assert.areEqual(
      'none',
      ((Map<String, Object>) forbiddenBody.get('tool_choice')).get('type'),
      'On the last iteration the model may not call a tool.'
    );
    Assert.isNotNull(
      forbiddenBody.get('tools'),
      'But the tools stay listed, or Anthropic rejects a conversation that already contains tool calls.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      new AIAnthropicRequestBuilder().buildRequestBody(null);
      Assert.fail('A null request should have thrown.');
    } catch (AIAnthropicRequestBuilder.AIAnthropicRequestBuilderException ex) {
      Assert.isTrue(
        ex.getMessage()
          .startsWith('Failed to build the Anthropic request body'),
        'The error names the adapter.'
      );
      Assert.isNotNull(ex.getCause(), 'The original error is kept.');
    }
    Test.stopTest();
  }
}
