/*
Class Name: AIAzureOpenAiRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for the Azure OpenAI provider and for an OpenAI-compatible service on the OpenAI provider: the request each sends, the reply read back, and a tool call answered.

=================================================================
=================================================================
Applicable Classes:

AIAzureOpenAiRequestBuilder, AIProvider, AIAgentManager

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAzureOpenAiRequestBuilderTest {
  // testScenario1: The Azure body is OpenAI's without the model: messages, max tokens, temperature and tools are kept, and tool_choice none on the last iteration.
  // testScenario2: An Azure turn calls the deployment URL on the model's Named Credential, sends no model, and reads the reply and its tokens as OpenAI's.
  // testScenario3: An Azure tool call runs the data source and its result goes back as a tool message, and the second reply ends the turn.
  // testScenario4: An OpenAI-compatible service is the OpenAI provider with its own base URL: the call goes to that Named Credential and path, with the model in the body.
  // testScenario5: The presets: each provider's base URL, path and key header, the Azure path built from the deployment, and none for an unknown provider.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    settings.CalloutTimeoutMilliseconds__c = 30000;
    upsert settings;
  }

  // Plays back a script of responses, one per callout, and remembers what it was sent.
  private class ScriptedMock implements HttpCalloutMock {
    List<String> bodies = new List<String>();
    List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest request) {
      requests.add(request);
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      response.setBody(bodies.remove(0));
      return response;
    }
  }

  private class World {
    AIModelConfiguration__c model;
    AIAgent__c agent;
    AIConversation__c conversation;
    List<AIConversationMessage__c> history;
  }

  private static World createWorld(
    String provider,
    String namedCredential,
    String modelIdentifier,
    String apiPath
  ) {
    World world = new World();
    world.model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    world.model.AIProvider__c = provider;
    world.model.NamedCredential__c = namedCredential;
    world.model.ModelIdentifier__c = modelIdentifier;
    world.model.ApiPath__c = apiPath;
    insert world.model;
    world.agent = AIAssistTestDataFactory.createAIAgents(
      1,
      world.model.Id,
      true
    )[0];
    world.conversation = AIAssistTestDataFactory.createAIConversations(
      world.agent.Id,
      1,
      true
    )[0];
    world.history = AIAssistTestDataFactory.createAIConversationMessages(
      world.conversation.Id,
      null,
      1,
      false
    );

    return world;
  }

  private static AIAgentManager.AgentResult run(
    World world,
    List<AIDataSource__c> dataSources
  ) {
    return AIAgentManager.executeAiMessage(
      world.agent,
      world.model,
      null,
      world.conversation,
      world.history,
      dataSources,
      new List<AIWorkflowAction__c>(),
      1,
      new AIExecutionStepTracker(world.conversation.Id, null, false, false)
    );
  }

  private static String text(String reply) {
    return '{"choices":[{"message":{"role":"assistant","content":' +
      JSON.serialize(reply) +
      '}}],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}';
  }

  @IsTest
  static void testScenario1() {
    AIProvider.Request request = new AIProvider.Request();
    request.modelIdentifier = 'my-deployment';
    request.maxOutputTokens = 500;
    request.temperature = 0.2;
    request.systemPromptText = 'Be brief.';
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
    };
    AIProvider.ToolDefinition tool = new AIProvider.ToolDefinition();
    tool.name = 'lookup';
    tool.description = 'Looks something up.';
    tool.inputSchema = new Map<String, Object>{ 'type' => 'object' };
    request.tools = new List<AIProvider.ToolDefinition>{ tool };
    request.allowToolCalls = false;

    Test.startTest();
    Map<String, Object> azureBody = AIProvider.getRequestBuilder(
        AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI
      )
      .buildRequestBody(request);
    Map<String, Object> openAiBody = new AIOpenAiRequestBuilder()
      .buildRequestBody(request);
    Test.stopTest();

    Assert.isFalse(azureBody.containsKey('model'), 'No model: it is the URL.');
    Assert.areEqual('my-deployment', openAiBody.get('model'), 'OpenAI has it.');
    openAiBody.remove('model');
    Assert.areEqual(
      JSON.serialize(openAiBody),
      JSON.serialize(azureBody),
      'Everything else is the same as OpenAI.'
    );
    Assert.areEqual(
      2,
      ((List<Object>) azureBody.get('messages')).size(),
      'The system prompt and the question.'
    );
    Assert.areEqual(
      'none',
      azureBody.get('tool_choice'),
      'No tool call on the last iteration.'
    );
  }

  @IsTest
  static void testScenario2() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI,
      'Azure_Resource',
      'my-deployment',
      AIProvider.getPreset(
          AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI,
          'my-deployment'
        )
        .apiPath
    );
    ScriptedMock mock = new ScriptedMock();
    mock.bodies.add(text('Hello from Azure'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult result = run(world, new List<AIDataSource__c>());
    Test.stopTest();

    Assert.isTrue(
      result.isSuccessful,
      'The turn succeeded: ' + result.errorMessage
    );
    Assert.areEqual('Hello from Azure', result.replyText, 'The reply.');
    Assert.areEqual(8, result.inputTokens, 'Prompt tokens.');
    Assert.areEqual(4, result.outputTokens, 'Completion tokens.');
    Assert.areEqual(
      'callout:Azure_Resource/openai/deployments/my-deployment/chat/completions?api-version=' +
      AIAssistApplicationConstants.AZURE_OPEN_AI_DEFAULT_API_VERSION,
      mock.requests[0].getEndpoint(),
      'The deployment URL on the Named Credential.'
    );
    Assert.isFalse(
      ((Map<String, Object>) JSON.deserializeUntyped(
          mock.requests[0].getBody()
        ))
        .containsKey('model'),
      'No model in the body.'
    );
    Assert.isNull(
      mock.requests[0].getHeader('api-key'),
      'The key is the Named Credential\'s to add: this code never holds it.'
    );
  }

  @IsTest
  static void testScenario3() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI,
      'Azure_Resource',
      'my-deployment',
      '/openai/deployments/my-deployment/chat/completions?api-version=2024-10-21'
    );
    Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
    world.conversation.RelatedRecordId__c = String.valueOf(account.Id);
    update world.conversation;
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL,
      'SELECT Id, Name FROM Account WHERE Id = :recordId',
      false
    )[0];
    dataSource.TargetObject__c = 'Account';
    insert dataSource;
    AIAssistTestDataFactory.createAIAgentDataSources(
      world.agent.Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );
    List<AIDataSource__c> dataSources = AIMessagingSelector.getAssignedDataSources(
      world.agent.Id
    );
    ScriptedMock mock = new ScriptedMock();
    mock.bodies.add(
      '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"' +
        dataSources[0].DeveloperName__c +
        '","arguments":"{}"}}]}}],"usage":{"prompt_tokens":6,"completion_tokens":2,"total_tokens":8}}'
    );
    mock.bodies.add(text('The account is found.'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult result = run(world, dataSources);
    Test.stopTest();

    Assert.isTrue(
      result.isSuccessful,
      'The turn succeeded: ' + result.errorMessage
    );
    Assert.areEqual(
      'The account is found.',
      result.replyText,
      'The final reply.'
    );
    Assert.areEqual(2, mock.requests.size(), 'The tool call, then the answer.');
    Assert.areEqual(20, result.totalTokensUsed, 'Both calls are counted.');
    List<Object> secondMessages = (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
        mock.requests[1].getBody()
      ))
      .get('messages');
    Map<String, Object> toolMessage = (Map<String, Object>) secondMessages[
      secondMessages.size() - 1
    ];
    Assert.areEqual(
      'tool',
      toolMessage.get('role'),
      'The result goes back as a tool message.'
    );
    Assert.areEqual(
      'call_1',
      toolMessage.get('tool_call_id'),
      'Answering the call.'
    );
    Assert.isFalse(
      ((Map<String, Object>) JSON.deserializeUntyped(
          mock.requests[1].getBody()
        ))
        .containsKey('model'),
      'Still no model on the second call.'
    );
  }

  @IsTest
  static void testScenario4() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI,
      'Compatible_Service',
      'llama-3.3-70b',
      '/openai/v1/chat/completions'
    );
    ScriptedMock mock = new ScriptedMock();
    mock.bodies.add(text('Hello from a compatible service'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult result = run(world, new List<AIDataSource__c>());
    Test.stopTest();

    Assert.isTrue(
      result.isSuccessful,
      'The turn succeeded: ' + result.errorMessage
    );
    Assert.areEqual(
      'callout:Compatible_Service/openai/v1/chat/completions',
      mock.requests[0].getEndpoint(),
      'The service\'s own base URL (the Named Credential) and path.'
    );
    Assert.areEqual(
      'llama-3.3-70b',
      ((Map<String, Object>) JSON.deserializeUntyped(
          mock.requests[0].getBody()
        ))
        .get('model'),
      'The model is in the body, as on OpenAI.'
    );
    Assert.areEqual(
      'Hello from a compatible service',
      result.replyText,
      'Read as OpenAI\'s reply.'
    );
  }

  @IsTest
  static void testScenario5() {
    Test.startTest();
    AIProvider.Preset anthropic = AIProvider.getPreset(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      null
    );
    AIProvider.Preset openAi = AIProvider.getPreset(
      AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI,
      null
    );
    AIProvider.Preset azure = AIProvider.getPreset(
      AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI,
      'gpt 4o'
    );
    AIProvider.Preset azureNoDeployment = AIProvider.getPreset(
      AIAssistApplicationConstants.AI_PROVIDER_AZURE_OPEN_AI,
      null
    );
    AIProvider.Preset unknown = AIProvider.getPreset('Something Else', null);
    Test.stopTest();

    Assert.areEqual(
      'https://api.anthropic.com',
      anthropic.baseUrl,
      'Anthropic.'
    );
    Assert.areEqual(
      'x-api-key',
      anthropic.headerName,
      'Anthropic\'s key header.'
    );
    Assert.areEqual(
      'anthropic-version',
      anthropic.versionHeaderName,
      'Its version header.'
    );
    Assert.areEqual(
      'https://api.openai.com',
      openAi.baseUrl,
      'OpenAI, unless another base URL is given.'
    );
    Assert.areEqual('/v1/chat/completions', openAi.apiPath, 'OpenAI.');
    Assert.isTrue(openAi.headerValue.startsWith('Bearer '), 'A bearer token.');
    Assert.isNull(
      azure.baseUrl,
      'Azure\'s base URL is the customer\'s own resource.'
    );
    Assert.areEqual('api-key', azure.headerName, 'Azure\'s key header.');
    Assert.isTrue(
      azure.apiPath.startsWith(
        '/openai/deployments/gpt+4o/chat/completions?api-version='
      ),
      'The deployment is in the path, encoded: ' + azure.apiPath
    );
    Assert.isTrue(
      azureNoDeployment.apiPath.contains('/deployments/deployment/'),
      'A placeholder.'
    );
    Assert.isNull(
      unknown,
      'No preset for a provider this package does not know.'
    );
  }
}
