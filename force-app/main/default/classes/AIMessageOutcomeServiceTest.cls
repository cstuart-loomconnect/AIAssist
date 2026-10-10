/*
Class Name: AIMessageOutcomeServiceTest

=================================================================
=================================================================

Description: Testing utility for AIMessageOutcomeService: what is recorded when a turn ends, whether it succeeded or failed, and the label the chat window is told.

=================================================================
=================================================================
Applicable Classes:

AIMessageOutcomeService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessageOutcomeServiceTest {

    // testScenario1: A successful turn stores the reply with the provider's tokens, latency and model, and marks the question Complete.
    // testScenario2: An Estimate agent counts the reply by its length, and a provider that reports only a total has it counted as input.
    // testScenario3: A suggested workflow action is stored when it is a real action Id, and ignored when it is the wrong type or not an Id.
    // testScenario4: A failed result records the reason on the question, a System message holding the tokens spent, and the cause in the log.
    // testScenario5: A null result and a blank reason both fail the turn as Other.
    // testScenario6: recordAiResponseFailure fails the turn with the given reason and tokens, and treats null tokens as none.
    // testScenario7: publishMessageFailure returns the Custom Label that matches each reason, and the generic one for any other.
    // testScenario8: When the reply cannot be saved the turn becomes a failed turn, and a null turn never throws.
    // testScenario9: Two messages sent while a third is being answered all end up Complete: the first by its own reply, the skipped one and the newest by the newest's reply. A failed turn fails the messages waiting behind it the same way.
    // testScenario10: A regenerated reply supersedes the earlier reply to the same message once it is saved, and a regenerate that fails leaves the earlier reply standing.

    private static final String REPLY_TEXT = 'The answer';
    private static final String CLASS_NAME = 'AIMessageOutcomeService';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create a tracked agent, a user, a conversation, a question and a successful result
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = true;
        result.replyText = REPLY_TEXT;
        result.inputTokens = 40;
        result.outputTokens = 10;
        result.totalTokensUsed = 50;
        result.latencyMilliseconds = 1200;

        // [2] Record the outcome of the turn
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, new AIExecutionStepTracker(conversation.Id, question.Id, false, false));
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c reply = [SELECT MessageBody__c, TokenCount__c, InputTokenCount__c, OutputTokenCount__c, LatencyMilliseconds__c, AIModelConfiguration__c, ProcessingStatus__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
        AIConversationMessage__c completedQuestion = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        // [4] Check the outcome
        Assert.areEqual(REPLY_TEXT, reply.MessageBody__c, 'The reply body should be the agent reply text.');
        Assert.areEqual(50, reply.TokenCount__c, 'A tracked agent should use the provider\'s total.');
        Assert.areEqual(40, reply.InputTokenCount__c, 'The reply should hold the input tokens.');
        Assert.areEqual(10, reply.OutputTokenCount__c, 'The reply should hold the output tokens.');
        Assert.areEqual(1200, reply.LatencyMilliseconds__c, 'The reply should hold the latency.');
        Assert.areEqual(agent.AIModelConfiguration__c, reply.AIModelConfiguration__c, 'The reply should hold the model configuration.');
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE, completedQuestion.ProcessingStatus__c, 'The question should be Complete.');
    }

    @IsTest static void testScenario2() {

        // [1] Create an Estimate agent, a conversation, a question and a result that reports only a total
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_ESTIMATE;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = true;
        result.replyText = 'x'.repeat(AIAssistApplicationConstants.CHARACTERS_PER_TOKEN_ESTIMATE * 8);
        result.inputTokens = 0;
        result.outputTokens = 0;
        result.totalTokensUsed = 77;
        result.latencyMilliseconds = 1200;

        // [2] Record the outcome with no step tracker
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c reply = [SELECT TokenCount__c, InputTokenCount__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [4] Check the outcome
        Assert.areEqual(8, reply.TokenCount__c, 'An Estimate agent should count the reply by its length.');
        Assert.areEqual(77, reply.InputTokenCount__c, 'The only figure there is should count as input.');
    }

    @IsTest static void testScenario3() {

        // [1] Create a conversation, a question, a successful result and a real workflow action
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = true;
        result.replyText = REPLY_TEXT;
        result.inputTokens = 40;
        result.outputTokens = 10;
        result.totalTokensUsed = 50;
        result.latencyMilliseconds = 1200;

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', true)[0];

        List<String> suggestions = new List<String>{
            action.Id,
            agent.Id,
            'not an id'
        };

        // [2] Record the outcome once for each suggestion: a real action Id, the wrong type and not an Id
        Test.startTest();
            for (String suggestion : suggestions) {

                result.suggestedWorkflowActionId = suggestion;
                AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, null);
            }
        Test.stopTest();

        // [3] Read the results back
        List<AIConversationMessage__c> replies = [SELECT SuggestedWorkflowAction__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
        Integer storedActionCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE SuggestedWorkflowAction__c = :action.Id];

        // [4] Check the outcome
        Assert.areEqual(3, replies.size(), 'A bad suggestion should never fail the reply.');
        Assert.areEqual(1, storedActionCount, 'Only the real action should be stored.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a conversation, a question and a timed-out failed result
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = false;
        result.failureReason = AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT;
        result.errorMessage = 'Read timed out';
        result.inputTokens = 40;
        result.outputTokens = 10;
        result.totalTokensUsed = 50;
        result.latencyMilliseconds = 1200;

        // [2] Record the failed outcome
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c failedQuestion = [SELECT ProcessingStatus__c, FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        AIConversationMessage__c systemMessage = [SELECT TokenCount__c, FailureReason__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM];

        Integer replyCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = :CLASS_NAME];

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, failedQuestion.ProcessingStatus__c, 'The question should be Failed.');
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT, failedQuestion.FailureReason__c, 'The question should hold the failure reason.');
        Assert.areEqual(50, systemMessage.TokenCount__c, 'The tokens a failed turn spent should still count.');
        Assert.areEqual(0, replyCount, 'A failed turn should have no reply.');
        Assert.areEqual(1, logCount, 'The detail should go to the log, not to a record the user can read.');
    }

    @IsTest static void testScenario5() {

        // [1] Create a conversation, a question and a failed result with no reason
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = false;
        result.failureReason = null;

        // [2] Record a failed result with a blank reason and then a null result
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, null);
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, null, null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c failedQuestion = [SELECT FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_OTHER, failedQuestion.FailureReason__c, 'A blank reason and a null result should both fail the turn as Other.');
    }

    @IsTest static void testScenario6() {

        // [1] Create a conversation and a question with no result
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        // [2] Record a failure with the given reason and null tokens
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseFailure(responseContext, null, 'Job was killed', AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c failedQuestion = [SELECT FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];
        Integer systemMessageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_SYSTEM];

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR, failedQuestion.FailureReason__c, 'The question should hold the given reason.');
        Assert.areEqual(0, systemMessageCount, 'Null tokens should mean no System message.');
    }

    @IsTest static void testScenario7() {

        // [1] List the Custom Label expected for each failure reason
        Map<String, String> labelByReason = new Map<String, String>{
            AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT => Label.AI_Error_Provider_Timeout,
            AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR => Label.AI_Error_Provider_Unavailable,
            AIAssistApplicationConstants.FAILURE_REASON_LIMIT_REACHED => Label.AI_Error_Daily_Usage_Limit,
            AIAssistApplicationConstants.FAILURE_REASON_REQUEST_BLOCKED => Label.AI_Error_Request_Blocked,
            AIAssistApplicationConstants.FAILURE_REASON_PII_MASKING_FAILED => Label.AI_Error_Privacy_Masking_Failed,
            AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR => Label.AI_Error_Provider_Not_Configured,
            AIAssistApplicationConstants.FAILURE_REASON_MESSAGE_MISSING => Label.AI_Error_Conversation_Not_Found,
            AIAssistApplicationConstants.FAILURE_REASON_AUTHENTICATION_FAILED => Label.AI_Error_Provider_Authentication,
            AIAssistApplicationConstants.FAILURE_REASON_MODEL_RETIRED => Label.AI_Error_Provider_Model_Retired,
            AIAssistApplicationConstants.FAILURE_REASON_RATE_LIMITED => Label.AI_Error_Provider_Rate_Limited,
            AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY => Label.AI_Error_Service_Busy,
            AIAssistApplicationConstants.FAILURE_REASON_OTHER => Label.AI_Error_Generic
        };
        Map<String, String> actual = new Map<String, String>();
        String unknown;

        // [2] Publish the failure for each reason and for an unknown one
        Test.startTest();
            for (String reason : labelByReason.keySet()) actual.put(reason, AIMessageOutcomeService.publishMessageFailure(null, reason));
            unknown = AIMessageOutcomeService.publishMessageFailure(null, 'Something new');
        Test.stopTest();

        // [3] Check each label matches
        for (String reason : labelByReason.keySet()) Assert.areEqual(labelByReason.get(reason), actual.get(reason), 'The label for ' + reason + ' should match.');
        Assert.areEqual(Label.AI_Error_Generic, unknown, 'An unknown reason should return the generic label.');
    }

    @IsTest static void testScenario8() {

        // [1] Create a conversation and a question, with a context that points at the wrong conversation
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = agent.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = chatUser.Id;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult result = new AIAgentManager.AgentResult();
        result.isSuccessful = true;
        result.replyText = REPLY_TEXT;
        result.inputTokens = 40;
        result.outputTokens = 10;
        result.totalTokensUsed = 50;
        result.latencyMilliseconds = 1200;

        // [2] Record outcomes with the bad context, a null context and a null failure
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, result, null);
            AIMessageOutcomeService.recordAiResponseOutcome(null, result, null);
            AIMessageOutcomeService.recordAiResponseFailure(null, 0, null, null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c failedQuestion = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, failedQuestion.ProcessingStatus__c, 'No reply could be saved, so the turn should have failed.');
    }

    @IsTest static void testScenario9() {

        // [1] Create an agent, a user and two conversations owned by that user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 2, true);
        for (AIConversation__c conversation : conversations) conversation.OwnerId = chatUser.Id;

        // [2] Queue three messages on the first conversation, the first being answered when the second and third are sent
        List<AIConversationMessage__c> answered = AIAssistTestDataFactory.createAIConversationMessages(conversations[0].Id, AIAssistApplicationConstants.SENDER_USER, 0, 3, false);
        for (AIConversationMessage__c message : answered) message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
        insert answered;
        for (Integer index = 0; index < answered.size(); index++) Test.setCreatedDate(answered[index].Id, System.now().addMinutes(-10).addSeconds(index));

        // [3] Queue two messages on the second conversation
        List<AIConversationMessage__c> failed = AIAssistTestDataFactory.createAIConversationMessages(conversations[1].Id, AIAssistApplicationConstants.SENDER_USER, 0, 2, false);
        for (AIConversationMessage__c message : failed) message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
        insert failed;
        for (Integer index = 0; index < failed.size(); index++) Test.setCreatedDate(failed[index].Id, System.now().addMinutes(-10).addSeconds(index));

        // [4] Build a context for the first, the newest and the failed turn, and the two replies
        AIMessageOutcomeService.AIResponseContext firstContext = new AIMessageOutcomeService.AIResponseContext();
        firstContext.conversationId = conversations[0].Id;
        firstContext.triggeringMessageId = answered[0].Id;
        firstContext.userId = conversations[0].OwnerId;
        firstContext.agentId = agent.Id;
        firstContext.modelConfigurationId = agent.AIModelConfiguration__c;
        firstContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIMessageOutcomeService.AIResponseContext newestContext = new AIMessageOutcomeService.AIResponseContext();
        newestContext.conversationId = conversations[0].Id;
        newestContext.triggeringMessageId = answered[2].Id;
        newestContext.userId = conversations[0].OwnerId;
        newestContext.agentId = agent.Id;
        newestContext.modelConfigurationId = agent.AIModelConfiguration__c;
        newestContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIMessageOutcomeService.AIResponseContext failedContext = new AIMessageOutcomeService.AIResponseContext();
        failedContext.conversationId = conversations[1].Id;
        failedContext.triggeringMessageId = failed[1].Id;
        failedContext.userId = conversations[1].OwnerId;
        failedContext.agentId = agent.Id;
        failedContext.modelConfigurationId = agent.AIModelConfiguration__c;
        failedContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult firstReply = new AIAgentManager.AgentResult();
        firstReply.isSuccessful = true;
        firstReply.replyText = 'First answer';
        firstReply.inputTokens = 4;
        firstReply.outputTokens = 1;
        firstReply.totalTokensUsed = 5;

        AIAgentManager.AgentResult newestReply = new AIAgentManager.AgentResult();
        newestReply.isSuccessful = true;
        newestReply.replyText = 'Newest answer';
        newestReply.inputTokens = 4;
        newestReply.outputTokens = 1;
        newestReply.totalTokensUsed = 5;

        Map<Id, String> afterFirst = new Map<Id, String>();

        // [5] Record the first reply, then the newest reply, then a failure on the second conversation
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(firstContext, firstReply, null);
            for (AIConversationMessage__c message : [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id IN :answered]) afterFirst.put(message.Id, message.ProcessingStatus__c);
            // The finalizer hands the lock to the newest, so the second is never answered itself.
            AIMessageOutcomeService.recordAiResponseOutcome(newestContext, newestReply, null);
            AIMessageOutcomeService.recordAiResponseFailure(failedContext, 0, 'The provider is down.', AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR);
        Test.stopTest();

        // [6] Read the statuses back
        Map<Id, String> afterNewest = new Map<Id, String>();
        for (AIConversationMessage__c message : [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id IN :answered]) afterNewest.put(message.Id, message.ProcessingStatus__c);
        List<AIConversationMessage__c> failedMessages = [SELECT ProcessingStatus__c, FailureReason__c FROM AIConversationMessage__c WHERE Id IN :failed];

        // [7] Check the answered messages all end up Complete and the failed turn fails the one behind it
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE, afterFirst.get(answered[0].Id), 'The first should be Complete by its own reply.');
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, afterFirst.get(answered[1].Id), 'A message sent after the one answered should still be waiting.');
        for (AIConversationMessage__c message : answered) Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE, afterNewest.get(message.Id), 'All three should end up Complete, including the one the hand-off skipped.');
        for (AIConversationMessage__c message : failedMessages) {

            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, message.ProcessingStatus__c, 'A failed turn should fail the message waiting behind it too.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, message.FailureReason__c, 'The waiting message should hold the same reason.');
        }
    }

    @IsTest static void testScenario10() {

        // [1] Create an agent, a user and a conversation owned by that user
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        conversation.OwnerId = chatUser.Id;

        // [2] Queue one question on the conversation
        List<AIConversationMessage__c> queued = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false);
        for (AIConversationMessage__c message : queued) message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
        insert queued;
        for (Integer index = 0; index < queued.size(); index++) Test.setCreatedDate(queued[index].Id, System.now().addMinutes(-10).addSeconds(index));

        AIConversationMessage__c question = queued[0];

        // [3] Build the turn's context and two replies
        AIMessageOutcomeService.AIResponseContext responseContext = new AIMessageOutcomeService.AIResponseContext();
        responseContext.conversationId = conversation.Id;
        responseContext.triggeringMessageId = question.Id;
        responseContext.userId = conversation.OwnerId;
        responseContext.agentId = agent.Id;
        responseContext.modelConfigurationId = agent.AIModelConfiguration__c;
        responseContext.tokenTrackingMethod = AIAssistApplicationConstants.TRACKING_METHOD_TRACK;

        AIAgentManager.AgentResult firstReply = new AIAgentManager.AgentResult();
        firstReply.isSuccessful = true;
        firstReply.replyText = 'First answer';
        firstReply.inputTokens = 4;
        firstReply.outputTokens = 1;
        firstReply.totalTokensUsed = 5;

        AIAgentManager.AgentResult secondReply = new AIAgentManager.AgentResult();
        secondReply.isSuccessful = true;
        secondReply.replyText = 'Second answer';
        secondReply.inputTokens = 4;
        secondReply.outputTokens = 1;
        secondReply.totalTokensUsed = 5;

        Map<String, Boolean> afterFailure = new Map<String, Boolean>();

        // [4] Record a reply, fail a regenerate, read the replies, then record a second reply
        Test.startTest();
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, firstReply, null);
            AIMessageOutcomeService.recordAiResponseFailure(responseContext, 0, 'The regenerate failed.', AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR);
            for (AIConversationMessage__c answer : [SELECT MessageBody__c, IsSuperseded__c FROM AIConversationMessage__c WHERE InReplyTo__c = :question.Id]) afterFailure.put(answer.MessageBody__c, answer.IsSuperseded__c);
            AIMessageOutcomeService.recordAiResponseOutcome(responseContext, secondReply, null);
        Test.stopTest();

        // [5] Read the replies back
        Map<String, Boolean> afterRegenerate = new Map<String, Boolean>();
        for (AIConversationMessage__c answer : [SELECT MessageBody__c, IsSuperseded__c FROM AIConversationMessage__c WHERE InReplyTo__c = :question.Id]) afterRegenerate.put(answer.MessageBody__c, answer.IsSuperseded__c);

        // [6] Check the failed regenerate left the earlier reply standing and the new reply replaced it
        Assert.areEqual(new Map<String, Boolean>{ 'First answer' => false }, afterFailure, 'A failed regenerate should leave the earlier reply standing.');
        Assert.areEqual(new Map<String, Boolean>{
            'First answer' => true,
            'Second answer' => false
        }, afterRegenerate, 'The new reply should replace the old one, and both should answer the same message.');
    }
}
