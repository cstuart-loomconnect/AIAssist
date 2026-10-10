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

@IsTest private class AIAnthropicAgentRequestBuilderTest {

    // testScenario1: Building a single user message with a system prompt -> a system message event then a user message event holding the text as it is.
    // testScenario2: Building a conversation with earlier messages -> the user message event holds the earlier turns labelled by speaker, then the latest message.
    // testScenario3: Building when the last message holds tool results -> one custom tool result event per result, each naming the call it answers, and no system prompt.
    // testScenario4: Building with no messages, no session on the request, or a last message with no tool results -> the adapter's own exception is thrown.
    // testScenario5: Building when the session has no id yet -> a session is started for the agent and environment, and the request's session then holds its id, its events endpoint and the beta header.
    // testScenario6: Building when the agent or environment id is missing, or Anthropic refuses the session -> the adapter's own exception says why, with no events built.
    // testScenario7: Building with a saved session that Anthropic still has open for the same agent and environment -> no new session is started, the saved one is used, and only the latest message is sent.
    // testScenario8: Building with a saved session Anthropic cannot find -> a new session is started and the earlier conversation is written into the message.
    // testScenario9: Building with a saved session that has ended or been archived -> a new session is started and the earlier conversation is written into the message.
    // testScenario10: Building with a saved session that belongs to another agent or environment -> a new session is started and the earlier conversation is written into the message.

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
            httpResponse.setBody(statusCode == 200 ? '{"id":"sesn_1"}' : '{"error":{"type":"authentication_error","message":"bad key"}}');

            return httpResponse;
        }
    }

    // Plays Anthropic for a saved session: the lookup of the saved session answers with the given status and body, and starting a session gives sesn_new.
    private class SavedSessionMock implements HttpCalloutMock {
        public Integer lookupStatusCode = 200;
        public String lookupBody;
        public List<String> requestLines = new List<String>();

        public HttpResponse respond(HttpRequest request) {
            requestLines.add(request.getMethod() + ' ' + request.getEndpoint());

            HttpResponse httpResponse = new HttpResponse();

            if (request.getMethod() == 'GET') {
                httpResponse.setStatusCode(lookupStatusCode);
                httpResponse.setBody(lookupBody);
            } else {
                httpResponse.setStatusCode(200);
                httpResponse.setBody('{"id":"sesn_new"}');
            }

            return httpResponse;
        }
    }

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) userEvent.get('content'))[0];

            // [4] Check the events
            Assert.areEqual(2, events.size(), 'There should be a system event and a user event.');
            Assert.areEqual('system.message', systemEvent.get('type'), 'The system prompt should go first as a system message.');
            Assert.areEqual('user.message', userEvent.get('type'), 'The user text should be a user message.');
            Assert.areEqual(USER_TEXT, userBlock.get('text'), 'A single message should be sent as it is.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) events[0]).get('content'))[0];

            // [4] Check the earlier turns are written out above the latest message
            Assert.areEqual(1, events.size(), 'With no system prompt there should be one event.');
            Assert.areEqual('Conversation so far:\nUser: ' + USER_TEXT + '\nAssistant: ' + ASSISTANT_TEXT + '\n\nLatest user message:\nAnd now?', userBlock.get('text'), 'The earlier turns should be labelled and the latest message last.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            Map<String, Object> secondBlock = (Map<String, Object>) ((List<Object>) secondEvent.get('content'))[0];

            // [4] Check one result event per call
            Assert.areEqual(2, events.size(), 'There should be one event per tool result and no system message.');
            Assert.areEqual('user.custom_tool_result', secondEvent.get('type'), 'Each result should be a custom tool result.');
            Assert.areEqual('sevt_2', secondEvent.get('custom_tool_use_id'), 'Each result should name the call it answers.');
            Assert.areEqual('second', secondBlock.get('text'), 'The result should be sent as text.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
                for (AIProvider.Request request : new List<AIProvider.Request>{ emptyRequest, noSessionRequest, noResultsRequest }) {
                    try {
                        new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
                    } catch (AIAnthropicAgentRequestBuilder.AIAnthropicAgentRequestBuilderException ex) {
                        errorMessages.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check each was refused with its own message
            Assert.areEqual(3, errorMessages.size(), 'All three requests should be refused.');
            Assert.areEqual('There is no message to send to the agent.', errorMessages[0], 'An empty request should say there is nothing to send.');
            Assert.isTrue(errorMessages[1].contains('no session'), 'A request with no session should say so.');
            Assert.areEqual('The last message holds no tool results to send to the agent.', errorMessages[2], 'A request with no tool results should say so.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
            Map<String, Object> startBody = (Map<String, Object>) JSON.deserializeUntyped(mock.requestBody);
            Map<String, Object> agent = (Map<String, Object>) startBody.get('agent');

            // [4] Check the session was started once, for the agent and environment, and remembered
            Assert.areEqual(1, mock.callCount, 'The second pass should reuse the session.');
            Assert.areEqual('agent_1', agent.get('id'), 'The session should be for the agent.');
            Assert.areEqual('env_1', startBody.get('environment_id'), 'The session should be in the environment.');
            Assert.areEqual('sesn_1', request.session.id, 'The session id should be kept on the request.');
            Assert.areEqual(SESSIONS_ENDPOINT + '/sesn_1/events', request.session.endpoint, 'Events should go to the session.');
            Assert.areEqual('managed-agents-2026-04-01', request.session.headers.get('anthropic-beta'), 'Events need the beta header.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
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
                for (AIProvider.Request request : new List<AIProvider.Request>{ noEnvironmentRequest, refusedRequest }) {
                    try {
                        new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
                    } catch (AIAnthropicAgentRequestBuilder.AIAnthropicAgentRequestBuilderException ex) {
                        errorMessages.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check both were refused, and only the second reached Anthropic
            Assert.areEqual(2, errorMessages.size(), 'Both requests should be refused.');
            Assert.isTrue(errorMessages[0].contains('both needed'), 'A missing id should say both are needed.');
            Assert.isTrue(errorMessages[1].contains('HTTP 401') && errorMessages[1].contains('authentication_error'), 'A refusal should carry the status and Anthropic\'s own error.');
            Assert.areEqual(1, mock.callCount, 'Only the request with both ids should call Anthropic.');
            Assert.isNull(refusedRequest.session.id, 'A refused session should leave the session empty.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register a mock where the saved session is idle and belongs to the same agent and environment
            SavedSessionMock mock = new SavedSessionMock();
            mock.lookupBody = '{"id":"sesn_saved","status":"idle","archived_at":null,"agent":{"type":"agent","id":"agent_1"},"environment_id":"env_1"}';
            Test.setMock(HttpCalloutMock.class, mock);

            AIProvider.Request request = new AIProvider.Request();
            request.modelIdentifier = 'agent_1';
            request.environmentId = 'env_1';
            request.endpoint = SESSIONS_ENDPOINT;
            request.session = new AIProvider.Session();
            request.session.resumeId = 'sesn_saved';
            request.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
                new Map<String, Object>{ 'role' => 'assistant', 'content' => ASSISTANT_TEXT },
                new Map<String, Object>{ 'role' => 'user', 'content' => 'And now?' }
            };

            Map<String, Object> body;

            // [2] Build the body
            Test.startTest();
                body = new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
            Test.stopTest();

            // [3] Read the text of the only event
            List<Object> events = (List<Object>) body.get('events');
            Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) events[0]).get('content'))[0];

            // [4] Check the saved session was continued and the history was not sent again
            Assert.areEqual(1, mock.requestLines.size(), 'Only the lookup of the saved session should reach Anthropic.');
            Assert.areEqual('GET ' + SESSIONS_ENDPOINT + '/sesn_saved', mock.requestLines[0], 'The saved session should be looked up by its id.');
            Assert.areEqual('sesn_saved', request.session.id, 'The saved session should be the one in use.');
            Assert.isTrue(request.session.isResumed, 'The session should be marked as continued.');
            Assert.areEqual(SESSIONS_ENDPOINT + '/sesn_saved/events', request.session.endpoint, 'Events should go to the saved session.');
            Assert.areEqual('managed-agents-2026-04-01', request.session.headers.get('anthropic-beta'), 'Events need the beta header.');
            Assert.areEqual('And now?', userBlock.get('text'), 'Only the latest message should be sent, because the session already holds the rest.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register a mock where Anthropic cannot find the saved session
            SavedSessionMock mock = new SavedSessionMock();
            mock.lookupStatusCode = 404;
            mock.lookupBody = '{"error":{"type":"not_found_error","message":"session not found"}}';
            Test.setMock(HttpCalloutMock.class, mock);

            AIProvider.Request request = new AIProvider.Request();
            request.modelIdentifier = 'agent_1';
            request.environmentId = 'env_1';
            request.endpoint = SESSIONS_ENDPOINT;
            request.session = new AIProvider.Session();
            request.session.resumeId = 'sesn_saved';
            request.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
                new Map<String, Object>{ 'role' => 'assistant', 'content' => ASSISTANT_TEXT },
                new Map<String, Object>{ 'role' => 'user', 'content' => 'And now?' }
            };

            Map<String, Object> body;

            // [2] Build the body
            Test.startTest();
                body = new AIAnthropicAgentRequestBuilder().buildRequestBody(request);
            Test.stopTest();

            // [3] Read the text of the only event
            List<Object> events = (List<Object>) body.get('events');
            Map<String, Object> userBlock = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) events[0]).get('content'))[0];

            // [4] Check a new session replaced it and the conversation was written into the message
            Assert.areEqual('POST ' + SESSIONS_ENDPOINT, mock.requestLines[1], 'A new session should be started after the lookup fails.');
            Assert.areEqual('sesn_new', request.session.id, 'The new session should be the one in use.');
            Assert.isFalse(request.session.isResumed, 'A new session is not a continued one.');
            Assert.areEqual('Conversation so far:\nUser: ' + USER_TEXT + '\nAssistant: ' + ASSISTANT_TEXT + '\n\nLatest user message:\nAnd now?', userBlock.get('text'), 'A new session should be given the earlier turns.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register a mock where the saved session has ended, and build a request that has earlier messages
            SavedSessionMock mock = new SavedSessionMock();
            mock.lookupBody = '{"id":"sesn_saved","status":"terminated","archived_at":null,"agent":{"type":"agent","id":"agent_1"},"environment_id":"env_1"}';
            Test.setMock(HttpCalloutMock.class, mock);

            AIProvider.Request endedRequest = new AIProvider.Request();
            endedRequest.modelIdentifier = 'agent_1';
            endedRequest.environmentId = 'env_1';
            endedRequest.endpoint = SESSIONS_ENDPOINT;
            endedRequest.session = new AIProvider.Session();
            endedRequest.session.resumeId = 'sesn_saved';
            endedRequest.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
                new Map<String, Object>{ 'role' => 'assistant', 'content' => ASSISTANT_TEXT },
                new Map<String, Object>{ 'role' => 'user', 'content' => 'And now?' }
            };

            // [2] Prepare a second request, for a saved session that is archived
            SavedSessionMock archivedMock = new SavedSessionMock();
            archivedMock.lookupBody = '{"id":"sesn_saved","status":"idle","archived_at":"2026-10-01T10:00:00Z","agent":{"type":"agent","id":"agent_1"},"environment_id":"env_1"}';

            AIProvider.Request archivedRequest = new AIProvider.Request();
            archivedRequest.modelIdentifier = 'agent_1';
            archivedRequest.environmentId = 'env_1';
            archivedRequest.endpoint = SESSIONS_ENDPOINT;
            archivedRequest.session = new AIProvider.Session();
            archivedRequest.session.resumeId = 'sesn_saved';
            archivedRequest.messages = endedRequest.messages;

            // [3] Build the body for each, switching the mock between them
            Test.startTest();
                new AIAnthropicAgentRequestBuilder().buildRequestBody(endedRequest);
                Test.setMock(HttpCalloutMock.class, archivedMock);
                new AIAnthropicAgentRequestBuilder().buildRequestBody(archivedRequest);
            Test.stopTest();

            // [4] Check a new session replaced each of them
            Assert.areEqual('sesn_new', endedRequest.session.id, 'An ended session should be replaced.');
            Assert.isFalse(endedRequest.session.isResumed, 'An ended session should not be continued.');
            Assert.areEqual('sesn_new', archivedRequest.session.id, 'An archived session should be replaced.');
            Assert.isFalse(archivedRequest.session.isResumed, 'An archived session should not be continued.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Register a mock where the saved session was made for another agent, and build a request that has earlier messages
            SavedSessionMock mock = new SavedSessionMock();
            mock.lookupBody = '{"id":"sesn_saved","status":"idle","archived_at":null,"agent":{"type":"agent","id":"agent_other"},"environment_id":"env_1"}';
            Test.setMock(HttpCalloutMock.class, mock);

            AIProvider.Request otherAgentRequest = new AIProvider.Request();
            otherAgentRequest.modelIdentifier = 'agent_1';
            otherAgentRequest.environmentId = 'env_1';
            otherAgentRequest.endpoint = SESSIONS_ENDPOINT;
            otherAgentRequest.session = new AIProvider.Session();
            otherAgentRequest.session.resumeId = 'sesn_saved';
            otherAgentRequest.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => USER_TEXT },
                new Map<String, Object>{ 'role' => 'assistant', 'content' => ASSISTANT_TEXT },
                new Map<String, Object>{ 'role' => 'user', 'content' => 'And now?' }
            };

            // [2] Prepare a second request, for a saved session in another environment
            SavedSessionMock otherEnvironmentMock = new SavedSessionMock();
            otherEnvironmentMock.lookupBody = '{"id":"sesn_saved","status":"idle","archived_at":null,"agent":{"type":"agent","id":"agent_1"},"environment_id":"env_other"}';

            AIProvider.Request otherEnvironmentRequest = new AIProvider.Request();
            otherEnvironmentRequest.modelIdentifier = 'agent_1';
            otherEnvironmentRequest.environmentId = 'env_1';
            otherEnvironmentRequest.endpoint = SESSIONS_ENDPOINT;
            otherEnvironmentRequest.session = new AIProvider.Session();
            otherEnvironmentRequest.session.resumeId = 'sesn_saved';
            otherEnvironmentRequest.messages = otherAgentRequest.messages;

            // [3] Build the body for each, switching the mock between them
            Test.startTest();
                new AIAnthropicAgentRequestBuilder().buildRequestBody(otherAgentRequest);
                Test.setMock(HttpCalloutMock.class, otherEnvironmentMock);
                new AIAnthropicAgentRequestBuilder().buildRequestBody(otherEnvironmentRequest);
            Test.stopTest();

            // [4] Check a new session replaced each of them
            Assert.areEqual('sesn_new', otherAgentRequest.session.id, 'A session made for another agent should be replaced.');
            Assert.isFalse(otherAgentRequest.session.isResumed, 'A session made for another agent should not be continued.');
            Assert.areEqual('sesn_new', otherEnvironmentRequest.session.id, 'A session in another environment should be replaced.');
            Assert.isFalse(otherEnvironmentRequest.session.isResumed, 'A session in another environment should not be continued.');
        }
    }
}
