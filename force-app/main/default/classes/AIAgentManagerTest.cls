/*
Class Name: AIAgentManagerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentManager: one turn with the AI provider, on mocked callouts, covering the reply, the tool-calling loop, retries, failures and the evidence left behind.

=================================================================
=================================================================
Applicable Classes:

AIAgentManager: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentManagerTest {

    // testScenario1: A text reply is returned with its tokens and latency, the callout is pinned to the model's Named Credential and carries the system prompt and history, and a workflow action the model suggests is resolved and stripped from the reply.
    // testScenario2: A tool call runs the data source as a step, its records go back to the model on the next pass, and the second provider call records what was sent: the object, the field names and the record count.
    // testScenario3: An OpenAI reply is parsed the same way, with the system prompt as the first message and prompt and completion tokens split.
    // testScenario4: A retryable status ends the attempt as retryable while attempts remain, is not retryable on the last, and a timeout status is reported as a timeout.
    // testScenario5: A callout exception is retryable, and one that says timed out is reported as a timeout while any other is a provider error.
    // testScenario6: A status that is neither a success nor retryable fails the turn for good with the provider's own error kept for the log.
    // testScenario7: A model configuration with no Named Credential, a credential or path of the wrong shape, or an unsupported provider fails as a configuration error before any callout.
    // testScenario8: A tool the model made up fails with a generic message, tool calls beyond the per-reply cap are skipped with an explanation, and the turn still completes.
    // testScenario9: Tool calls on the last allowed iteration fail the turn as a limit, and a reply with no text fails it as a provider error.
    // testScenario10: The agent's persona opens the system prompt. A rejected credential, a retired model and an exhausted quota are never retried even when their status is listed as retryable, and say which record to fix; rate limiting is retried.
    // testScenario11: Other prompt templates are offered and the model picks one -> the first request lists them and offers the select tool, the second request answers with the picked template alone, and the result names the picked template and its version.
    // testScenario12: The model picks a template that was never offered, and a turn has no other templates -> the unknown pick changes nothing and is answered, and with nothing to pick from the tool is not offered.
    // testScenario13: The Anthropic Agent API with a session saved on the conversation -> the saved session is looked up and continued, only the latest message is sent, and the result carries the session id.
    // testScenario14: A stateless provider with a reference saved on the conversation -> the reference is ignored, no session is looked up, and the result carries no reference.
    // testScenario15: The Anthropic Agent API on a retry -> a new session is started instead of continuing the saved one, and the result carries the new session id.
    // testScenario16: The Anthropic Agent API when sending the message fails after a session was started -> the failed result still carries the session id.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    // Plays back a script of responses and exceptions, one per callout, and remembers what it was sent.
    private class ScriptedMock implements HttpCalloutMock {
        List<Object> script = new List<Object>();
        List<HttpRequest> requests = new List<HttpRequest>();

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            Object next = script.remove(0);
            if (next instanceof Exception) {
                throw (Exception) next;
            }
            return (HttpResponse) next;
        }
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Offer the agent a workflow action
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];
            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);
            List<AIWorkflowAction__c> actions = AIMessageProcessingQueueable.getAssignedActions(agent.Id);

            // [3] Script a text reply that suggests that action
            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Here you go.\n{"suggested_workflow_action":"' + actions[0].DeveloperName__c + '"}') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIExecutionStepTracker trace = new AIExecutionStepTracker(conversation.Id, null, false, false);
            AIAgentManager.AgentResult result;

            // [4] Run one turn with the provider
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, new List<AIDataSource__c>(), actions, 1, trace);
            Test.stopTest();

            // [5] Read back what was sent to the provider
            String sentBody = mock.requests[0].getBody();
            String languageInstruction = String.format(AIAssistApplicationConstants.LANGUAGE_PROMPT_INSTRUCTION, new List<String>{ UserInfo.getLanguage() });

            // [6] Check the reply, the callout and the evidence
            Assert.isTrue(result.isSuccessful, 'The turn succeeded.');
            Assert.areEqual('Here you go.', result.replyText, 'The suggestion line is stripped from the visible reply.');
            Assert.areEqual(String.valueOf(action.Id), result.suggestedWorkflowActionId, 'The suggested action is resolved to a real action that was offered.');
            Assert.areEqual(15, result.totalTokensUsed, 'Total tokens.');
            Assert.areEqual(10, result.inputTokens, 'Input tokens.');
            Assert.areEqual(5, result.outputTokens, 'Output tokens.');
            Assert.isNotNull(result.latencyMilliseconds, 'How long the turn took.');
            Assert.isFalse(result.isRetryable, 'A success is never retried.');

            Assert.areEqual(1, mock.requests.size(), 'One callout.');
            Assert.areEqual('callout:Test_Credential/v1/messages', mock.requests[0].getEndpoint(), 'The callout is pinned to the model configuration\'s Named Credential.');
            Assert.isTrue(sentBody.contains('Be brief.'), 'The prompt template is sent as the system prompt.');
            Assert.isTrue(sentBody.contains(languageInstruction), 'The model is told to reply in the user\'s language.');
            Assert.isTrue(sentBody.contains('Test message 0'), 'The history is sent.');
            Assert.isTrue(sentBody.contains(actions[0].DeveloperName__c), 'The offered workflow action is described to the model.');

            Assert.areEqual(2, trace.steps.size(), 'A prompt assembly step and one provider call step.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_PROMPT_ASSEMBLY, trace.steps[0].stepType, 'The prompt is assembled first.');
            Assert.isTrue(trace.steps[0].stepDetail.contains('Built the prompt'), 'The detail says what was built.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL, trace.steps[1].stepType, 'Then it is a provider call.');
            Assert.areEqual(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, trace.steps[1].provider, 'It records the provider.');
            Assert.areEqual('test-model', trace.steps[1].modelIdentifier, 'And the model.');
            Assert.areEqual('Final reply.', trace.steps[1].stepDetail, 'The provider call says it was the final reply.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Relate the conversation to an account
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            conversation.RelatedRecordId__c = String.valueOf(account.Id);
            update conversation;

            // [3] Give the agent a data source that reads that account
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id, Name FROM Account WHERE Id = :recordId', false)[0];
            dataSource.TargetObject__c = 'Account';
            insert dataSource;

            AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{ dataSource }, true);
            List<AIDataSource__c> dataSources = AIMessageProcessingQueueable.getAssignedDataSources(agent.Id);

            String accountName = [SELECT Name FROM Account WHERE Id = :account.Id].Name;

            // [4] Script a tool call followed by a text reply
            HttpResponse toolResponse = new HttpResponse();
            toolResponse.setStatusCode(200);
            toolResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"' + dataSources[0].DeveloperName__c + '","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('The account is found.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(toolResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIExecutionStepTracker trace = new AIExecutionStepTracker(conversation.Id, null, false, false);
            AIAgentManager.AgentResult result;

            // [5] Run one turn with the provider
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, dataSources, new List<AIWorkflowAction__c>(), 1, trace);
            Test.stopTest();

            // [6] Read back what was sent to the provider
            String firstBody = mock.requests[0].getBody();
            String secondBody = mock.requests[1].getBody();

            // [7] Check the tool loop and the evidence
            Assert.isTrue(result.isSuccessful, 'The turn succeeded after the tool call.');

            Assert.areEqual(2, mock.requests.size(), 'Two provider calls.');
            Assert.isTrue(firstBody.contains('"tools"'), 'The first request advertises the tool.');
            Assert.isTrue(secondBody.contains('tool_result') && secondBody.contains(accountName), 'The second request carries the data source\'s records back.');

            Assert.areEqual(4, trace.steps.size(), 'Prompt assembly, provider call, data source, provider call.');
            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE, trace.steps[2].stepType, 'The middle step is the data source.');
            Assert.areEqual(dataSource.Id, trace.steps[2].dataSourceId, 'It names the data source.');
            Assert.isTrue(trace.steps[2].stepDetail.contains('1 record returned'), 'The detail says how many records came back.');
            Assert.isTrue(trace.steps[1].stepDetail.startsWith('The model asked for the data source'), 'The first call says what the model asked for.');

            Assert.areEqual(1, trace.steps[3].recordsSentCount, 'The record count that went to the provider.');
            Assert.areEqual('Account', trace.steps[3].objectsSent, 'The object that went.');
            Assert.isTrue(trace.steps[3].fieldsSent.contains('Account.Name'), 'The field names that went, never the values.');
            Assert.isFalse(trace.steps[3].fieldsSent.contains(accountName), 'The values never appear in the evidence.');
            Assert.areEqual(2, trace.toolCallingIterationsUsed, 'Two iterations were used.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an OpenAI model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_OPEN_AI;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script an OpenAI reply
            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"choices":[{"message":{"role":"assistant","content":"Hello from OpenAI"}}],"usage":{"prompt_tokens":8,"completion_tokens":4,"total_tokens":12}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn with the provider
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, new List<AIDataSource__c>(), new List<AIWorkflowAction__c>(), 1, new AIExecutionStepTracker(conversation.Id, null, false, false));
            Test.stopTest();

            // [4] Read back what was sent to the provider
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0].getBody());
            Map<String, Object> firstMessage = (Map<String, Object>) ((List<Object>) sent.get('messages'))[0];

            // [5] Check the parsed reply and the message order
            Assert.isTrue(result.isSuccessful, 'The turn succeeded.');
            Assert.areEqual('Hello from OpenAI', result.replyText, 'The reply.');
            Assert.areEqual(8, result.inputTokens, 'Prompt tokens.');
            Assert.areEqual(4, result.outputTokens, 'Completion tokens.');

            Assert.areEqual('system', firstMessage.get('role'), 'The system prompt is the first message on OpenAI.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history, with retryable statuses 408, 429 and 503 (two retries by default: three attempts)
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            settings.RetryableStatusCodes__c = '408,429,503';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a 503, a 408 and another 503
            HttpResponse unavailableOne = new HttpResponse();
            unavailableOne.setStatusCode(503);
            unavailableOne.setBody('Unavailable');

            HttpResponse timeoutResponse = new HttpResponse();
            timeoutResponse.setStatusCode(408);
            timeoutResponse.setBody('Request timeout');

            HttpResponse unavailableTwo = new HttpResponse();
            unavailableTwo.setStatusCode(503);
            unavailableTwo.setBody('Unavailable');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(unavailableOne);
            mock.script.add(timeoutResponse);
            mock.script.add(unavailableTwo);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult first;
            AIAgentManager.AgentResult second;
            AIAgentManager.AgentResult last;

            // [3] Run the first, second and last attempts
            Test.startTest();
                first = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                second = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 2, null);
                last = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 3, null);
            Test.stopTest();

            // [4] Check which attempts can be retried and why they failed
            Assert.isTrue(first.isRetryable, 'The first attempt can be retried.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, first.failureReason, 'A 503 is a provider error.');

            Assert.isTrue(second.isRetryable, 'The second attempt can be retried.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT, second.failureReason, 'A 408 is a timeout.');

            Assert.isFalse(last.isRetryable, 'The last attempt cannot be retried.');
            Assert.isFalse(last.isSuccessful, 'And it failed.');

            Assert.isTrue(first.errorMessage.contains('503'), 'The detail for the log names the status.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a timed out exception and a tunnel exception
            ScriptedMock mock = new ScriptedMock();
            mock.script.add(new CalloutException('Read timed out'));
            mock.script.add(new CalloutException('Unable to tunnel through proxy'));
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult timedOut;
            AIAgentManager.AgentResult unreachable;

            // [3] Run two turns
            Test.startTest();
                timedOut = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                unreachable = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [4] Check each failure is classified and retryable as expected
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT, timedOut.failureReason, 'A timeout.');
            Assert.isTrue(timedOut.isRetryable, 'A callout exception is retried.');

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, unreachable.failureReason, 'Any other callout failure is a provider error.');
            Assert.isTrue(unreachable.errorMessage.contains('Unable to tunnel'), 'The detail for the log keeps the real reason.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a 400 bad request
            HttpResponse badRequest = new HttpResponse();
            badRequest.setStatusCode(400);
            badRequest.setBody('{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens is too large"}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(badRequest);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn with the provider
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [4] Check the turn failed for good and kept the provider's message
            Assert.isFalse(result.isSuccessful, 'The turn failed.');
            Assert.isFalse(result.isRetryable, 'A bad request will not succeed on retry.');

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, result.failureReason, 'A provider error.');
            Assert.isTrue(result.errorMessage.contains('max_tokens is too large'), 'The provider\'s message is kept for the log.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Set a mock that records any callout
            ScriptedMock mock = new ScriptedMock();
            Test.setMock(HttpCalloutMock.class, mock);

            // [3] Make four badly configured copies of the model
            AIModelConfiguration__c noCredential = model.clone(true);
            noCredential.NamedCredential__c = null;

            AIModelConfiguration__c wrongCredential = model.clone(true);
            wrongCredential.NamedCredential__c = 'Bad Credential!';

            AIModelConfiguration__c wrongPath = model.clone(true);
            wrongPath.ApiPath__c = '/v1/../admin';

            AIModelConfiguration__c wrongProvider = model.clone(true);
            wrongProvider.AIProvider__c = 'Skynet';

            List<AIAgentManager.AgentResult> results = new List<AIAgentManager.AgentResult>();

            // [4] Run a turn with each badly configured model
            Test.startTest();
                for (AIModelConfiguration__c badModel : new List<AIModelConfiguration__c>{ noCredential, wrongCredential, wrongPath, wrongProvider }) {
                    results.add(AIAgentManager.executeAiMessage(agent, badModel, template, null, conversation, history, null, null, 1, null));
                }
            Test.stopTest();

            // [5] Check every turn failed as a configuration error with no callout
            Assert.areEqual(4, results.size(), 'One result per badly configured model.');

            for (AIAgentManager.AgentResult result : results) {
                Assert.isFalse(result.isSuccessful, 'A badly configured model cannot succeed.');
                Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR, result.failureReason, 'It is a configuration error.');
                Assert.isFalse(result.isRetryable, 'And will not fix itself on retry.');
            }

            Assert.isTrue(mock.requests.isEmpty(), 'No callout was made to an endpoint that failed its checks.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history, allowing one tool call per reply
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            settings.MaxToolCallsPerIteration__c = 1;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a reply calling two made up tools, then a text reply
            HttpResponse toolResponse = new HttpResponse();
            toolResponse.setStatusCode(200);
            toolResponse.setBody('{"content":[{"type":"tool_use","id":"t1","name":"made_up_tool","input":{}},{"type":"tool_use","id":"t2","name":"another_tool","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('I could not look that up.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(toolResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIExecutionStepTracker trace = new AIExecutionStepTracker(conversation.Id, null, false, false);
            AIAgentManager.AgentResult result;

            // [3] Run one turn with the provider
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, trace);
            Test.stopTest();

            // [4] Read back what the model was told on the second call
            String secondRequest = mock.requests[1].getBody();

            // [5] Check the failures were hidden, the extra call skipped and the turn completed
            Assert.isTrue(result.isSuccessful, 'The turn completes.');
            Assert.isTrue(secondRequest.contains('This tool failed to run'), 'The unknown tool gets the generic failure message, not the real error.');
            Assert.isTrue(secondRequest.contains('too many tool calls'), 'The second call is skipped with an explanation, because providers reject an unanswered tool call.');
            Assert.isFalse(secondRequest.contains('made_up_tool\' was requested'), 'The real error stays out of what the model is told.');

            Assert.areEqual(AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE, trace.steps[2].stepType, 'The failed tool is a data source step, not a provider call.');
            Assert.isFalse(trace.steps[2].isSuccess, 'And it is recorded as failed.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Allow the agent a single tool calling iteration
            agent.MaxToolCallingIterations__c = 1;
            update agent;

            // [3] Script a tool call, then a blank reply
            HttpResponse toolResponse = new HttpResponse();
            toolResponse.setStatusCode(200);
            toolResponse.setBody('{"content":[{"type":"tool_use","id":"t1","name":"made_up_tool","input":{}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse blankResponse = new HttpResponse();
            blankResponse.setStatusCode(200);
            blankResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('   ') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(toolResponse);
            mock.script.add(blankResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult limited;
            AIAgentManager.AgentResult empty;

            // [4] Run two turns
            Test.startTest();
                limited = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                empty = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [5] Check the limit and the blank reply both fail the turn
            Assert.isFalse(limited.isSuccessful, 'The turn did not finish.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED, limited.failureReason, 'It ran out of iterations.');
            Assert.areEqual(6, limited.totalTokensUsed, 'The tokens it spent are reported.');

            Assert.isFalse(empty.isSuccessful, 'A blank reply is not a success.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, empty.failureReason, 'It is reported as a provider error.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, agent, template, conversation and history, listing 401, 404, 429 and 503 as retryable
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CalloutTimeoutMilliseconds__c = 30000;
            settings.RetryableStatusCodes__c = '401,404,429,503';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            template.AIPrompt__c = 'Be brief.';
            insert template;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Give the agent a persona and the model an identifier that will be reported retired
            agent.AIAgentPersona__c = 'A patient mortgage adviser.';
            model.ModelIdentifier__c = 'retired-model-1';

            // [3] Script a reply, a 401, a 404, an exhausted quota and rate limiting
            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Hello.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            HttpResponse rejectedResponse = new HttpResponse();
            rejectedResponse.setStatusCode(401);
            rejectedResponse.setBody('{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');

            HttpResponse retiredResponse = new HttpResponse();
            retiredResponse.setStatusCode(404);
            retiredResponse.setBody('{"type":"error","error":{"type":"not_found_error","message":"model: retired-model-1"}}');

            HttpResponse noQuotaResponse = new HttpResponse();
            noQuotaResponse.setStatusCode(429);
            noQuotaResponse.setBody('{"error":{"code":"insufficient_quota"}}');

            HttpResponse rateLimitedResponse = new HttpResponse();
            rateLimitedResponse.setStatusCode(429);
            rateLimitedResponse.setBody('{"error":{"code":"rate_limit_exceeded"}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(replyResponse);
            mock.script.add(rejectedResponse);
            mock.script.add(retiredResponse);
            mock.script.add(noQuotaResponse);
            mock.script.add(rateLimitedResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult reply;
            AIAgentManager.AgentResult rejected;
            AIAgentManager.AgentResult retired;
            AIAgentManager.AgentResult noQuota;
            AIAgentManager.AgentResult rateLimited;

            // [4] Run five turns
            Test.startTest();
                reply = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                rejected = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                retired = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                noQuota = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
                rateLimited = AIAgentManager.executeAiMessage(agent, model, template, null, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [5] Read back the first request
            String firstBody = mock.requests[0].getBody();

            // [6] Check the persona, the never retried failures and the retried rate limit
            Assert.isTrue(reply.isSuccessful, 'The first turn replied.');
            Assert.isTrue(firstBody.contains('Persona: A patient mortgage adviser.'), 'The persona is in the system prompt: ' + firstBody);
            Assert.isTrue(firstBody.indexOf('Persona:') < firstBody.indexOf('Be brief.'), 'The persona comes before the template.');

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED, rejected.failureReason, 'A 401 is a rejected credential.');
            Assert.isFalse(rejected.isRetryable, 'A rejected credential is not retried.');
            Assert.isTrue(rejected.errorMessage.contains(model.NamedCredential__c) && rejected.errorMessage.contains(model.Id), 'The message names the credential and the record to fix: ' + rejected.errorMessage);

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED, retired.failureReason, 'A 404 naming the model is a retired model.');
            Assert.isFalse(retired.isRetryable, 'A retired model is not retried.');
            Assert.isTrue(retired.errorMessage.contains('retired-model-1'), 'The message names the model: ' + retired.errorMessage);

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED, noQuota.failureReason, 'An exhausted quota is an account problem.');
            Assert.isFalse(noQuota.isRetryable, 'Waiting does not refill a quota.');

            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED, rateLimited.failureReason, 'A 429 is rate limiting.');
            Assert.isTrue(rateLimited.isRetryable, 'Rate limiting is retried.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, an agent with a default template, and two other described templates
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 3, false);
            templates[0].AIPrompt__c = 'Default wording.';
            templates[0].IsDefault__c = true;
            templates[1].AIPrompt__c = 'Write the email in a warm tone.';
            templates[1].DeveloperName__c = 'draft_client_email';
            templates[1].Description__c = 'Drafts an email to the client.';
            templates[2].AIPrompt__c = 'Summarise the account in five bullets.';
            templates[2].DeveloperName__c = 'summarise_account';
            templates[2].Description__c = 'Summarises an account.';
            insert templates;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);
            templates = [SELECT Id, Name, DeveloperName__c, Description__c, IsDefault__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c, Version__c FROM AIPromptTemplate__c WHERE Id IN :templates ORDER BY DeveloperName__c NULLS FIRST];
            AIPromptTemplate__c chosenTemplate = templates[2];

            // [2] Script the model picking a template, then answering
            HttpResponse pickResponse = new HttpResponse();
            pickResponse.setStatusCode(200);
            pickResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"select_prompt_template","input":{"template":"summarise_account"}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Here is the summary.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(pickResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn with the default template and the other two offered
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, templates[0], new List<AIPromptTemplate__c>{ templates[1], templates[2] }, conversation, history, null, null, 1, null);
            Test.stopTest();

            // [4] Read back what was sent to the provider
            String firstBody = mock.requests[0].getBody();
            String secondBody = mock.requests[1].getBody();

            // [5] Check the choices were offered, then the picked template alone was used
            Assert.isTrue(result.isSuccessful, 'The turn succeeded after the pick.');
            Assert.areEqual(2, mock.requests.size(), 'Two provider calls.');

            Assert.isTrue(firstBody.contains('"name":"select_prompt_template"'), 'The first request offers the select tool.');
            Assert.isTrue(firstBody.contains('draft_client_email: Drafts an email to the client.'), 'The first request describes each template.');
            Assert.isTrue(firstBody.contains('Default wording.'), 'The first request starts with the default template.');
            Assert.isFalse(firstBody.contains('Summarise the account in five bullets.'), 'A template is not sent until it is picked.');

            Assert.isTrue(secondBody.contains('Summarise the account in five bullets.'), 'The second request uses the picked template.');
            Assert.isFalse(secondBody.contains('Default wording.'), 'The default wording is replaced by the picked template.');
            Assert.isFalse(secondBody.contains('draft_client_email: Drafts an email to the client.'), 'The list of choices is dropped once one is picked.');
            Assert.isTrue(secondBody.contains(AIAssistApplicationConstants.TOOL_RESULT_PROMPT_TEMPLATE_SELECTED), 'The model is told the pick worked.');

            Assert.areEqual(chosenTemplate.Id, result.selectedPromptTemplateId, 'The result names the template that produced the reply.');
            Assert.areEqual(chosenTemplate.Version__c, result.selectedPromptTemplateVersion, 'And its version.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic model, an agent, a default template and one other described template
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
            templates[0].AIPrompt__c = 'Default wording.';
            templates[0].IsDefault__c = true;
            templates[1].AIPrompt__c = 'Write the email in a warm tone.';
            templates[1].DeveloperName__c = 'draft_client_email';
            templates[1].Description__c = 'Drafts an email to the client.';
            insert templates;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script the model picking a name that was never offered, then answering, and then a plain answer for the second turn
            HttpResponse pickResponse = new HttpResponse();
            pickResponse.setStatusCode(200);
            pickResponse.setBody('{"content":[{"type":"tool_use","id":"toolu_1","name":"select_prompt_template","input":{"template":"made_up"}}],"usage":{"input_tokens":4,"output_tokens":2}}');

            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":' + JSON.serialize('Plain answer.') + '}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(pickResponse);
            mock.script.add(replyResponse);
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult unknownPick;
            AIAgentManager.AgentResult nothingToPick;

            // [3] Run one turn with a template on offer and one with none on offer
            Test.startTest();
                unknownPick = AIAgentManager.executeAiMessage(agent, model, templates[0], new List<AIPromptTemplate__c>{ templates[1] }, conversation, history, null, null, 1, null);
                nothingToPick = AIAgentManager.executeAiMessage(agent, model, templates[0], new List<AIPromptTemplate__c>(), conversation, history, null, null, 1, null);
            Test.stopTest();

            // [4] Read back what was sent to the provider
            String afterUnknownBody = mock.requests[1].getBody();
            String nothingToPickBody = mock.requests[2].getBody();

            // [5] Check the unknown pick changed nothing and no tool is offered without choices
            Assert.isTrue(unknownPick.isSuccessful, 'The turn still succeeds after an unknown pick.');
            Assert.isNull(unknownPick.selectedPromptTemplateId, 'An unknown pick selects nothing.');
            Assert.isTrue(afterUnknownBody.contains(AIAssistApplicationConstants.TOOL_RESULT_PROMPT_TEMPLATE_UNKNOWN), 'The model is told the name is not on the list.');
            Assert.isTrue(afterUnknownBody.contains('Default wording.'), 'The default template still answers.');

            Assert.isTrue(nothingToPick.isSuccessful, 'A turn with nothing to pick succeeds.');
            Assert.isFalse(nothingToPickBody.contains('select_prompt_template'), 'The select tool is not offered when there are no other templates.');
        }
    }

    @IsTest static void testScenario13() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic Agent API model, an agent and a conversation that already has a saved session
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
            model.ModelIdentifier__c = 'agent_1';
            model.EnvironmentId__c = 'env_1';
            model.ApiPath__c = '/v1/sessions';
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false)[0];
            conversation.ExternalReference__c = 'sesn_saved';
            insert conversation;
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 2, false);

            // [2] Script the lookup of the saved session, the events being accepted, and the agent's answer
            HttpResponse lookupResponse = new HttpResponse();
            lookupResponse.setStatusCode(200);
            lookupResponse.setBody('{"id":"sesn_saved","status":"idle","archived_at":null,"agent":{"type":"agent","id":"agent_1"},"environment_id":"env_1"}');
            HttpResponse sendResponse = new HttpResponse();
            sendResponse.setStatusCode(200);
            sendResponse.setBody('{}');
            HttpResponse eventsResponse = new HttpResponse();
            eventsResponse.setStatusCode(200);
            eventsResponse.setBody('{"data":[{"type":"user.message"},{"type":"agent.message","content":[{"type":"text","text":"Hello again."}]},{"type":"span.model_request_end","model_usage":{"input_tokens":10,"output_tokens":5}},{"type":"session.status_idle","stop_reason":{"type":"end_turn"}}]}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(lookupResponse);
            mock.script.add(sendResponse);
            mock.script.add(eventsResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, new List<AIDataSource__c>(), new List<AIWorkflowAction__c>(), 1, null);
            Test.stopTest();

            // [4] Check the saved session was continued and only the latest message went with it
            Assert.isTrue(result.isSuccessful, 'The turn should succeed.');
            Assert.areEqual('Hello again.', result.replyText, 'The agent\'s answer should be the reply.');
            Assert.areEqual('sesn_saved', result.externalReference, 'The result should carry the session id for the caller to save.');
            Assert.areEqual('GET', mock.requests[0].getMethod(), 'The saved session should be looked up first.');
            Assert.areEqual('callout:Test_Credential/v1/sessions/sesn_saved', mock.requests[0].getEndpoint(), 'The lookup should be for the saved session.');
            Assert.areEqual('callout:Test_Credential/v1/sessions/sesn_saved/events', mock.requests[1].getEndpoint(), 'The message should be sent to the saved session.');
            Assert.isFalse(mock.requests[1].getBody().contains(AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_HEADING), 'The earlier conversation should not be sent again.');
        }
    }

    @IsTest static void testScenario14() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a stateless Anthropic model and a conversation that has a reference saved on it
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC;
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false)[0];
            conversation.ExternalReference__c = 'sesn_saved';
            insert conversation;
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a plain text reply
            HttpResponse replyResponse = new HttpResponse();
            replyResponse.setStatusCode(200);
            replyResponse.setBody('{"content":[{"type":"text","text":"Hello."}],"usage":{"input_tokens":10,"output_tokens":5}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(replyResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, new List<AIDataSource__c>(), new List<AIWorkflowAction__c>(), 1, null);
            Test.stopTest();

            // [4] Check the reference was ignored
            Assert.isTrue(result.isSuccessful, 'The turn should succeed.');
            Assert.isNull(result.externalReference, 'A stateless provider should return no reference.');
            Assert.areEqual(1, mock.requests.size(), 'Only the model call should be made, with no session lookup.');
            Assert.areEqual('callout:Test_Credential/v1/messages', mock.requests[0].getEndpoint(), 'The call should go to the messages endpoint.');
        }
    }

    @IsTest static void testScenario15() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic Agent API model, an agent and a conversation that already has a saved session
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
            model.ModelIdentifier__c = 'agent_1';
            model.EnvironmentId__c = 'env_1';
            model.ApiPath__c = '/v1/sessions';
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, false)[0];
            conversation.ExternalReference__c = 'sesn_saved';
            insert conversation;
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 2, false);

            // [2] Script a new session being started, the events being accepted, and the agent's answer
            HttpResponse startResponse = new HttpResponse();
            startResponse.setStatusCode(200);
            startResponse.setBody('{"id":"sesn_fresh"}');
            HttpResponse sendResponse = new HttpResponse();
            sendResponse.setStatusCode(200);
            sendResponse.setBody('{}');
            HttpResponse eventsResponse = new HttpResponse();
            eventsResponse.setStatusCode(200);
            eventsResponse.setBody('{"data":[{"type":"user.message"},{"type":"agent.message","content":[{"type":"text","text":"Hello again."}]},{"type":"session.status_idle","stop_reason":{"type":"end_turn"}}]}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(startResponse);
            mock.script.add(sendResponse);
            mock.script.add(eventsResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run the turn as the second attempt
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, new List<AIDataSource__c>(), new List<AIWorkflowAction__c>(), 2, null);
            Test.stopTest();

            // [4] Check a new session was started, with the earlier conversation written into the message
            Assert.isTrue(result.isSuccessful, 'The retry should succeed.');
            Assert.areEqual('sesn_fresh', result.externalReference, 'The result should carry the new session id.');
            Assert.areEqual('POST', mock.requests[0].getMethod(), 'A new session should be started with no lookup of the saved one.');
            Assert.areEqual('callout:Test_Credential/v1/sessions', mock.requests[0].getEndpoint(), 'The session should be started on the sessions endpoint.');
            Assert.isTrue(mock.requests[1].getBody().contains(AIAssistApplicationConstants.ANTHROPIC_AGENT_TRANSCRIPT_HEADING), 'A new session should be given the earlier conversation.');
        }
    }

    @IsTest static void testScenario16() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build an Anthropic Agent API model, an agent and a conversation with no saved session
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
            model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
            model.ModelIdentifier__c = 'agent_1';
            model.EnvironmentId__c = 'env_1';
            model.ApiPath__c = '/v1/sessions';
            insert model;

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> history = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, null, 1, false);

            // [2] Script a new session being started, then the events being refused
            HttpResponse startResponse = new HttpResponse();
            startResponse.setStatusCode(200);
            startResponse.setBody('{"id":"sesn_fresh"}');
            HttpResponse refusedResponse = new HttpResponse();
            refusedResponse.setStatusCode(400);
            refusedResponse.setBody('{"error":{"type":"invalid_request_error","message":"bad events"}}');

            ScriptedMock mock = new ScriptedMock();
            mock.script.add(startResponse);
            mock.script.add(refusedResponse);
            Test.setMock(HttpCalloutMock.class, mock);

            AIAgentManager.AgentResult result;

            // [3] Run one turn
            Test.startTest();
                result = AIAgentManager.executeAiMessage(agent, model, null, null, conversation, history, new List<AIDataSource__c>(), new List<AIWorkflowAction__c>(), 1, null);
            Test.stopTest();

            // [4] Check the turn failed but the session id was still returned, so it can be saved and not orphaned
            Assert.isFalse(result.isSuccessful, 'The turn should fail.');
            Assert.areEqual('sesn_fresh', result.externalReference, 'A failed turn should still carry the session that was started.');
        }
    }
}
