/*
Class Name: AIAssistTestProviderMock

=================================================================
=================================================================

Description: Testing utility that stands in for the AI provider's HTTP endpoint, so tests drive the real AI Agent Manager.

Step 1: A test calls install with the kind of provider behaviour it needs
Step 2: install makes the callout settings valid and registers this mock
Step 3: Every callout is answered in the Anthropic reply shape, or with a failure status, and counted. The agent kind answers as the Anthropic Agent API instead: sessions, events and the lookup of a saved session

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
public without sharing class AIAssistTestProviderMock implements HttpCalloutMock {

    // answer: every call replies 'Fake reply'. echo: replies with the number of messages sent and the last one's text. fail: every call is refused with a non-retryable status. retry: the first call is a retryable failure, later calls reply 'Fake reply'.
    public static final String KIND_ANSWER = 'answer';
    public static final String KIND_ECHO = 'echo';
    public static final String KIND_FAIL = 'fail';
    public static final String KIND_RETRY = 'retry';
    public static final String KIND_AGENT = 'agent'; // The Anthropic Agent API: starting a session gives sesn_fresh, the session sesn_saved is found and idle, any other saved session is not found, and the agent replies 'Fake reply'.

    public static final String REPLY_TEXT = 'Fake reply';
    public static final String SESSION_ID_NEW = 'sesn_fresh';
    public static final String SESSION_ID_SAVED = 'sesn_saved';

    public static Integer callCount = 0;

    private String kind;

    private AIAssistTestProviderMock(String kind) {

        // [1] Remember which behaviour this mock plays
        this.kind = kind;
    }

    // Makes the callout settings valid, then registers the mock. Call it before Test.startTest.
    public static void install(String kind) {

        // [1] Start the call count again
        callCount = 0;

        // [2] Make the callout settings valid and clear the cached copy
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.CalloutTimeoutMilliseconds__c = 30000;
        settings.RetryableStatusCodes__c = '503';
        upsert settings;
        AIAssistSettingsService.cachedSettings = null;

        // [3] Register the mock for the callouts
        Test.setMock(HttpCalloutMock.class, new AIAssistTestProviderMock(kind));
    }

    // Answers a callout according to the kind of mock.
    public HttpResponse respond(HttpRequest request) {

        // [1] Count the call
        callCount++;

        HttpResponse httpResponse = new HttpResponse();

        // [2] Answer as the Anthropic Agent API when playing that kind
        if (kind == KIND_AGENT) return buildAgentResponse(request);

        // [3] Refuse every call with a status that is never retried
        if (kind == KIND_FAIL) {

            httpResponse.setStatusCode(400);
            httpResponse.setBody('Provider said no');
            return httpResponse;
        }

        // [4] Fail the first call with a status that is retried
        if (kind == KIND_RETRY && callCount == 1) {

            httpResponse.setStatusCode(503);
            httpResponse.setBody('Unavailable');
            return httpResponse;
        }

        // [5] Reply with the fixed text, or with a summary of the request when echoing
        httpResponse.setStatusCode(200);
        httpResponse.setBody(buildAnthropicReply(kind == KIND_ECHO ? buildEchoText(request) : REPLY_TEXT));

        return httpResponse;
    }

    // Answers a call to the Anthropic Agent API by what it asks for: a new session, events sent to a session, the events of a session, or the lookup of a saved session.
    private static HttpResponse buildAgentResponse(HttpRequest request) {

        HttpResponse httpResponse = new HttpResponse();
        httpResponse.setStatusCode(200);

        String endpoint = request.getEndpoint();
        Boolean isPost = request.getMethod() == 'POST';

        // [1] Starting a session gives a new id
        if (isPost && endpoint.endsWith('/v1/sessions')) {

            httpResponse.setBody('{"id":"' + SESSION_ID_NEW + '"}');

            return httpResponse;
        }

        // [2] Sending events to a session is accepted
        if (isPost && endpoint.endsWith('/events')) {

            httpResponse.setBody('{}');

            return httpResponse;
        }

        // [3] Reading a session's events gives the question and the agent's reply
        if (endpoint.endsWith('/events')) {

            httpResponse.setBody('{"data":[{"type":"user.message"},{"type":"agent.message","content":[{"type":"text","text":"' + REPLY_TEXT + '"}]},{"type":"span.model_request_end","model_usage":{"input_tokens":10,"output_tokens":5}},{"type":"session.status_idle","stop_reason":{"type":"end_turn"}}]}');

            return httpResponse;
        }

        // [4] Looking up the saved session finds it
        if (endpoint.endsWith('/' + SESSION_ID_SAVED)) {

            httpResponse.setBody('{"id":"' + SESSION_ID_SAVED + '","status":"idle","archived_at":null,"agent":{"type":"agent","id":"test-model"},"environment_id":"env_1"}');

            return httpResponse;
        }

        // [5] Any other saved session is not found
        httpResponse.setStatusCode(404);
        httpResponse.setBody('{"error":{"type":"not_found_error","message":"session not found"}}');

        return httpResponse;
    }

    // Wraps the text in the shape of an Anthropic reply.
    private static String buildAnthropicReply(String text) {

        // [1] Return the reply with fixed token counts
        return '{"content":[{"type":"text","text":' + JSON.serialize(text) + '}],"usage":{"input_tokens":10,"output_tokens":5}}';
    }

    // The number of messages in the request and the text of the last one.
    private static String buildEchoText(HttpRequest request) {

        // [1] Read the messages out of the request
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
        List<Object> messages = (List<Object>) body.get('messages');
        Map<String, Object> lastMessage = (Map<String, Object>) messages[messages.size() - 1];

        // [2] Return the count and the last message text
        return messages.size() + '|' + lastMessage.get('content');
    }
}
