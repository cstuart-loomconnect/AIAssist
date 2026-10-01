/*
Class Name: AIOpenAiRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiRequestBuilder: the canonical request becomes the exact JSON body OpenAI expects.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiRequestBuilder

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIOpenAiRequestBuilderTest {
  // testScenario1: The required fields are present and optional ones are omitted when unset.
  // testScenario2: The system prompt is the first message with the system role, unlike Anthropic where it is a top-level field, and the temperature is sent when set.
  // testScenario3: Tools are wrapped in a function object, and tool_choice none is added only when tool calls are not allowed.
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
    Map<String, Object> body = new AIOpenAiRequestBuilder()
      .buildRequestBody(request);
    Test.stopTest();

    Assert.areEqual('test-model', body.get('model'), 'The model.');
    Assert.areEqual(512, body.get('max_tokens'), 'The output cap.');
    Assert.areEqual(
      1,
      ((List<Object>) body.get('messages')).size(),
      'Just the one message.'
    );
    Assert.isFalse(
      body.containsKey('temperature') || body.containsKey('tools'),
      'Unset optional keys are omitted.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIProvider.Request request = buildRequest();
    request.systemPromptText = 'Be brief.';
    request.temperature = 0.7;

    Test.startTest();
    Map<String, Object> body = new AIOpenAiRequestBuilder()
      .buildRequestBody(request);
    Test.stopTest();

    List<Object> messages = (List<Object>) body.get('messages');
    Map<String, Object> first = (Map<String, Object>) messages[0];

    Assert.areEqual(
      2,
      messages.size(),
      'The system message plus the conversation.'
    );
    Assert.areEqual(
      'system',
      first.get('role'),
      'The first message has the system role.'
    );
    Assert.areEqual(
      'Be brief.',
      first.get('content'),
      'It carries the system prompt.'
    );
    Assert.isFalse(
      body.containsKey('system'),
      'There is no top-level system field.'
    );
    Assert.areEqual(0.7, body.get('temperature'), 'The temperature.');
  }

  @IsTest
  static void testScenario3() {
    AIProvider.Request allowed = buildRequest();
    allowed.tools = new List<AIProvider.ToolDefinition>{ buildTool() };
    AIProvider.Request forbidden = buildRequest();
    forbidden.tools = new List<AIProvider.ToolDefinition>{ buildTool() };
    forbidden.allowToolCalls = false;

    Test.startTest();
    Map<String, Object> allowedBody = new AIOpenAiRequestBuilder()
      .buildRequestBody(allowed);
    Map<String, Object> forbiddenBody = new AIOpenAiRequestBuilder()
      .buildRequestBody(forbidden);
    Test.stopTest();

    Map<String, Object> tool = (Map<String, Object>) ((List<Object>) allowedBody.get(
      'tools'
    ))[0];
    Map<String, Object> function = (Map<String, Object>) tool.get('function');

    Assert.areEqual(
      'function',
      tool.get('type'),
      'OpenAI wraps each tool in a function object.'
    );
    Assert.areEqual('lookup', function.get('name'), 'The tool name.');
    Assert.isNotNull(
      function.get('parameters'),
      'The input schema is the parameters.'
    );
    Assert.isFalse(
      allowedBody.containsKey('tool_choice'),
      'Tool calls are allowed.'
    );
    Assert.areEqual(
      'none',
      forbiddenBody.get('tool_choice'),
      'On the last iteration the model may not call a tool.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      new AIOpenAiRequestBuilder().buildRequestBody(null);
      Assert.fail('A null request should have thrown.');
    } catch (AIOpenAiRequestBuilder.AIOpenAiRequestBuilderException ex) {
      Assert.isTrue(
        ex.getMessage().startsWith('Failed to build the OpenAI request body'),
        'The error names the adapter.'
      );
      Assert.isNotNull(ex.getCause(), 'The original error is kept.');
    }
    Test.stopTest();
  }
}
