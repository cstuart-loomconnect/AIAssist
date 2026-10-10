/*
Class Name: AIAnthropicAgentResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicAgentResponseHandler: the events of an Anthropic Agent API session become the canonical response, and the conversation is shaped the way the request builder expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicAgentResponseHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAnthropicAgentResponseHandlerTest {

    // testScenario1: Handling a reply with agent messages and model usage -> the text is joined, input includes cached tokens, and the assistant's blocks are appended to the conversation.
    // testScenario2: Handling a reply with custom tool use events -> tool calls take the event id, name and input, and a missing input becomes an empty map.
    // testScenario3: Handling tool results from the previous pass with no response -> they are batched into one user message with a tool_result per call, and null is returned.
    // testScenario4: Handling a different number of tool results than tool calls -> the adapter's own exception is thrown.
    // testScenario5: Handling a failed status, an error event, an ended session and an approval wait -> each throws the adapter's own exception saying why.
    // testScenario6: Handling a successful status when the event list is not valid JSON -> the adapter's own exception wraps the failure.
    // testScenario7: Handling when the event list shows the agent still running -> it is fetched again, and an old idle from an earlier request is ignored.
    // testScenario8: Handling when the agent never settles, or the request has no session -> an interrupt is sent, and the adapter's own exception says why.

    private static final String TEXT_EVENTS = '[{"type":"agent.message","id":"e1","content":[{"type":"text","text":"Hello"},{"type":"text","text":"there"}]},{"type":"span.model_request_end","model_usage":{"input_tokens":10,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":5}},{"type":"session.status_idle","stop_reason":{"type":"end_turn"}}]';
    private static final String TOOL_EVENTS = '[{"type":"agent.custom_tool_use","id":"sevt_1","name":"lookup","input":{"q":"x"}},{"type":"agent.custom_tool_use","id":"sevt_2","name":"other"},{"type":"session.status_idle","stop_reason":{"type":"requires_action","event_ids":["sevt_1","sevt_2"]}}]';
    private static final String ERROR_EVENTS = '[{"type":"session.error","error":{"type":"overloaded_error","message":"Try later"}},{"type":"session.status_idle"}]';
    private static final String TERMINATED_EVENTS = '[{"type":"session.status_terminated"}]';
    private static final String APPROVAL_EVENTS = '[{"type":"agent.tool_use","id":"e1","name":"bash"},{"type":"session.status_idle","stop_reason":{"type":"requires_action"}}]';
    private static final String SESSION_ENDPOINT = 'callout:Anthropic/v1/sessions/sesn_1/events';
    private static final String JSON_ERROR_BODY = '{"type":"error","error":{"type":"not_found_error","message":"agent not found"}}';

    // Plays the session's event list. The list starts with an old idle and the message that was sent, then the events given. When listsBeforeSettled is above 0, that many lists show only a running status first.
    private class EventListMock implements HttpCalloutMock {
        public String eventsJson;
        public Integer listsBeforeSettled = 0;
        public Integer listCount = 0;
        public Integer interruptCount = 0;
        public Integer statusCode = 200;
        public String errorBody;

        public HttpResponse respond(HttpRequest request) {
            HttpResponse httpResponse = new HttpResponse();
            httpResponse.setStatusCode(statusCode);

            if (request.getMethod() == 'POST') {
                if (request.getBody().contains('user.interrupt'))
                interruptCount++;

                httpResponse.setBody('{"data":[]}');

                return httpResponse;
            }

            listCount++;

            String sent = '{"type":"session.status_idle","stop_reason":{"type":"end_turn"}},{"type":"user.message"}';

            if (errorBody != null)
            httpResponse.setBody(errorBody);
            else
            httpResponse.setBody(listCount <= listsBeforeSettled ? '{"data":[' + sent + ',{"type":"session.status_running"}]}' : '{"data":[' + sent + ',' + eventsJson.substring(1) + '}');

            return httpResponse;
        }
    }

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Register a session that answers with two text blocks, usage and an idle status
        EventListMock mock = new EventListMock();
        mock.eventsJson = TEXT_EVENTS;
        Test.setMock(HttpCalloutMock.class, mock);
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"data":[]}');
        AIProvider.Request request = new AIProvider.Request();
        request.session = new AIProvider.Session();
        request.session.endpoint = SESSION_ENDPOINT;
        request.maxWaitMilliseconds = 60000;
        AIProvider.Response result;

        // [2] Handle it
        Test.startTest();
            result = new AIAnthropicAgentResponseHandler().handleResponse(messages, response, null, null, request);
        Test.stopTest();

        // [3] Read the appended assistant message
        List<Object> blocks = (List<Object>) messages[0].get('content');

        // [4] Check the answer, the tokens and the conversation
        Assert.areEqual('Hello\nthere', result.textContent, 'The text blocks should be joined.');
        Assert.areEqual(15, result.inputTokens, 'Input should include the cache creation and cache read tokens.');
        Assert.areEqual(5, result.outputTokens, 'Output tokens should be read from the model usage.');
        Assert.areEqual(20, result.totalTokens, 'Total should be input plus output.');
        Assert.isTrue(result.toolCalls.isEmpty(), 'A plain reply asks for no tools.');
        Assert.areEqual('assistant', messages[0].get('role'), 'The reply should be appended as the assistant.');
        Assert.areEqual(2, blocks.size(), 'Both text blocks should be kept.');
    }

    @IsTest static void testScenario2() {

        // [1] Register a session that answers with two custom tool calls, the second with no input
        EventListMock mock = new EventListMock();
        mock.eventsJson = TOOL_EVENTS;
        Test.setMock(HttpCalloutMock.class, mock);
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"data":[]}');
        AIProvider.Request request = new AIProvider.Request();
        request.session = new AIProvider.Session();
        request.session.endpoint = SESSION_ENDPOINT;
        request.maxWaitMilliseconds = 60000;
        AIProvider.Response result;

        // [2] Handle it
        Test.startTest();
            result = new AIAnthropicAgentResponseHandler().handleResponse(messages, response, null, null, request);
        Test.stopTest();

        // [3] Check the tool calls and the conversation
        Assert.areEqual(2, result.toolCalls.size(), 'Both tool calls should be read.');
        Assert.areEqual('sevt_1', result.toolCalls[0].id, 'The event id is what the result must name.');
        Assert.areEqual('lookup', result.toolCalls[0].name, 'The tool name should be read.');
        Assert.areEqual('x', result.toolCalls[0].arguments.get('q'), 'The input should be read.');
        Assert.isTrue(result.toolCalls[1].arguments.isEmpty(), 'A missing input should become an empty map.');
        Assert.areEqual('', result.textContent, 'There is no text when the agent only called tools.');
        Assert.areEqual(2, ((List<Object>) messages[0].get('content')).size(), 'Both calls should be kept on the assistant message.');
    }

    @IsTest static void testScenario3() {

        // [1] Build two tool calls and their results
        List<Map<String, Object>> messages = new List<Map<String, Object>>();
        AIProvider.ToolCall firstCall = new AIProvider.ToolCall();
        firstCall.id = 'sevt_1';
        AIProvider.ToolCall secondCall = new AIProvider.ToolCall();
        secondCall.id = 'sevt_2';
        List<Object> toolResults = new List<Object>{
            'first result',
            new List<Object>{ 'a' }
        };
        AIProvider.Response result;

        // [2] Handle the results with no response
        Test.startTest();
            result = new AIAnthropicAgentResponseHandler().handleResponse(messages, null, new List<AIProvider.ToolCall>{ firstCall, secondCall }, toolResults, null);
        Test.stopTest();

        // [3] Read the blocks back
        List<Object> blocks = (List<Object>) messages[0].get('content');
        Map<String, Object> secondBlock = (Map<String, Object>) blocks[1];

        // [4] Check the results were batched into one user message
        Assert.isNull(result, 'With no response there should be nothing to parse.');
        Assert.areEqual(1, messages.size(), 'Every result should go in one message.');
        Assert.areEqual('user', messages[0].get('role'), 'Results should come back as a user message.');
        Assert.areEqual('sevt_2', secondBlock.get('tool_use_id'), 'Each result should name the call it answers.');
        Assert.areEqual('["a"]', secondBlock.get('content'), 'A non-text result should be serialised.');
    }

    @IsTest static void testScenario4() {

        // [1] Build one tool call with no result
        AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
        toolCall.id = 'sevt_1';
        AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException thrownException;

        // [2] Handle it
        Test.startTest();
            try {
                new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), null, new List<AIProvider.ToolCall>{ toolCall }, new List<Object>(), null);
            } catch (AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException ex) {
                thrownException = ex;
            }
        Test.stopTest();

        // [3] Check the mismatch was refused
        Assert.isNotNull(thrownException, 'A result count mismatch should throw the adapter exception.');
        Assert.isTrue(thrownException.getMessage().contains('does not match'), 'The error should say the counts differ.');
    }

    @IsTest static void testScenario5() {

        // [1] Build a failed send, and three event lists that cannot give an answer
        HttpResponse failedSend = new HttpResponse();
        failedSend.setStatusCode(404);
        failedSend.setBody(JSON_ERROR_BODY);
        List<String> errorMessages = new List<String>();
        List<String> eventLists = new List<String>{
            ERROR_EVENTS,
            TERMINATED_EVENTS,
            APPROVAL_EVENTS
        };

        // [2] Handle the failed send, then each event list
        Test.startTest();
            try {
                new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), failedSend, null, null, null);
            } catch (AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException ex) {
                errorMessages.add(ex.getMessage());
            }

            for (String eventList : eventLists) {
                EventListMock mock = new EventListMock();
                mock.eventsJson = eventList;
                Test.setMock(HttpCalloutMock.class, mock);

                HttpResponse sent = new HttpResponse();
                sent.setStatusCode(200);
                sent.setBody('{"data":[]}');
                AIProvider.Request request = new AIProvider.Request();
                request.session = new AIProvider.Session();
                request.session.endpoint = SESSION_ENDPOINT;
                request.maxWaitMilliseconds = 60000;

                try {
                    new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), sent, null, null, request);
                } catch (AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException ex) {
                    errorMessages.add(ex.getMessage());
                }
            }
        Test.stopTest();

        // [3] Check each threw with its own message
        Assert.areEqual(4, errorMessages.size(), 'All four should throw.');
        Assert.areEqual('AI provider returned HTTP 404: not_found_error - agent not found', errorMessages[0], 'The provider\'s error type and message should be used.');
        Assert.isTrue(errorMessages[1].contains('overloaded_error - Try later'), 'An error event should report its own message.');
        Assert.areEqual('The agent session ended before it answered.', errorMessages[2], 'An ended session should say so.');
        Assert.isTrue(errorMessages[3].contains('always_allow'), 'An approval wait should say what to change.');
    }

    @IsTest static void testScenario6() {

        // [1] Register a session whose event list is not JSON
        EventListMock mock = new EventListMock();
        mock.errorBody = 'not json at all';
        Test.setMock(HttpCalloutMock.class, mock);
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"data":[]}');
        AIProvider.Request request = new AIProvider.Request();
        request.session = new AIProvider.Session();
        request.session.endpoint = SESSION_ENDPOINT;
        request.maxWaitMilliseconds = 60000;
        AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException thrownException;

        // [2] Handle it
        Test.startTest();
            try {
                new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), response, null, null, request);
            } catch (AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException ex) {
                thrownException = ex;
            }
        Test.stopTest();

        // [3] Check the failure was wrapped
        Assert.isNotNull(thrownException, 'A bad body should throw the adapter exception.');
        Assert.isTrue(thrownException.getMessage().startsWith('Failed to handle the Anthropic Agent response'), 'The failure should be wrapped with a clear message.');
    }

    @IsTest static void testScenario7() {

        // [1] Register a session that is still running for the first list, with an old idle before the message that was sent
        EventListMock mock = new EventListMock();
        mock.eventsJson = TEXT_EVENTS;
        mock.listsBeforeSettled = 1;
        Test.setMock(HttpCalloutMock.class, mock);
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"data":[]}');
        AIProvider.Request request = new AIProvider.Request();
        request.session = new AIProvider.Session();
        request.session.endpoint = SESSION_ENDPOINT;
        request.maxWaitMilliseconds = 60000;
        AIProvider.Response result;

        // [2] Handle it
        Test.startTest();
            result = new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), response, null, null, request);
        Test.stopTest();

        // [3] Check the list was fetched again and the answer came from the second
        Assert.areEqual(2, mock.listCount, 'The list should be fetched again while the agent is still running.');
        Assert.areEqual('Hello\nthere', result.textContent, 'The answer should be the one after the sent message.');
        Assert.areEqual(0, mock.interruptCount, 'An agent that settled should not be interrupted.');
    }

    @IsTest static void testScenario8() {

        // [1] Register a session, and prepare a request that allows no time and one with no session
        EventListMock mock = new EventListMock();
        mock.eventsJson = TEXT_EVENTS;
        Test.setMock(HttpCalloutMock.class, mock);
        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody('{"data":[]}');
        AIProvider.Request noTimeRequest = new AIProvider.Request();
        noTimeRequest.session = new AIProvider.Session();
        noTimeRequest.session.endpoint = SESSION_ENDPOINT;
        noTimeRequest.maxWaitMilliseconds = 0;
        List<String> errorMessages = new List<String>();

        // [2] Handle each
        Test.startTest();
            for (AIProvider.Request request : new List<AIProvider.Request>{ noTimeRequest, new AIProvider.Request() }) {
                try {
                    new AIAnthropicAgentResponseHandler().handleResponse(new List<Map<String, Object>>(), response, null, null, request);
                } catch (AIAnthropicAgentResponseHandler.AIAnthropicAgentResponseHandlerException ex) {
                    errorMessages.add(ex.getMessage());
                }
            }
        Test.stopTest();

        // [3] Check the agent was stopped, and both said why
        Assert.areEqual(2, errorMessages.size(), 'Both should throw.');
        Assert.isTrue(errorMessages[0].contains('did not finish'), 'Running out of time should say so.');
        Assert.areEqual(1, mock.interruptCount, 'The agent should be told to stop.');
        Assert.isTrue(errorMessages[1].contains('no agent session'), 'A request with no session should say so.');
    }
}
