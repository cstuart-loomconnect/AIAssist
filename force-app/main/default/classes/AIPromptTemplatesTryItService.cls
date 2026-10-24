/*
Class Name: AIPromptTemplatesTryItService

=================================================================
=================================================================

Description: Runs one message through the model with a prompt template's saved wording and its edited wording, for the Try it tab.

Step 1: Check the message and the agent, and fill the merge fields from the agent and the record
Step 2: Run the message with the saved wording, then with the edited wording, the same way a chat turn runs but with no data sources or workflow actions
Step 3: Keep the replies on the saved test message when the run came from one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplatesTryItService {

    public class AIPromptTemplatesTryItServiceException extends Exception {}

    // Runs the message with both wordings. The saved wording is left out for a template that is not saved yet. A saved test message gets the replies, and its marks are cleared because they were about the earlier replies. Only the wording is tested: no data sources or workflow actions are offered to the model.
    public static AIPromptTemplatesDataStructure.TryItResult runTryIt(AIPromptTemplatesDataStructure.TemplateDetail detail, String messageBody, Id agentId, Id recordId, Id testMessageId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Check the message and the agent, and load the agent's model
        if (String.isBlank(messageBody)) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Message_Required);
        if (messageBody.length() > AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Message_Too_Long);
        if (agentId == null) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Agent_Required);

        AIAgent__c agent = AIPromptTemplatesEditorService.findAgent(agentId);

        if (agent == null || agent.AIModelConfiguration__c == null) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Agent_No_Model);

        AIModelConfiguration__c modelConfiguration = getModelConfiguration(agent.AIModelConfiguration__c);

        if (modelConfiguration == null) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Agent_No_Model);

        // [3] Fill the merge fields of each wording from the agent, the user and the record
        Map<String, String> valueByToken = AIPromptMergeFieldService.buildValues(agent, AIPromptTemplatesEditorService.getFirstObjectApiName(agent), recordId, true);
        AIPromptTemplate__c editedTemplate = AIPromptMergeFieldService.buildFilledTemplate(AIPromptTemplatesEditorService.buildTemplateFromDetail(detail), valueByToken);
        AIPromptTemplate__c savedTemplate = detail == null || detail.templateId == null ? null : getSavedTemplate(detail.templateId);

        // [4] Run the saved wording, then the edited wording. Nothing is saved before the last callout, because the platform refuses a callout after unsaved changes.
        AIPromptTemplatesDataStructure.TryItResult result = new AIPromptTemplatesDataStructure.TryItResult();

        if (savedTemplate != null) result.savedRun = runMessage(agent, modelConfiguration, AIPromptMergeFieldService.buildFilledTemplate(savedTemplate, valueByToken), messageBody);

        result.editedRun = runMessage(agent, modelConfiguration, editedTemplate, messageBody);

        // [5] Keep the replies on the saved test message
        if (testMessageId != null) result.testMessage = saveRunOnTestMessage(testMessageId, result);

        return result;
    }

    // Runs one message with one wording the way a chat turn does, and reports the reply.
    private static AIPromptTemplatesDataStructure.RunResult runMessage(AIAgent__c agent, AIModelConfiguration__c modelConfiguration, AIPromptTemplate__c promptTemplate, String messageBody) {

        // [1] Build the one message the model answers
        AIConversationMessage__c userMessage = new AIConversationMessage__c(Sender__c = AIAssistApplicationConstants.SENDER_USER, MessageBody__c = messageBody);

        // [2] Run it, with no conversation, no data sources and no workflow actions
        AIAgentManager.AgentResult agentResult = AIAgentManager.executeAiMessage(agent, modelConfiguration, promptTemplate, null, null, new List<AIConversationMessage__c>{userMessage}, null, null, 1, null);

        // [3] Report the reply, or a message that is safe to show when there was none
        AIPromptTemplatesDataStructure.RunResult runResult = new AIPromptTemplatesDataStructure.RunResult();
        runResult.isSuccessful = agentResult.isSuccessful && String.isNotBlank(agentResult.replyText);
        runResult.replyText = agentResult.replyText;
        runResult.latencyMilliseconds = agentResult.latencyMilliseconds;
        runResult.totalTokens = agentResult.totalTokensUsed;
        runResult.errorMessage = runResult.isSuccessful ? null : Label.AI_Prompts_Error_Run_Failed;

        return runResult;
    }

    // Keeps the replies of a run on the saved test message, and clears the marks about the earlier replies.
    private static AIPromptTemplatesDataStructure.TestMessage saveRunOnTestMessage(Id testMessageId, AIPromptTemplatesDataStructure.TryItResult result) {

        // [1] Load the test message
        AIPromptTestMessage__c testMessage = AIPromptTemplatesEditorService.findTestMessage(testMessageId);

        // [2] Say whether every run that was made got a reply
        Boolean isSavedRunFine = result.savedRun == null || result.savedRun.isSuccessful == true;
        Boolean areAllRunsFine = isSavedRunFine && result.editedRun.isSuccessful == true;

        // [3] Keep the replies and clear the marks
        testMessage.LastRunOn__c = Datetime.now();
        testMessage.LastRunStatus__c = areAllRunsFine ? AIAssistApplicationConstants.PROMPT_TEST_STATUS_PASSED : AIAssistApplicationConstants.PROMPT_TEST_STATUS_FAILED;
        testMessage.LastSavedReply__c = result.savedRun == null ? null : result.savedRun.replyText;
        testMessage.LastEditedReply__c = result.editedRun.replyText;
        testMessage.SavedVerdict__c = null;
        testMessage.EditedVerdict__c = null;
        Database.update(testMessage, AccessLevel.SYSTEM_MODE);

        return AIPromptTemplatesEditorService.buildTestMessage(testMessage);
    }

    // The saved template with the wording the model receives.
    private static AIPromptTemplate__c getSavedTemplate(Id templateId) {

        // [1] Query it
        List<AIPromptTemplate__c> templates = [SELECT Id, Name, DeveloperName__c, Version__c, MaxResponseLength__c, AISystemContext__c, AITone__c, AIPrompt__c, AIExclusionRules__c FROM AIPromptTemplate__c WHERE Id = :templateId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (templates.isEmpty()) throw new AIPromptTemplatesTryItServiceException(Label.AI_Prompts_Error_Not_Found);

        return templates[0];
    }

    // The model connection of an agent.
    private static AIModelConfiguration__c getModelConfiguration(Id modelConfigurationId) {

        // [1] Query it
        List<AIModelConfiguration__c> configurations = [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c FROM AIModelConfiguration__c WHERE Id = :modelConfigurationId WITH SYSTEM_MODE LIMIT 1];

        return configurations.isEmpty() ? null : configurations[0];
    }
}
