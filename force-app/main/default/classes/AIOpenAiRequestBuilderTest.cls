/*
Class Name: AIOpenAiRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIOpenAiRequestBuilder: the canonical request becomes the exact JSON body OpenAI expects.

=================================================================
=================================================================
Applicable Classes:

AIOpenAiRequestBuilder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIOpenAiRequestBuilderTest {

    // testScenario1: Building a request with only the required fields -> model, max_tokens and messages are present and the optional keys are omitted.
    // testScenario2: Building a request with a system prompt and temperature -> the system prompt is the first message with the system role, there is no top-level system field, and the temperature is sent.
    // testScenario3: Building requests with tools, with and without tool calls allowed -> each tool is wrapped in a function object, and tool_choice none is added only when tool calls are not allowed.
    // testScenario4: Building a request from null -> the adapter's own exception is thrown with the original as its cause.

    private static final String MODEL_IDENTIFIER = 'test-model';
    private static final String ROLE_SYSTEM = 'system';
    private static final String SYSTEM_PROMPT = 'Be brief.';
    private static final String TOOL_NAME = 'lookup';
    private static final String WRAPPED_ERROR_PREFIX = 'Failed to build the OpenAI request body';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Build a request with only the required fields
        AIProvider.Request request = new AIProvider.Request();
        request.modelIdentifier = MODEL_IDENTIFIER;
        request.maxOutputTokens = 512;
        request.messages = new List<Map<String, Object>>{
            new Map<String, Object>{
                'role' => 'user',
                'content' => 'Hello'
            }
        };

        Map<String, Object> body;

        // [2] Build the request body
        Test.startTest();
            body = new AIOpenAiRequestBuilder().buildRequestBody(request);
        Test.stopTest();

        // [3] Check the body holds the required fields and omits the optional ones
        Assert.areEqual(MODEL_IDENTIFIER, body.get('model'), 'The model should be sent.');
        Assert.areEqual(512, body.get('max_tokens'), 'The output cap should be sent.');
        Assert.areEqual(1, ((List<Object>) body.get('messages')).size(), 'Only the one conversation message should be sent.');

        Assert.isFalse(body.containsKey('temperature'), 'An unset temperature should be omitted.');
        Assert.isFalse(body.containsKey('tools'), 'Unset tools should be omitted.');
    }

    @IsTest static void testScenario2() {

        // [1] Build a request with a system prompt and a temperature
        AIProvider.Request request = new AIProvider.Request();
        request.modelIdentifier = MODEL_IDENTIFIER;
        request.maxOutputTokens = 512;
        request.messages = new List<Map<String, Object>>{
            new Map<String, Object>{
                'role' => 'user',
                'content' => 'Hello'
            }
        };
        request.systemPromptText = SYSTEM_PROMPT;
        request.temperature = 0.7;

        Map<String, Object> body;

        // [2] Build the request body
        Test.startTest();
            body = new AIOpenAiRequestBuilder().buildRequestBody(request);
        Test.stopTest();

        // [3] Read the messages and the first message back out of the body
        List<Object> messages = (List<Object>) body.get('messages');
        Map<String, Object> firstMessage = (Map<String, Object>) messages[0];

        // [4] Check the system prompt is the first message and the temperature is sent
        Assert.areEqual(2, messages.size(), 'The system message plus the conversation should be sent.');
        Assert.areEqual(ROLE_SYSTEM, firstMessage.get('role'), 'The first message should have the system role.');
        Assert.areEqual(SYSTEM_PROMPT, firstMessage.get('content'), 'The first message should carry the system prompt.');

        Assert.isFalse(body.containsKey('system'), 'There should be no top-level system field.');
        Assert.areEqual(0.7, body.get('temperature'), 'The temperature should be sent.');
    }

    @IsTest static void testScenario3() {

        // [1] Build a tool definition for each of the two requests
        AIProvider.ToolDefinition allowedTool = new AIProvider.ToolDefinition();
        allowedTool.name = TOOL_NAME;
        allowedTool.description = 'Looks something up';
        allowedTool.inputSchema = new Map<String, Object>{ 'type' => 'object' };

        AIProvider.ToolDefinition forbiddenTool = new AIProvider.ToolDefinition();
        forbiddenTool.name = TOOL_NAME;
        forbiddenTool.description = 'Looks something up';
        forbiddenTool.inputSchema = new Map<String, Object>{ 'type' => 'object' };

        // [2] Build one request that allows tool calls and one that does not
        AIProvider.Request allowedRequest = new AIProvider.Request();
        allowedRequest.modelIdentifier = MODEL_IDENTIFIER;
        allowedRequest.maxOutputTokens = 512;
        allowedRequest.messages = new List<Map<String, Object>>{
            new Map<String, Object>{
                'role' => 'user',
                'content' => 'Hello'
            }
        };
        allowedRequest.tools = new List<AIProvider.ToolDefinition>{ allowedTool };

        AIProvider.Request forbiddenRequest = new AIProvider.Request();
        forbiddenRequest.modelIdentifier = MODEL_IDENTIFIER;
        forbiddenRequest.maxOutputTokens = 512;
        forbiddenRequest.messages = new List<Map<String, Object>>{
            new Map<String, Object>{
                'role' => 'user',
                'content' => 'Hello'
            }
        };
        forbiddenRequest.tools = new List<AIProvider.ToolDefinition>{
            forbiddenTool
        };
        forbiddenRequest.allowToolCalls = false;

        Map<String, Object> allowedBody;
        Map<String, Object> forbiddenBody;

        // [3] Build both request bodies
        Test.startTest();
            allowedBody = new AIOpenAiRequestBuilder().buildRequestBody(allowedRequest);
            forbiddenBody = new AIOpenAiRequestBuilder().buildRequestBody(forbiddenRequest);
        Test.stopTest();

        // [4] Read the tool and its function details back out of the body
        Map<String, Object> tool = (Map<String, Object>) ((List<Object>) allowedBody.get('tools'))[0];
        Map<String, Object> functionDetails = (Map<String, Object>) tool.get('function');

        // [5] Check the function wrapper and when tool_choice is added
        Assert.areEqual('function', tool.get('type'), 'OpenAI wraps each tool in a function object.');
        Assert.areEqual(TOOL_NAME, functionDetails.get('name'), 'The tool name should be sent.');
        Assert.isNotNull(functionDetails.get('parameters'), 'The input schema should be sent as the parameters.');

        Assert.isFalse(allowedBody.containsKey('tool_choice'), 'No tool_choice should be sent when tool calls are allowed.');
        Assert.areEqual('none', forbiddenBody.get('tool_choice'), 'On the last iteration the model should not be allowed to call a tool.');
    }

    @IsTest static void testScenario4() {

        // [1] Prepare to catch the adapter exception
        AIOpenAiRequestBuilder.AIOpenAiRequestBuilderException thrownException;

        // [2] Build a request body from null
        Test.startTest();
            try {

                new AIOpenAiRequestBuilder().buildRequestBody(null);

            } catch (AIOpenAiRequestBuilder.AIOpenAiRequestBuilderException ex) {

                thrownException = ex;
            }
        Test.stopTest();

        // [3] Check the adapter exception was thrown with the original as its cause
        Assert.isNotNull(thrownException, 'A null request should throw the adapter exception.');
        Assert.isTrue(thrownException.getMessage().startsWith(WRAPPED_ERROR_PREFIX), 'The error should name the adapter.');
        Assert.isNotNull(thrownException.getCause(), 'The original error should be kept as the cause.');
    }
}
