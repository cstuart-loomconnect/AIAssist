/*
Class Name: AIAnthropicMessageResponseHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicMessageResponseHandler: the Anthropic response becomes the canonical response, and the conversation sent back is shaped the way Anthropic expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicMessageResponseHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAnthropicMessageResponseHandlerTest {

    // testScenario1: Handling a text reply -> the text blocks are joined, input and output tokens are split, and the assistant's content is appended to the conversation as returned.
    // testScenario2: Handling a reply with only tool_use blocks -> tool calls keep their id, name and arguments, missing arguments become an empty map, and there is no text.
    // testScenario3: Handling tool results from the previous pass with no response -> they are batched into one user message with a tool_result per call, and null is returned.
    // testScenario4: Handling a different number of tool results than tool calls -> the adapter's own exception is thrown, because Anthropic rejects a tool_use with no tool_result.
    // testScenario5: Handling a status outside the success codes -> an exception is thrown with the provider's own error, falling back to the raw body when it is not JSON.
    // testScenario6: Handling a status listed in the success codes setting, and a body that is not valid JSON -> the status is accepted, and the bad body throws the adapter's own exception.

    private static final String ROLE_ASSISTANT = 'assistant';
    private static final String ROLE_USER = 'user';
    private static final String TOOL_NAME = 'lookup';
    private static final String TEXT_RESPONSE_BODY = '{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"there"}],"usage":{"input_tokens":10,"output_tokens":5}}';
    private static final String TOOL_RESPONSE_BODY = '{"content":[{"type":"tool_use","id":"t1","name":"lookup","input":{"q":"x"}},{"type":"tool_use","id":"t2","name":"other"}],"usage":{"input_tokens":4,"output_tokens":2}}';
    private static final String JSON_ERROR_BODY = '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens is too large"}}';
    private static final String RAW_ERROR_BODY = 'Bad gateway';
    private static final String CREATED_RESPONSE_BODY = '{"content":[{"type":"text","text":"Created"}]}';
    private static final String MALFORMED_BODY = 'not json at all';
    private static final String WRAPPED_ERROR_PREFIX = 'Failed to handle the Anthropic response';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Build an empty conversation and a text response
        List<Map<String, Object>> messages = new List<Map<String, Object>>();

        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody(TEXT_RESPONSE_BODY);

        AIProvider.Response result;

        // [2] Handle the response
        Test.startTest();
            result = new AIAnthropicMessageResponseHandler().handleResponse(messages, response, null, null, null);
        Test.stopTest();

        // [3] Check the text, tokens and appended assistant turn
        Assert.areEqual('Hello\nthere', result.textContent, 'The text blocks should be joined.');
        Assert.areEqual(10, result.inputTokens, 'The input tokens should be read from usage.');
        Assert.areEqual(5, result.outputTokens, 'The output tokens should be read from usage.');
        Assert.areEqual(15, result.totalTokens, 'The total should be input plus output.');

        Assert.isTrue(result.toolCalls.isEmpty(), 'There should be no tool calls.');

        Assert.areEqual(1, messages.size(), 'The assistant turn should be appended to the conversation.');
        Assert.areEqual(ROLE_ASSISTANT, messages[0].get('role'), 'The appended turn should have the assistant role.');
    }

    @IsTest static void testScenario2() {

        // [1] Build an empty conversation and a response with only tool_use blocks
        List<Map<String, Object>> messages = new List<Map<String, Object>>();

        HttpResponse response = new HttpResponse();
        response.setStatusCode(200);
        response.setBody(TOOL_RESPONSE_BODY);

        AIProvider.Response result;

        // [2] Handle the response
        Test.startTest();
            result = new AIAnthropicMessageResponseHandler().handleResponse(messages, response, null, null, null);
        Test.stopTest();

        // [3] Check the tool calls and that there is no text
        Assert.areEqual(2, result.toolCalls.size(), 'Both tool calls should be returned.');
        Assert.areEqual('t1', result.toolCalls[0].id, 'The id should be kept so the result can be paired.');
        Assert.areEqual(TOOL_NAME, result.toolCalls[0].name, 'The tool name should be kept.');
        Assert.areEqual('x', result.toolCalls[0].arguments.get('q'), 'The arguments should be kept.');
        Assert.isTrue(result.toolCalls[1].arguments.isEmpty(), 'Missing arguments should become an empty map.');

        Assert.areEqual('', result.textContent, 'With no text blocks there should be no text.');
    }

    @IsTest static void testScenario3() {

        // [1] Build an empty conversation, two tool calls and their results
        List<Map<String, Object>> messages = new List<Map<String, Object>>();

        AIProvider.ToolCall firstCall = new AIProvider.ToolCall();
        firstCall.id = 't1';
        firstCall.name = TOOL_NAME;
        firstCall.arguments = new Map<String, Object>();

        AIProvider.ToolCall secondCall = new AIProvider.ToolCall();
        secondCall.id = 't2';
        secondCall.name = TOOL_NAME;
        secondCall.arguments = new Map<String, Object>();

        List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{
            firstCall,
            secondCall
        };
        List<Object> toolResults = new List<Object>{
            'first result',
            new List<Object>{ 'a' }
        };

        AIProvider.Response result;

        // [2] Handle the tool results with no response
        Test.startTest();
            result = new AIAnthropicMessageResponseHandler().handleResponse(messages, null, calls, toolResults, null);
        Test.stopTest();

        // [3] Read the result blocks back out of the single message
        List<Object> blocks = (List<Object>) messages[0].get('content');
        Map<String, Object> firstBlock = (Map<String, Object>) blocks[0];
        Map<String, Object> secondBlock = (Map<String, Object>) blocks[1];

        // [4] Check the results were batched into one user message
        Assert.isNull(result, 'With no response there should be nothing to parse.');

        Assert.areEqual(1, messages.size(), 'Every result should go in one message.');
        Assert.areEqual(ROLE_USER, messages[0].get('role'), 'Anthropic has no tool role, so results should come back as a user message.');
        Assert.areEqual(2, blocks.size(), 'There should be one block per tool call.');

        Assert.areEqual('t1', firstBlock.get('tool_use_id'), 'Each result should name the call it answers.');
        Assert.areEqual('["a"]', secondBlock.get('content'), 'A non-text result should be serialised.');
    }

    @IsTest static void testScenario4() {

        // [1] Build one tool call and prepare to catch the adapter exception
        AIProvider.ToolCall toolCall = new AIProvider.ToolCall();
        toolCall.id = 't1';
        toolCall.name = TOOL_NAME;
        toolCall.arguments = new Map<String, Object>();
        List<AIProvider.ToolCall> calls = new List<AIProvider.ToolCall>{ toolCall };

        AIAnthropicMessageResponseHandler.AIAnthropicMessageResponseHandlerException thrownException;

        // [2] Handle one tool call with no tool results
        Test.startTest();
            try {
                new AIAnthropicMessageResponseHandler().handleResponse(new List<Map<String, Object>>(), null, calls, new List<Object>(), null);
            } catch (AIAnthropicMessageResponseHandler.AIAnthropicMessageResponseHandlerException ex) {
                thrownException = ex;
            }
        Test.stopTest();

        // [3] Check the mismatch was refused
        Assert.isNotNull(thrownException, 'A result count mismatch should throw the adapter exception.');
        Assert.isTrue(thrownException.getMessage().contains('does not match'), 'The error should say the counts differ.');
    }

    @IsTest static void testScenario5() {

        // [1] Build a JSON error response and a raw error response
        HttpResponse jsonErrorResponse = new HttpResponse();
        jsonErrorResponse.setStatusCode(400);
        jsonErrorResponse.setBody(JSON_ERROR_BODY);

        HttpResponse rawErrorResponse = new HttpResponse();
        rawErrorResponse.setStatusCode(502);
        rawErrorResponse.setBody(RAW_ERROR_BODY);

        List<HttpResponse> failedResponses = new List<HttpResponse>{
            jsonErrorResponse,
            rawErrorResponse
        };
        List<String> errorMessages = new List<String>();

        // [2] Handle each failed response
        Test.startTest();
            for (HttpResponse response : failedResponses) {
                try {
                    new AIAnthropicMessageResponseHandler().handleResponse(new List<Map<String, Object>>(), response, null, null, null);
                } catch (AIAnthropicMessageResponseHandler.AIAnthropicMessageResponseHandlerException ex) {
                    errorMessages.add(ex.getMessage());
                }
            }
        Test.stopTest();

        // [3] Check each failure threw with the right message
        Assert.areEqual(2, errorMessages.size(), 'Both failure statuses should throw.');
        Assert.areEqual('AI provider returned HTTP 400: invalid_request_error - max_tokens is too large', errorMessages[0], 'The provider\'s error type and message should be used.');
        Assert.areEqual('AI provider returned HTTP 502: Bad gateway', errorMessages[1], 'The raw body should be used when it is not JSON.');
    }

    @IsTest static void testScenario6() {

        // [1] Add 201 to the success status codes setting
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.AIProviderSuccessStatusCodes__c = '200,201';
        update settings;
        AIAssistSettingsService.cachedSettings = null;

        // [2] Build a 201 response and a malformed 200 response
        HttpResponse created = new HttpResponse();
        created.setStatusCode(201);
        created.setBody(CREATED_RESPONSE_BODY);

        HttpResponse malformed = new HttpResponse();
        malformed.setStatusCode(200);
        malformed.setBody(MALFORMED_BODY);

        AIProvider.Response result;
        String malformedMessage;

        // [3] Handle both responses
        Test.startTest();
            result = new AIAnthropicMessageResponseHandler().handleResponse(new List<Map<String, Object>>(), created, null, null, null);

            try {
                new AIAnthropicMessageResponseHandler().handleResponse(new List<Map<String, Object>>(), malformed, null, null, null);
            } catch (AIAnthropicMessageResponseHandler.AIAnthropicMessageResponseHandlerException ex) {
                malformedMessage = ex.getMessage();
            }
        Test.stopTest();

        // [4] Check the 201 was accepted and the malformed body was refused
        Assert.areEqual('Created', result.textContent, 'A 201 should be a success when the setting says so.');
        Assert.isNotNull(malformedMessage, 'A malformed body should throw the adapter exception.');
        Assert.isTrue(malformedMessage.startsWith(WRAPPED_ERROR_PREFIX), 'An unexpected error should be wrapped with the original as its cause.');
    }
}
