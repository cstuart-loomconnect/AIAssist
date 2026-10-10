/*
Class Name: AIAnthropicAgentRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicAgentRequestBuilder: the canonical request becomes the events body an Anthropic Agent API session expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicAgentRequestBuilder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAnthropicAgentRequestBuilderTest {
  // testScenario1: Building a single user message with a system prompt -> a system message event then a user message event holding the text as it is.
  // testScenario2: Building a conversation with earlier messages -> the user message event holds the earlier turns labelled by speaker, then the latest message.
  // testScenario3: Building when the last message holds tool results -> one custom tool result event per result, each naming the call it answers, and no system prompt.
  // testScenario4: Building with no messages, no session on the request, or a last message with no tool results -> the adapter's own exception is thrown.
  // testScenario5: Building when the session has no id yet -> a session is started for the agent and environment, and the request's session then holds its id, its events endpoint and the beta header.
  // testScenario6: Building when the agent or environment id is missing, or Anthropic refuses the session -> the adapter's own exception says why, with no events built.

  private static final String SYSTEM_PROMPT = 'Be brief.';
  private static final String USER_TEXT = 'What is the status?';
  private static final String ASSISTANT_TEXT = 'It is open.';
  private static final String SESSIONS_ENDPOINT = 'callout:Anthropic/v1/sessions';

  // Plays Anthropic's session start: a session id, or a refusal.
  private class SessionStartMock implements HttpCalloutMock {
    public Integer statusCode = 200;
    public Integer callCount = 0;
    public String requestBody;

    public HttpResponse respond(HttpRequest request) {
      callCount++;
      requestBody = request.getBody();

      HttpResponse httpResponse = new HttpResponse();
      httpResponse.setStatusCode(statusCode);
      httpResponse.setBody(
        statusCode == 200
          ? '{"id":"sesn_1"}'
          : '{"error":{"type":"authentication_error","message":"bad key"}}'
      );

      return httpResponse;
    }
  }

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
    // [1] Build a request with one user message and a system prompt
    AIProvider.Request request = new AIProvider.Request();
    request.systemPromptText = SYSTEM_PROMPT;
    request.session = new AIProvider.Session();
    request.session.id = 'sesn_1';
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT }
    };

    Map<String, Object> body;

    // [2] Build the body
    Test.startTest();
    body = new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
    Test.stopTest();

    // [3] Read the events back
    List<Object> events = (List<Object>) body.get('events');
    Map<String, Object> systemEvent = (Map<String, Object>) events[0];
    Map<String, Object> userEvent = (Map<String, Object>) events[1];
    Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) userEvent.get(
      'content'
    ))[0];

    // [4] Check the events
    Assert.areEqual(
      2,
      events.size(),
      'There should be a system event and a user event.'
    );
    Assert.areEqual(
      'system.message',
      systemEvent.get('type'),
      'The system prompt should go first as a system message.'
    );
    Assert.areEqual(
      'user.message',
      userEvent.get('type'),
      'The user text should be a user message.'
    );
    Assert.areEqual(
      USER_TEXT,
      userBlock.get('text'),
      'A single message should be sent as it is.'
    );
  }

  @IsTest
  static void testScenario2() {
    // [1] Build a request with an earlier exchange and a new user message
    AIProvider.Request request = new AIProvider.Request();
    request.session = new AIProvider.Session();
    request.session.id = 'sesn_1';
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
      new Map<String, Object>{
        'role' => 'assistant',
        'content' => ASSISTANT_TEXT
      },
      new Map<String, Object>{ 'role' => 'user', 'content' => 'And now?' }
    };

    Map<String, Object> body;

    // [2] Build the body
    Test.startTest();
    body = new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
    Test.stopTest();

    // [3] Read the text of the only event
    List<Object> events = (List<Object>) body.get('events');
    Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) events[0])
      .get('content'))[0];

    // [4] Check the earlier turns are written out above the latest message
    Assert.areEqual(
      1,
      events.size(),
      'With no system prompt there should be one event.'
    );
    Assert.areEqual(
      'Conversation so far:\nUser: ' +
        USER_TEXT +
        '\nAssistant: ' +
        ASSISTANT_TEXT +
        '\n\nLatest user message:\nAnd now?',
      userBlock.get('text'),
      'The earlier turns should be labelled and the latest message last.'
    );
  }

  @IsTest
  static void testScenario3() {
    // [1] Build a request whose last message is two tool results, with a system prompt that must not be sent again
    AIProvider.Request request = new AIProvider.Request();
    request.systemPromptText = SYSTEM_PROMPT;
    request.session = new AIProvider.Session();
    request.session.id = 'sesn_1';
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
      new Map<String, Object>{
        'role' => 'assistant',
        'content' => new List<Object>()
      },
      new Map<String, Object>{
        'role' => 'user',
        'content' => new List<Object>{
          new Map<String, Object>{
            'type' => 'tool_result',
            'tool_use_id' => 'sevt_1',
            'content' => 'first'
          },
          new Map<String, Object>{
            'type' => 'tool_result',
            'tool_use_id' => 'sevt_2',
            'content' => 'second'
          }
        }
      }
    };

    Map<String, Object> body;

    // [2] Build the body
    Test.startTest();
    body = new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
    Test.stopTest();

    // [3] Read the events back
    List<Object> events = (List<Object>) body.get('events');
    Map<String, Object> secondEvent = (Map<String, Object>) events[1];
    Map<String, Object> secondBlock = (Map<String, Object>) ((List<Object>) secondEvent.get(
      'content'
    ))[0];

    // [4] Check one result event per call
    Assert.areEqual(
      2,
      events.size(),
      'There should be one event per tool result and no system message.'
    );
    Assert.areEqual(
      'user.custom_tool_result',
      secondEvent.get('type'),
      'Each result should be a custom tool result.'
    );
    Assert.areEqual(
      'sevt_2',
      secondEvent.get('custom_tool_use_id'),
      'Each result should name the call it answers.'
    );
    Assert.areEqual(
      'second',
      secondBlock.get('text'),
      'The result should be sent as text.'
    );
  }

  @IsTest
  static void testScenario4() {
    // [1] Prepare a request with no messages, one with no session, and one whose last message holds no tool results
    AIProvider.Request emptyRequest = new AIProvider.Request();
    emptyRequest.messages = new List<Map<String, Object>>();
    AIProvider.Request noSessionRequest = new AIProvider.Request();
    noSessionRequest.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT }
    };
    AIProvider.Request noResultsRequest = new AIProvider.Request();
    noResultsRequest.session = new AIProvider.Session();
    noResultsRequest.session.id = 'sesn_1';
    noResultsRequest.messages = new List<Map<String, Object>>{
      new Map<String, Object>{
        'role' => 'user',
        'content' => new List<Object>()
      }
    };
    List<String> errorMessages = new List<String>();

    // [2] Build each body
    Test.startTest();
    for (
      AIProvider.Request request : new List<AIProvider.Request>{
        emptyRequest,
        noSessionRequest,
        noResultsRequest
      }
    ) {
      try {
        new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
      } catch (AIAnthropicAgentRequestBuilder.AIAnthropicAgentRequestBuilderException ex) {
        errorMessages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    // [3] Check each was refused with its own message
    Assert.areEqual(
      3,
      errorMessages.size(),
      'All three requests should be refused.'
    );
    Assert.areEqual(
      'There is no message to send to the agent.',
      errorMessages[0],
      'An empty request should say there is nothing to send.'
    );
    Assert.isTrue(
      errorMessages[1].contains('no session'),
      'A request with no session should say so.'
    );
    Assert.areEqual(
      'The last message holds no tool results to send to the agent.',
      errorMessages[2],
      'A request with no tool results should say so.'
    );
  }

  @IsTest
  static void testScenario5() {
    // [1] Register the mock and build a request with an empty session
    SessionStartMock mock = new SessionStartMock();
    Test.setMock(HttpCalloutMock.class, mock);
    AIProvider.Request request = new AIProvider.Request();
    request.modelIdentifier = 'agent_1';
    request.environmentId = 'env_1';
    request.endpoint = SESSIONS_ENDPOINT;
    request.session = new AIProvider.Session();
    request.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT }
    };

    // [2] Build the body twice, as two passes of a turn would
    Test.startTest();
    new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
    new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
    Test.stopTest();

    // [3] Read what was sent to start the session
    Map<String, Object> startBody = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requestBody
    );
    Map<String, Object> agent = (Map<String, Object>) startBody.get('agent');

    // [4] Check the session was started once, for the agent and environment, and remembered
    Assert.areEqual(
      1,
      mock.callCount,
      'The second pass should reuse the session.'
    );
    Assert.areEqual(
      'agent_1',
      agent.get('id'),
      'The session should be for the agent.'
    );
    Assert.areEqual(
      'env_1',
      startBody.get('environment_id'),
      'The session should be in the environment.'
    );
    Assert.areEqual(
      'sesn_1',
      request.session.id,
      'The session id should be kept on the request.'
    );
    Assert.areEqual(
      SESSIONS_ENDPOINT + '/sesn_1/events',
      request.session.endpoint,
      'Events should go to the session.'
    );
    Assert.areEqual(
      'managed-agents-2026-04-01',
      request.session.headers.get('anthropic-beta'),
      'Events need the beta header.'
    );
  }

  @IsTest
  static void testScenario6() {
    // [1] Prepare a request with no environment, and one that Anthropic will refuse
    SessionStartMock mock = new SessionStartMock();
    mock.statusCode = 401;
    Test.setMock(HttpCalloutMock.class, mock);
    AIProvider.Request noEnvironmentRequest = new AIProvider.Request();
    noEnvironmentRequest.modelIdentifier = 'agent_1';
    noEnvironmentRequest.endpoint = SESSIONS_ENDPOINT;
    noEnvironmentRequest.session = new AIProvider.Session();
    noEnvironmentRequest.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT }
    };
    AIProvider.Request refusedRequest = new AIProvider.Request();
    refusedRequest.modelIdentifier = 'agent_1';
    refusedRequest.environmentId = 'env_1';
    refusedRequest.endpoint = SESSIONS_ENDPOINT;
    refusedRequest.session = new AIProvider.Session();
    refusedRequest.messages = new List<Map<String, Object>>{
      new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT }
    };
    List<String> errorMessages = new List<String>();

    // [2] Build each body
    Test.startTest();
    for (
      AIProvider.Request request : new List<AIProvider.Request>{
        noEnvironmentRequest,
        refusedRequest
      }
    ) {
      try {
        new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
      } catch (AIAnthropicAgentRequestBuilder.AIAnthropicAgentRequestBuilderException ex) {
        errorMessages.add(ex.getMessage());
      }
    }
    Test.stopTest();

    // [3] Check both were refused, and only the second reached Anthropic
    Assert.areEqual(
      2,
      errorMessages.size(),
      'Both requests should be refused.'
    );
    Assert.isTrue(
      errorMessages[0].contains('both needed'),
      'A missing id should say both are needed.'
    );
    Assert.isTrue(
      errorMessages[1].contains('HTTP 401') &&
      errorMessages[1].contains('authentication_error'),
      'A refusal should carry the status and Anthropic\'s own error.'
    );
    Assert.areEqual(
      1,
      mock.callCount,
      'Only the request with both ids should call Anthropic.'
    );
    Assert.isNull(
      refusedRequest.session.id,
      'A refused session should leave the session empty.'
    );
  }
}
