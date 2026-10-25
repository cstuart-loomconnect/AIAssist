/*
Class Name: AIOpenAiResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiResponseHandler: the OpenAI response becomes the canonical response, and the conversation sent back is shaped the way OpenAI expects.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiResponseHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIOpenAiResponseHandlerTest {

    // testScenario1: Handling a text reply -> the reply text is returned, prompt and completion tokens are split, and the assistant message is appended as returned.
    // testScenario2: Handling a reply with tool calls and null content -> tool calls keep their id and name, the JSON argument string is deserialised (blank means none), and the text is blank.
    // testScenario3: Handling tool results from the previous pass with no response -> one tool-role message per call is added, each keyed by its tool_call_id, and null is returned.
    // testScenario4: Handling a different number of tool results than tool calls -> the adapter's own exception is thrown.
    // testScenario5: Handling a failure status, a response with no choices and a choice with no message -> an exception is thrown with the provider's own error, the raw body, or a message saying what is missing.
    // testScenario6: Handling a body that is not valid JSON -> the adapter's own exception is thrown with the original as its cause.

    private static final String ROLE_TOOL = 'tool';
    private static final String TOOL_NAME = 'lookup';
    private static final String TEXT_RESPONSE_BODY = '{"choices":[{"message":{"role":"assistant","content":"Hello"}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}';
    private static final String TOOL_RESPONSE_BODY = '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"lookup","arguments":"{\\"q\\":\\"x\\"}"}},{"id":"c2","type":"function","function":{"name":"other","arguments":""}}]}}],"usage":{"total_tokens":9}}';
    private static final String JSON_ERROR_BODY = '{"error":{"type":"rate_limit_exceeded","message":"Slow down"}}';
    private static final String RAW_ERROR_BODY = 'Server error';
    private static final String NO_CHOICES_BODY = '{"choices":[]}';
    private static final String NO_MESSAGE_BODY = '{"choices":[{"index":0}]}';
    private static final String MALFORMED_BODY = 'not json';
    private static final String WRAPPED_ERROR_PREFIX = 'Failed to handle the OpenAI response';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an empty conversation and a text response
            List<Map<String, Object>> messages = new List<Map<String, Object>>();

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(TEXT_RESPONSE_BODY);

            AIProvider.Response result;

            // [2] Handle the response
            Test.startTest();
                result = new AIOpenAiResponseHandler().handleResponse(messages, response, null, null, null);
            Test.stopTest();

            // [3] Check the text, tokens and appended assistant message
            Assert.areEqual('Hello', result.textContent, 'The reply text should be returned.');
            Assert.areEqual(10, result.inputTokens, 'The prompt tokens should be the input.');
            Assert.areEqual(5, result.outputTokens, 'The completion tokens should be the output.');

            Assert.areEqual(15, result.totalTokens, 'The total should be the one OpenAI reports.');
            Assert.areEqual(1, messages.size(), 'The assistant message should be appended to the conversation.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an empty conversation and a response with tool calls and null content
            List<Map<String, Object>> messages = new List<Map<String, Object>>();

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(TOOL_RESPONSE_BODY);

            AIProvider.Response result;

            // [2] Handle the response
            Test.startTest();
                result = new AIOpenAiResponseHandler().handleResponse(messages, response, null, null, null);
            Test.stopTest();

            // [3] Check the tool calls, blank text and token counts
            Assert.areEqual(2, result.toolCalls.size(), 'Both tool calls should be returned.');
            Assert.areEqual('c1', result.toolCalls[0].id, 'The id should be kept so the result can be paired.');
            Assert.areEqual(TOOL_NAME, result.toolCalls[0].name, 'The tool name should be kept.');
            Assert.areEqual('x', result.toolCalls[0].arguments.get('q'), 'The argument string should be deserialised.');
            Assert.isTrue(result.toolCalls[1].arguments.isEmpty(), 'A blank argument string should mean no arguments.');

            Assert.areEqual('', result.textContent, 'Null content should become blank text.');

            Assert.areEqual(9, result.totalTokens, 'The total tokens should be read from usage.');
            Assert.areEqual(0, result.inputTokens, 'With no prompt tokens reported the input should be zero.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an empty conversation, two tool calls and their results
            List<Map<String, Object>> messages = new List<Map<String, Object>>();

            AIProvider.ToolCall firstCall = new AIProvider.ToolCall();
            firstCall.id = 'c1';
            firstCall.name = TOOL_NAME;
            firstCall.arguments = new Map<String, Object>();

            AIProvider.ToolCall secondCall = new AIProvider.ToolCall();
            secondCall.id = 'c2';
            secondCall.name = TOOL_NAME;
            secondCall.arguments = new Map<String, Object>();

            List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{
                firstCall,
                secondCall
            };
            List<Object> toolResults = new List<Object>{
                'first',
                'second'
            };

            AIProvider.Response result;

            // [2] Handle the tool results with no response
            Test.startTest();
                result = new AIOpenAiResponseHandler().handleResponse(messages, null, calls, toolResults, null);
            Test.stopTest();

            // [3] Check one tool message was added per call
            Assert.isNull(result, 'With no response there should be nothing to parse.');

            Assert.areEqual(2, messages.size(), 'OpenAI wants a message per tool call, not one batch.');
            Assert.areEqual(ROLE_TOOL, messages[0].get('role'), 'Each message should have the tool role.');
            Assert.areEqual('c2', messages[1].get('tool_call_id'), 'Each message should name the call it answers.');
            Assert.areEqual('second', messages[1].get('content'), 'Each message should carry its result.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build one tool call and prepare to catch the adapter exception
            AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
            toolCall.id = 'c1';
            toolCall.name = TOOL_NAME;
            toolCall.arguments = new Map<String, Object>();

            List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{ toolCall };

            AIOpenAiResponseHandler.AIOpenAiResponseHandlerException thrownException;

            // [2] Handle one tool call with null tool results
            Test.startTest();
                try {

                    new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), null, calls, null, null);

                } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {

                    thrownException = ex;
                }
            Test.stopTest();

            // [3] Check the mismatch was refused
            Assert.isNotNull(thrownException, 'A result count mismatch should throw the adapter exception.');
            Assert.isTrue(thrownException.getMessage().contains('does not match'), 'The error should say the counts differ.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a JSON error, a raw error, a no-choices and a no-message response
            HttpResponse jsonErrorResponse = new HttpResponse();
            jsonErrorResponse.setStatusCode(429);
            jsonErrorResponse.setBody(JSON_ERROR_BODY);

            HttpResponse rawErrorResponse = new HttpResponse();
            rawErrorResponse.setStatusCode(500);
            rawErrorResponse.setBody(RAW_ERROR_BODY);

            HttpResponse noChoicesResponse = new HttpResponse();
            noChoicesResponse.setStatusCode(200);
            noChoicesResponse.setBody(NO_CHOICES_BODY);

            HttpResponse noMessageResponse = new HttpResponse();
            noMessageResponse.setStatusCode(200);
            noMessageResponse.setBody(NO_MESSAGE_BODY);

            List<HttpResponse> failedResponses = new List<HttpResponse>{
                jsonErrorResponse,
                rawErrorResponse,
                noChoicesResponse,
                noMessageResponse
            };
            List<String> errorMessages = new List<String>();

            // [2] Handle each failed response
            Test.startTest();
                for (HttpResponse response : failedResponses) {

                    try {

                        new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), response, null, null, null);

                    } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {

                        errorMessages.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check each failure threw with the right message
            Assert.areEqual(4, errorMessages.size(), 'Every one of these responses should throw.');

            Assert.areEqual('AI provider returned HTTP 429: rate_limit_exceeded - Slow down', errorMessages[0], 'The provider\'s error type and message should be used.');
            Assert.areEqual('AI provider returned HTTP 500: Server error', errorMessages[1], 'The raw body should be used when it is not JSON.');

            Assert.isTrue(errorMessages[2].contains('no choices'), 'A response with no choices should be refused.');
            Assert.isTrue(errorMessages[3].contains('no message'), 'A choice with no message should be refused.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a malformed response and prepare to catch the adapter exception
            HttpResponse malformed = new HttpResponse();
            malformed.setStatusCode(200);
            malformed.setBody(MALFORMED_BODY);

            AIOpenAiResponseHandler.AIOpenAiResponseHandlerException thrownException;

            // [2] Handle the malformed response
            Test.startTest();
                try {

                    new AIOpenAiResponseHandler().handleResponse(new List<Map<String, Object>>(), malformed, null, null, null);

                } catch (AIOpenAiResponseHandler.AIOpenAiResponseHandlerException ex) {

                    thrownException = ex;
                }
            Test.stopTest();

            // [3] Check the adapter exception was thrown with the original as its cause
            Assert.isNotNull(thrownException, 'A malformed body should throw the adapter exception.');
            Assert.isTrue(thrownException.getMessage().startsWith(WRAPPED_ERROR_PREFIX), 'The error should name the adapter.');
            Assert.isNotNull(thrownException.getCause(), 'The original error should be kept as the cause.');
        }
    }
}
