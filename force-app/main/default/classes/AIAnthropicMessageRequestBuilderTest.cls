/*
Class Name: AIAnthropicMessageRequestBuilderTest

=================================================================
=================================================================

Description: Testing utility for AIAnthropicMessageRequestBuilder: the canonical request becomes the exact JSON body Anthropic expects.

=================================================================
=================================================================
Applicable Classes:

AIAnthropicMessageRequestBuilder: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAnthropicMessageRequestBuilderTest {

    // testScenario1: Building a request with only the required fields -> model, max_tokens and messages are present; temperature, system and tools are omitted entirely rather than sent as null.
    // testScenario2: Building a request with temperature and a system prompt -> both are sent, and the system prompt is a top-level field, not a message.
    // testScenario3: Building requests with tools, with and without tool calls allowed -> tools are sent in Anthropic's flat shape, and tool_choice none is added only when tool calls are not allowed.
    // testScenario4: Building a null request -> the adapter's own exception is thrown with the original as its cause.

    private static final String MODEL_IDENTIFIER = 'test-model';
    private static final Integer MAX_OUTPUT_TOKENS = 512;
    private static final String TOOL_NAME = 'lookup';
    private static final String TOOL_DESCRIPTION = 'Looks something up';
    private static final String SYSTEM_PROMPT = 'Be brief.';
    private static final String ERROR_PREFIX = 'Failed to build the Anthropic request body';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a request with only the required fields
            AIProvider.Request request = new AIProvider.Request();
            request.modelIdentifier = MODEL_IDENTIFIER;
            request.maxOutputTokens = MAX_OUTPUT_TOKENS;
            request.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
            };

            Map<String, Object> body;

            // [2] Build the request body
            Test.startTest();
                body = new AIAnthropicMessageRequestBuilder().buildRequestBody(request);
            Test.stopTest();

            // [3] Check the body holds the required fields and omits the optional ones
            Assert.areEqual(MODEL_IDENTIFIER, body.get('model'), 'The model should be sent.');
            Assert.areEqual(MAX_OUTPUT_TOKENS, body.get('max_tokens'), 'The output cap should be sent.');
            Assert.areEqual(request.messages, body.get('messages'), 'The messages should be sent unchanged.');

            Assert.isFalse(body.containsKey('temperature'), 'No temperature is set, so none should be sent.');
            Assert.isFalse(body.containsKey('system'), 'No system prompt is set, so none should be sent.');
            Assert.isFalse(body.containsKey('tools'), 'No tools are set, so none should be sent.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a request with a temperature and a system prompt
            AIProvider.Request request = new AIProvider.Request();
            request.modelIdentifier = MODEL_IDENTIFIER;
            request.maxOutputTokens = MAX_OUTPUT_TOKENS;
            request.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
            };

            request.temperature = 0.4;
            request.systemPromptText = SYSTEM_PROMPT;

            Map<String, Object> body;

            // [2] Build the request body
            Test.startTest();
                body = new AIAnthropicMessageRequestBuilder().buildRequestBody(request);
            Test.stopTest();

            // [3] Count the messages that were sent
            Integer messageCount = ((List<Object>) body.get('messages')).size();

            // [4] Check the temperature and system prompt are top-level fields
            Assert.areEqual(0.4, body.get('temperature'), 'The temperature should be sent.');
            Assert.areEqual(SYSTEM_PROMPT, body.get('system'), 'The system prompt should be a top-level field on Anthropic.');
            Assert.areEqual(1, messageCount, 'The system prompt should not be added as a message.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a tool definition for each of the two requests
            AIProvider.ToolDefinition allowedTool = new AIProvider.ToolDefinition();
            allowedTool.name = TOOL_NAME;
            allowedTool.description = TOOL_DESCRIPTION;
            allowedTool.inputSchema = new Map<String, Object>{ 'type' => 'object' };

            AIProvider.ToolDefinition forbiddenTool = new AIProvider.ToolDefinition();
            forbiddenTool.name = TOOL_NAME;
            forbiddenTool.description = TOOL_DESCRIPTION;
            forbiddenTool.inputSchema = new Map<String, Object>{ 'type' => 'object' };

            // [2] Build one request that allows tool calls and one that does not
            AIProvider.Request allowed = new AIProvider.Request();
            allowed.modelIdentifier = MODEL_IDENTIFIER;
            allowed.maxOutputTokens = MAX_OUTPUT_TOKENS;
            allowed.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
            };
            allowed.tools = new List<AIProvider.ToolDefinition>{ allowedTool };

            AIProvider.Request forbidden = new AIProvider.Request();
            forbidden.modelIdentifier = MODEL_IDENTIFIER;
            forbidden.maxOutputTokens = MAX_OUTPUT_TOKENS;
            forbidden.messages = new List<Map<String, Object>>{
                new Map<String, Object>{ 'role' => 'user', 'content' => 'Hello' }
            };
            forbidden.tools = new List<AIProvider.ToolDefinition>{ forbiddenTool };
            forbidden.allowToolCalls = false;

            Map<String, Object> allowedBody;
            Map<String, Object> forbiddenBody;

            // [3] Build both request bodies
            Test.startTest();
                allowedBody = new AIAnthropicMessageRequestBuilder().buildRequestBody(allowed);
                forbiddenBody = new AIAnthropicMessageRequestBuilder().buildRequestBody(forbidden);
            Test.stopTest();

            // [4] Read the tool and the tool choice back out of the bodies
            Map<String, Object> tool = (Map<String, Object>) ((List<Object>) allowedBody.get('tools'))[0];
            Map<String, Object> toolChoice = (Map<String, Object>) forbiddenBody.get('tool_choice');

            // [5] Check the tool shape and when tool_choice is added
            Assert.areEqual(TOOL_NAME, tool.get('name'), 'The tool name should be sent.');
            Assert.areEqual(TOOL_DESCRIPTION, tool.get('description'), 'The tool description should be sent.');
            Assert.isNotNull(tool.get('input_schema'), 'The input schema should be sent flat, with no function wrapper.');

            Assert.isFalse(allowedBody.containsKey('tool_choice'), 'Tool calls are allowed, so nothing should be restricted.');
            Assert.areEqual('none', toolChoice.get('type'), 'On the last iteration the model should not be allowed to call a tool.');
            Assert.isNotNull(forbiddenBody.get('tools'), 'The tools should stay listed, or Anthropic rejects a conversation that already contains tool calls.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Prepare to catch the adapter exception
            AIAnthropicMessageRequestBuilder.AIAnthropicMessageRequestBuilderException thrownException;

            // [2] Build a request body from null
            Test.startTest();
                try {
                    new AIAnthropicMessageRequestBuilder().buildRequestBody(null);
                } catch (AIAnthropicMessageRequestBuilder.AIAnthropicMessageRequestBuilderException ex) {
                    thrownException = ex;
                }
            Test.stopTest();

            // [3] Check the adapter exception was thrown with the original as its cause
            Assert.isNotNull(thrownException, 'A null request should throw the adapter exception.');
            Assert.isTrue(thrownException.getMessage().startsWith(ERROR_PREFIX), 'The error should name the adapter.');
            Assert.isNotNull(thrownException.getCause(), 'The original error should be kept as the cause.');
        }
    }
}
