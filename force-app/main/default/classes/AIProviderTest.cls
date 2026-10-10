/*
Class Name: AIProviderTest

=================================================================
=================================================================

Description: Testing utility for AIProvider: the provider lookup and the canonical request and response types every provider adapter converts to and from.

=================================================================
=================================================================
Applicable Classes:

AIProvider: Coverage TBC
IAIProviderRequestBuilder: Coverage TBC
IAIProviderResponseHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIProviderTest {

    // testScenario1: Both supported providers are recognised in any case -> each has a request builder and a response handler of its own.
    // testScenario2: An unknown, blank or null provider is asked for -> it is not supported and asking for its adapters throws.
    // testScenario3: stringifyToolResult is given a String, a map and a list -> the String passes through untouched and the others are serialised to JSON.
    // testScenario4: The canonical types are created -> tool calls are allowed on a request, and a response has no tool calls and no tokens.
    // testScenario5: getFailureReason is given rejected credentials, an exhausted quota, a retired model, rate limiting, a timeout and other errors -> each maps to its own reason, and anything else to a provider error.
    // testScenario6: The Anthropic Agent provider is asked for -> it is supported and has its own request builder, response handler and preset.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Ask whether each provider is supported and fetch its builder and handler
        Test.startTest();
            Boolean isAnthropic = AIProvider.isSupported(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC);
            Boolean isOpenAiLowerCase = AIProvider.isSupported(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI.toLowerCase());

            IAIProviderRequestBuilder anthropicBuilder = AIProvider.getRequestBuilder(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC);
            IAIProviderResponseHandler anthropicHandler = AIProvider.getResponseHandler(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC);

            IAIProviderRequestBuilder openAiBuilder = AIProvider.getRequestBuilder(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI);
            IAIProviderResponseHandler openAiHandler = AIProvider.getResponseHandler(AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI);
        Test.stopTest();

        // [2] Check both providers are recognised with their own adapters
        Assert.areEqual(true, isAnthropic, 'Anthropic is supported.');
        Assert.areEqual(true, isOpenAiLowerCase, 'The match ignores case.');

        Assert.areEqual(true, anthropicBuilder instanceof AIAnthropicMessageRequestBuilder, 'Anthropic has its own request builder.');
        Assert.areEqual(true, anthropicHandler instanceof AIAnthropicMessageResponseHandler, 'Anthropic has its own response handler.');

        Assert.areEqual(true, openAiBuilder instanceof AIOpenAiRequestBuilder, 'OpenAI has its own request builder.');
        Assert.areEqual(true, openAiHandler instanceof AIOpenAiResponseHandler, 'OpenAI has its own response handler.');
    }

    @IsTest static void testScenario2() {

        // [1] Prepare to capture the errors
        String requestBuilderMessage;
        String responseHandlerMessage;

        // [2] Ask about an unknown, blank and null provider and fetch adapters that throw
        Test.startTest();
            Boolean isUnknown = AIProvider.isSupported('Skynet');
            Boolean isBlank = AIProvider.isSupported('');
            Boolean isNull = AIProvider.isSupported(null);

            try {
                AIProvider.getRequestBuilder('Skynet');
            } catch (AIProvider.AIProviderException ex) {
                requestBuilderMessage = ex.getMessage();
            }

            try {
                AIProvider.getResponseHandler(null);
            } catch (AIProvider.AIProviderException ex) {
                responseHandlerMessage = ex.getMessage();
            }
        Test.stopTest();

        // [3] Check none is supported and both errors say so
        Assert.areEqual(false, isUnknown, 'An unknown provider is not supported.');
        Assert.areEqual(false, isBlank, 'A blank provider is not supported.');
        Assert.areEqual(false, isNull, 'A null provider is not supported.');

        Assert.isNotNull(requestBuilderMessage, 'An unsupported provider should have thrown for its request builder.');
        Assert.areEqual(true, requestBuilderMessage.contains('Unsupported AI Provider'), 'The error says the provider is unsupported.');

        Assert.isNotNull(responseHandlerMessage, 'A null provider should have thrown for its response handler.');
        Assert.areEqual(true, responseHandlerMessage.contains('Unsupported AI Provider'), 'The error says the provider is unsupported.');
    }

    @IsTest static void testScenario3() {

        // [1] Stringify a String, a map and a list
        Test.startTest();
            String fromString = AIProvider.stringifyToolResult('No records found.');
            String fromMap = AIProvider.stringifyToolResult(new Map<String, Object>{ 'count' => 2 });
            String fromList = AIProvider.stringifyToolResult(new List<Object>{ 'a', 1 });
        Test.stopTest();

        // [2] Check the String passes through and the others become JSON
        Assert.areEqual('No records found.', fromString, 'A String is passed through.');
        Assert.areEqual('{"count":2}', fromMap, 'A map is serialised.');
        Assert.areEqual('["a",1]', fromList, 'A list is serialised.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a request and a response
        Test.startTest();
            AIProvider.Request request = new AIProvider.Request();
            AIProvider.Response response = new AIProvider.Response();
        Test.stopTest();

        // [2] Check the request allows tool calls and the response is empty
        Assert.areEqual(true, request.allowToolCalls, 'A request allows tool calls until the last iteration turns them off.');
        Assert.areEqual(true, response.toolCalls.isEmpty(), 'A response has no tool calls.');
        Assert.areEqual(0, response.totalTokens, 'And no tokens.');
        Assert.areEqual(0, response.inputTokens, 'Nor input tokens.');
        Assert.areEqual(0, response.outputTokens, 'Nor output tokens.');
    }

    @IsTest static void testScenario5() {

        // [1] Define each status, body and expected reason
        // Status and body, then the reason expected.
        List<List<Object>> cases = new List<List<Object>>{
            new List<Object>{
                401,
                '{"error":{"code":"invalid_api_key"}}',
                AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
            },
            new List<Object>{
                403,
                '{"type":"error","error":{"type":"permission_error"}}',
                AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
            },
            new List<Object>{
                429,
                '{"error":{"code":"insufficient_quota"}}',
                AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED
            },
            new List<Object>{
                404,
                '{"error":{"code":"model_not_found"}}',
                AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
            },
            new List<Object>{
                404,
                '{"type":"error","error":{"type":"not_found_error","message":"model: claude-old"}}',
                AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
            },
            new List<Object>{
                410,
                null,
                AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
            },
            new List<Object>{
                400,
                'The model has been deprecated.',
                AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED
            },
            new List<Object>{
                429,
                '{"error":{"code":"rate_limit_exceeded"}}',
                AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED
            },
            new List<Object>{
                408,
                '',
                AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
            },
            new List<Object>{
                504,
                'Gateway timeout',
                AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT
            },
            new List<Object>{
                503,
                'Unavailable',
                AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
            },
            new List<Object>{
                404,
                'No such path',
                AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR
            }
        };
        List<String> reasons = new List<String>();

        // [2] Get the failure reason for every case
        Test.startTest();
            for (List<Object> oneCase : cases) {
                reasons.add(AIProvider.getFailureReason((Integer) oneCase[0], (String) oneCase[1]));
            }
        Test.stopTest();

        // [3] Check each case maps to its own reason
        for (Integer index = 0; index < cases.size(); index++) {
            Assert.areEqual(cases[index][2], reasons[index], 'HTTP ' + cases[index][0] + ' with ' + cases[index][1]);
        }
    }

    @IsTest static void testScenario6() {

        // [1] Ask for the Anthropic Agent provider's adapters and preset
        Test.startTest();
            Boolean isSupported = AIProvider.isSupported(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT);
            IAIProviderRequestBuilder builder = AIProvider.getRequestBuilder(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT);
            IAIProviderResponseHandler handler = AIProvider.getResponseHandler(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT);
            AIProvider.Preset preset = AIProvider.getPreset(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT, null);
        Test.stopTest();

        // [2] Check each
        Assert.areEqual(true, isSupported, 'The Anthropic Agent provider is supported.');
        Assert.areEqual(true, builder instanceof AIAnthropicAgentRequestBuilder, 'It has its own request builder.');
        Assert.areEqual(true, handler instanceof AIAnthropicAgentResponseHandler, 'It has its own response handler.');
        Assert.areEqual('/v1/sessions', preset.apiPath, 'Its preset starts sessions.');
        Assert.areEqual('x-api-key', preset.headerName, 'It authenticates with the API key.');
    }
}
