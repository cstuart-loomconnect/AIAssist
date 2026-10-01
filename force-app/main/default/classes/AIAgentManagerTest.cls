/*
Class Name: AIAgentManagerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentManager: one turn with the AI provider, on mocked callouts, covering the reply, the tool-calling loop, retries, failures and the evidence left behind.

=================================================================
=================================================================
Applicable Classes:

AIAgentManager

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAgentManagerTest {
  // testScenario1: A text reply is returned with its tokens and latency, the callout is pinned to the model's Named Credential and carries the system prompt and history, and a workflow action the model suggests is resolved and stripped from the reply.
  // testScenario2: A tool call runs the data source as a step, its records go back to the model on the next pass, and the second provider call records what was sent: the object, the field names and the record count.
  // testScenario3: An OpenAI reply is parsed the same way, with the system prompt as the first message and prompt and completion tokens split.
  // testScenario4: A retryable status ends the attempt as retryable while attempts remain, is not retryable on the last, and a timeout status is reported as a timeout.
  // testScenario5: A callout exception is retryable, and one that says timed out is reported as a timeout while any other is a provider error.
  // testScenario6: A status that is neither a success nor retryable fails the turn for good with the provider's own error kept for the log.
  // testScenario7: A model configuration with no Named Credential, a credential or path of the wrong shape, or an unsupported provider fails as a configuration error before any callout.
  // testScenario8: A data source that writes to the database throws AIDataSourceWriteException, carrying the tokens spent so far, before the next callout is attempted.
  // testScenario9: A tool the model made up fails with a generic message, tool calls beyond the per-reply cap are skipped with an explanation, and the turn still completes.
  // testScenario10: Tool calls on the last allowed iteration fail the turn as a limit, and a reply with no text fails it as a provider error.

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  private class World {
    AIModelConfiguration__c model;
    AIAgent__c agent;
    AIPromptTemplate__c template;
    AIConversation__c conversation;
    List<AIConversationMessage__c> history;
  }

  // Plays back a script of responses and exceptions, one per callout, and remembers what it was sent.
  private class ScriptedMock implements HttpCalloutMock {
    List<Object> script = new List<Object>();
    List<HttpRequest> requests = new List<HttpRequest>();

    public HttpResponse respond(HttpRequest request) {
      requests.add(request);
      Object next = script.remove(0);
      if (next instanceof Exception)
        throw (Exception) next;
      return (HttpResponse) next;
    }
  }

  // An Apex data source that writes to the database, which a data source must never do.
  public class WritingExecutor implements IAIDataSourceExecutor {
    public List<SObject> execute(
      Id recordId,
      Map<String, Object> inputParameters
    ) {
      insert new Account(Name = 'Written by a data source');
      return new List<SObject>();
    }
  }

  private static World createWorld(String provider) {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.CalloutTimeoutMilliseconds__c = 30000;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    World world = new World();
    world.model = AIAssistTestDataFactory.createAIModelConfigurations(
      1,
      false
    )[0];
    world.model.AIProvider__c = provider;
    insert world.model;
    world.agent = AIAssistTestDataFactory.createAIAgents(
      1,
      world.model.Id,
      true
    )[0];
    world.template = AIAssistTestDataFactory.createAIPromptTemplates(
      world.agent.Id,
      1,
      false
    )[0];
    world.template.AIPrompt__c = 'Be brief.';
    insert world.template;
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

  private static HttpResponse response(Integer statusCode, String body) {
    HttpResponse httpResponse = new HttpResponse();
    httpResponse.setStatusCode(statusCode);
    httpResponse.setBody(body);

    return httpResponse;
  }

  private static String anthropicText(String text) {
    return '{"content":[{"type":"text","text":' +
      JSON.serialize(text) +
      '}],"usage":{"input_tokens":10,"output_tokens":5}}';
  }

  private static String anthropicToolUse(String id, String toolName) {
    return '{"content":[{"type":"tool_use","id":"' +
      id +
      '","name":"' +
      toolName +
      '","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}';
  }

  private static AIAgentManager.AgentResult run(
    World world,
    List<AIDataSource__c> dataSources,
    List<AIWorkflowAction__c> actions,
    Integer attemptNumber,
    AIExecutionStepTracker trace
  ) {
    return AIAgentManager.executeAiMessage(
      world.agent,
      world.model,
      world.template,
      world.conversation,
      world.history,
      dataSources,
      actions,
      attemptNumber,
      trace
    );
  }

  @IsTest
  static void testScenario1() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(
      1,
      AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW,
      'Some_Flow',
      true
    )[0];
    AIAssistTestDataFactory.createAIAgentWorkflowActions(
      world.agent.Id,
      new List<AIWorkflowAction__c>{ action },
      true
    );
    List<AIWorkflowAction__c> actions = AIMessagingSelector.getAssignedActions(
      world.agent.Id
    );
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        200,
        anthropicText(
          'Here you go.\n{"suggested_workflow_action":"' +
            actions[0].DeveloperName__c +
            '"}'
        )
      )
    );
    Test.setMock(HttpCalloutMock.class, mock);
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      world.conversation.Id,
      null,
      false,
      false
    );

    Test.startTest();
    AIAgentManager.AgentResult result = run(
      world,
      new List<AIDataSource__c>(),
      actions,
      1,
      trace
    );
    Test.stopTest();

    Assert.isTrue(result.isSuccessful, 'The turn succeeded.');
    Assert.areEqual(
      'Here you go.',
      result.replyText,
      'The suggestion line is stripped from the visible reply.'
    );
    Assert.areEqual(
      String.valueOf(action.Id),
      result.suggestedWorkflowActionId,
      'The suggested action is resolved to a real action that was offered.'
    );
    Assert.areEqual(15, result.totalTokensUsed, 'Total tokens.');
    Assert.areEqual(10, result.inputTokens, 'Input tokens.');
    Assert.areEqual(5, result.outputTokens, 'Output tokens.');
    Assert.isNotNull(result.latencyMilliseconds, 'How long the turn took.');
    Assert.isFalse(result.isRetryable, 'A success is never retried.');
    Assert.areEqual(1, mock.requests.size(), 'One callout.');
    Assert.areEqual(
      'callout:Test_Credential/v1/messages',
      mock.requests[0].getEndpoint(),
      'The callout is pinned to the model configuration\'s Named Credential.'
    );
    Assert.isTrue(
      mock.requests[0].getBody().contains('Be brief.'),
      'The prompt template is sent as the system prompt.'
    );
    Assert.isTrue(
      mock.requests[0].getBody().contains('Test message 0'),
      'The history is sent.'
    );
    Assert.isTrue(
      mock.requests[0].getBody().contains(actions[0].DeveloperName__c),
      'The offered workflow action is described to the model.'
    );
    Assert.areEqual(1, trace.steps.size(), 'One provider call step.');
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL,
      trace.steps[0].stepType,
      'It is a provider call.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC,
      trace.steps[0].provider,
      'It records the provider.'
    );
    Assert.areEqual(
      'test-model',
      trace.steps[0].modelIdentifier,
      'And the model.'
    );
  }

  @IsTest
  static void testScenario2() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
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
    String accountName = [SELECT Name FROM Account WHERE Id = :account.Id].Name;
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        200,
        anthropicToolUse('toolu_1', dataSources[0].DeveloperName__c)
      )
    );
    mock.script.add(response(200, anthropicText('The account is found.')));
    Test.setMock(HttpCalloutMock.class, mock);
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      world.conversation.Id,
      null,
      false,
      false
    );

    Test.startTest();
    AIAgentManager.AgentResult result = run(
      world,
      dataSources,
      new List<AIWorkflowAction__c>(),
      1,
      trace
    );
    Test.stopTest();

    Assert.isTrue(
      result.isSuccessful,
      'The turn succeeded after the tool call.'
    );
    Assert.areEqual(2, mock.requests.size(), 'Two provider calls.');
    Assert.isTrue(
      mock.requests[0].getBody().contains('"tools"'),
      'The first request advertises the tool.'
    );
    Assert.isTrue(
      mock.requests[1].getBody().contains('tool_result') &&
      mock.requests[1].getBody().contains(accountName),
      'The second request carries the data source\'s records back.'
    );
    Assert.areEqual(
      3,
      trace.steps.size(),
      'Provider call, data source, provider call.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE,
      trace.steps[1].stepType,
      'The middle step is the data source.'
    );
    Assert.areEqual(
      dataSource.Id,
      trace.steps[1].dataSourceId,
      'It names the data source.'
    );
    Assert.areEqual(
      1,
      trace.steps[2].recordsSentCount,
      'The record count that went to the provider.'
    );
    Assert.areEqual(
      'Account',
      trace.steps[2].objectsSent,
      'The object that went.'
    );
    Assert.isTrue(
      trace.steps[2].fieldsSent.contains('Account.Name'),
      'The field names that went, never the values.'
    );
    Assert.isFalse(
      trace.steps[2].fieldsSent.contains(accountName),
      'The values never appear in the evidence.'
    );
    Assert.areEqual(
      2,
      trace.toolCallingIterationsUsed,
      'Two iterations were used.'
    );
  }

  @IsTest
  static void testScenario3() {
    World world = createWorld(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI);
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        200,
        '{"choices":[{"message":{"role":"assistant","content":"Hello from OpenAI"}}],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}'
      )
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult result = run(
      world,
      new List<AIDataSource__c>(),
      new List<AIWorkflowAction__c>(),
      1,
      new AIExecutionStepTracker(world.conversation.Id, null, false, false)
    );
    Test.stopTest();

    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requests[0].getBody()
    );
    Map<String, Object> firstMessage = (Map<String, Object>) ((List<Object>) sent.get(
      'messages'
    ))[0];

    Assert.isTrue(result.isSuccessful, 'The turn succeeded.');
    Assert.areEqual('Hello from OpenAI', result.replyText, 'The reply.');
    Assert.areEqual(8, result.inputTokens, 'Prompt tokens.');
    Assert.areEqual(4, result.outputTokens, 'Completion tokens.');
    Assert.areEqual(
      'system',
      firstMessage.get('role'),
      'The system prompt is the first message on OpenAI.'
    );
  }

  @IsTest
  static void testScenario4() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    ); // The model allows two retries: three attempts.
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(response(503, 'Unavailable'));
    mock.script.add(response(408, 'Request timeout'));
    mock.script.add(response(503, 'Unavailable'));
    Test.setMock(HttpCalloutMock.class, mock);
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.RetryableStatusCodes__c = '408,429,503';
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    AIAgentManager.AgentResult first = run(world, null, null, 1, null);
    AIAgentManager.AgentResult second = run(world, null, null, 2, null);
    AIAgentManager.AgentResult last = run(world, null, null, 3, null);
    Test.stopTest();

    Assert.isTrue(first.isRetryable, 'The first attempt can be retried.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      first.failureReason,
      'A 503 is a provider error.'
    );
    Assert.isTrue(second.isRetryable, 'The second attempt can be retried.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
      second.failureReason,
      'A 408 is a timeout.'
    );
    Assert.isFalse(last.isRetryable, 'The last attempt cannot be retried.');
    Assert.isFalse(last.isSuccessful, 'And it failed.');
    Assert.isTrue(
      first.errorMessage.contains('503'),
      'The detail for the log names the status.'
    );
  }

  @IsTest
  static void testScenario5() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(new CalloutException('Read timed out'));
    mock.script.add(new CalloutException('Unable to tunnel through proxy'));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult timedOut = run(world, null, null, 1, null);
    AIAgentManager.AgentResult unreachable = run(world, null, null, 1, null);
    Test.stopTest();

    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT,
      timedOut.failureReason,
      'A timeout.'
    );
    Assert.isTrue(timedOut.isRetryable, 'A callout exception is retried.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      unreachable.failureReason,
      'Any other callout failure is a provider error.'
    );
    Assert.isTrue(
      unreachable.errorMessage.contains('Unable to tunnel'),
      'The detail for the log keeps the real reason.'
    );
  }

  @IsTest
  static void testScenario6() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        400,
        '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens is too large"}}'
      )
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult result = run(world, null, null, 1, null);
    Test.stopTest();

    Assert.isFalse(result.isSuccessful, 'The turn failed.');
    Assert.isFalse(
      result.isRetryable,
      'A bad request will not succeed on retry.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      result.failureReason,
      'A provider error.'
    );
    Assert.isTrue(
      result.errorMessage.contains('max_tokens is too large'),
      'The provider\'s message is kept for the log.'
    );
  }

  @IsTest
  static void testScenario7() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    ScriptedMock mock = new ScriptedMock();
    Test.setMock(HttpCalloutMock.class, mock);

    AIModelConfiguration__c noCredential = world.model.clone(true);
    noCredential.NamedCredential__c = null;
    AIModelConfiguration__c wrongCredential = world.model.clone(true);
    wrongCredential.NamedCredential__c = 'Bad Credential!';
    AIModelConfiguration__c wrongPath = world.model.clone(true);
    wrongPath.ApiPath__c = '/v1/../admin';
    AIModelConfiguration__c wrongProvider = world.model.clone(true);
    wrongProvider.AIProvider__c = 'Skynet';
    List<AIAgentManager.AgentResult> results = new List<AIAgentManager.AgentResult>();

    Test.startTest();
    for (
      AIModelConfiguration__c badModel : new List<AIModelConfiguration__c>{
        noCredential,
        wrongCredential,
        wrongPath,
        wrongProvider
      }
    ) {
      results.add(
        AIAgentManager.executeAiMessage(
          world.agent,
          badModel,
          world.template,
          world.conversation,
          world.history,
          null,
          null,
          1,
          null
        )
      );
    }
    Test.stopTest();

    for (AIAgentManager.AgentResult result : results) {
      Assert.isFalse(
        result.isSuccessful,
        'A badly configured model cannot succeed.'
      );
      Assert.areEqual(
        AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR,
        result.failureReason,
        'It is a configuration error.'
      );
      Assert.isFalse(result.isRetryable, 'And will not fix itself on retry.');
    }
    Assert.isTrue(
      mock.requests.isEmpty(),
      'No callout was made to an endpoint that failed its checks.'
    );
  }

  @IsTest
  static void testScenario8() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(
      1,
      AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX,
      'AIAgentManagerTest.WritingExecutor',
      false
    )[0];
    dataSource.BindingType__c = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
    insert dataSource;
    AIAssistTestDataFactory.createAIAgentDataSources(
      world.agent.Id,
      new List<AIDataSource__c>{ dataSource },
      true
    );
    AIPlanLimitService.setLimitForTest(
      AIAssistApplicationConstants.FEATURE_APEX_DATA_SOURCES_ALLOWED,
      true
    );
    List<AIDataSource__c> dataSources = AIMessagingSelector.getAssignedDataSources(
      world.agent.Id
    );
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        200,
        anthropicToolUse('toolu_1', dataSources[0].DeveloperName__c)
      )
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    try {
      run(world, dataSources, null, 1, null);
      Assert.fail('A data source that writes should have thrown.');
    } catch (AIAgentManager.AIDataSourceWriteException ex) {
      Assert.isTrue(
        ex.getMessage().contains('wrote to the database'),
        'The error says the data source wrote.'
      );
      Assert.areEqual(
        6,
        ex.tokensUsed,
        'The tokens spent so far are kept so they can still be recorded after the rollback.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      1,
      mock.requests.size(),
      'The next callout was never attempted.'
    );
  }

  @IsTest
  static void testScenario9() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.MaxToolCallsPerIteration__c = 1;
    update settings;
    AIAssistSettingsService.cachedSettings = null;
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(
      response(
        200,
        '{"content":[{"type":"tool_use","id":"t1","name":"made_up_tool","input":{}},{"type":"tool_use","id":"t2","name":"another_tool","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}'
      )
    );
    mock.script.add(response(200, anthropicText('I could not look that up.')));
    Test.setMock(HttpCalloutMock.class, mock);
    AIExecutionStepTracker trace = new AIExecutionStepTracker(
      world.conversation.Id,
      null,
      false,
      false
    );

    Test.startTest();
    AIAgentManager.AgentResult result = run(world, null, null, 1, trace);
    Test.stopTest();

    String secondRequest = mock.requests[1].getBody();

    Assert.isTrue(result.isSuccessful, 'The turn completes.');
    Assert.isTrue(
      secondRequest.contains('This tool failed to run'),
      'The unknown tool gets the generic failure message, not the real error.'
    );
    Assert.isTrue(
      secondRequest.contains('too many tool calls'),
      'The second call is skipped with an explanation, because providers reject an unanswered tool call.'
    );
    Assert.isFalse(
      secondRequest.contains('made_up_tool\' was requested'),
      'The real error stays out of what the model is told.'
    );
    Assert.areEqual(
      AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE,
      trace.steps[1].stepType,
      'The failed tool is a data source step, not a provider call.'
    );
    Assert.isFalse(trace.steps[1].isSuccess, 'And it is recorded as failed.');
  }

  @IsTest
  static void testScenario10() {
    World world = createWorld(
      AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC
    );
    world.agent.MaxToolCallingIterations__c = 1;
    update world.agent;
    ScriptedMock mock = new ScriptedMock();
    mock.script.add(response(200, anthropicToolUse('t1', 'made_up_tool')));
    mock.script.add(response(200, anthropicText('   ')));
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    AIAgentManager.AgentResult limited = run(world, null, null, 1, null);
    AIAgentManager.AgentResult empty = run(world, null, null, 1, null);
    Test.stopTest();

    Assert.isFalse(limited.isSuccessful, 'The turn did not finish.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED,
      limited.failureReason,
      'It ran out of iterations.'
    );
    Assert.areEqual(
      6,
      limited.totalTokensUsed,
      'The tokens it spent are reported.'
    );
    Assert.isFalse(empty.isSuccessful, 'A blank reply is not a success.');
    Assert.areEqual(
      AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR,
      empty.failureReason,
      'It is reported as a provider error.'
    );
  }
}
