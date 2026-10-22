/*
Class Name: AIModelsConnectionTestService

=================================================================
=================================================================

Description: Tests the connection of a model by sending one short message through its named credential.

Step 1: Build a stand-in agent and prompt template, and a copy of the model that asks for a short reply
Step 2: Send the message the way a chat turn does, through AIAgentManager
Step 3: Report whether it worked, how long it took, the tokens used and the status, without the provider's own text

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIModelsConnectionTestService {

    // Tests the connection of a model, saved or not. The test is the real chat path, so it checks the provider, the credential, the path and the model ID together. Nothing is saved, so the caller may save afterwards.
    public static AIModelsDataStructure.TestResult runTest(AIModelConfiguration__c modelConfiguration) {

        // [1] Copy the model with a small reply size, so the test uses few tokens
        AIModelConfiguration__c testConfiguration = modelConfiguration.clone(false, true, false, false);
        Decimal configuredTokens = modelConfiguration.MaximumOutputTokens__c == null ? AIAssistApplicationConstants.MODEL_TEST_MAX_OUTPUT_TOKENS : modelConfiguration.MaximumOutputTokens__c;
        testConfiguration.MaximumOutputTokens__c = Math.min(configuredTokens, AIAssistApplicationConstants.MODEL_TEST_MAX_OUTPUT_TOKENS);

        // [2] Build the agent, prompt and message the test sends. None is saved.
        AIAgent__c agent = new AIAgent__c(Name = Label.AI_Models_Test_Agent_Name);
        AIPromptTemplate__c promptTemplate = new AIPromptTemplate__c(Name = Label.AI_Models_Test_Agent_Name, AIPrompt__c = AIAssistApplicationConstants.MODEL_TEST_INSTRUCTIONS);
        AIConversationMessage__c testMessage = new AIConversationMessage__c(Sender__c = AIAssistApplicationConstants.SENDER_USER, MessageBody__c = AIAssistApplicationConstants.MODEL_TEST_MESSAGE);

        // [3] Send it, with no conversation, no data sources and no workflow actions
        AIAgentManager.AgentResult agentResult = AIAgentManager.executeAiMessage(agent, testConfiguration, promptTemplate, null, null, new List<AIConversationMessage__c>{testMessage}, null, null, 1, null);

        // [4] Report the outcome. An empty reply is a failure, because a chat would fail the same way.
        AIModelsDataStructure.TestResult result = new AIModelsDataStructure.TestResult();
        result.isSuccessful = agentResult.isSuccessful && String.isNotBlank(agentResult.replyText);
        result.httpStatusCode = agentResult.httpStatusCode;
        result.latencyMilliseconds = agentResult.latencyMilliseconds;
        result.inputTokens = agentResult.inputTokens;
        result.outputTokens = agentResult.outputTokens;
        result.failureReason = result.isSuccessful ? null : (String.isBlank(agentResult.failureReason) ? AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR : agentResult.failureReason);
        result.namedCredential = modelConfiguration.NamedCredential__c;

        return result;
    }
}
