/*
Class Name: AIAgentWizardTryService

=================================================================
=================================================================

Description: Runs one message through the model, prompt template and persona of an AI Agent Wizard draft, for the Review step.

Step 1: Check the message and the model
Step 2: Build an agent that is never saved from the draft, and find the prompt template it would answer with
Step 3: Run the message the same way a chat turn does, with no data sources or workflow actions, and report the reply

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardTryService {

    public class AIAgentWizardTryServiceException extends Exception {}

    // Runs the message with the draft as it stands. Only the model, the prompt template and the persona are tried: no data sources or workflow actions are offered to the model.
    public static AIAgentWizardDataStructure.TryResult tryAgent(AIAgentWizardDataStructure.AgentDraft draft, String messageBody, Id recordId) {

        // [1] Refuse a user who may not use the tab, a missing draft and a message that cannot be sent
        AIAssistSettingsEditorService.requireManager();
        if (draft == null) throw new AIAgentWizardTryServiceException(Label.AI_Wizard_Error_Draft_Required);
        if (String.isBlank(messageBody)) throw new AIAgentWizardTryServiceException(Label.AI_Wizard_Error_Message_Required);
        if (messageBody.length() > AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH) throw new AIAgentWizardTryServiceException(Label.AI_Wizard_Error_Message_Too_Long);

        // [2] Load the model of the draft
        Id modelId = draft.modelConfigurationId;
        List<AIModelConfiguration__c> models = [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];
        if (models.isEmpty()) throw new AIAgentWizardTryServiceException(Label.AI_Wizard_Error_No_Model);

        // [3] Build the agent the draft describes. It is never saved.
        AIAgent__c agent = new AIAgent__c(Name = draft.agentName, DeveloperName__c = draft.developerName, AIAgentPersona__c = draft.persona, ObjectApiNames__c = draft.objectApiNames == null ? null : String.join(draft.objectApiNames, ','), AIModelConfiguration__c = modelId, TokenTrackingMethod__c = draft.tokenTrackingMethod, MaxToolCallingIterations__c = draft.maxToolCallingIterations);

        // [4] Fill the merge fields of the prompt template from the agent, the user and the record
        Map<String, String> valueByToken = AIPromptMergeFieldService.buildValues(agent, AIPromptTemplatesEditorService.getFirstObjectApiName(agent), recordId, true);
        AIPromptTemplate__c promptTemplate = AIPromptMergeFieldService.buildFilledTemplate(getPromptTemplate(draft.promptTemplateId, draft.agentName), valueByToken);

        // [5] Run the message and report the reply
        AIPromptTemplatesDataStructure.RunResult runResult = AIPromptTemplatesTryItService.runMessage(agent, models[0], promptTemplate, messageBody);

        AIAgentWizardDataStructure.TryResult result = new AIAgentWizardDataStructure.TryResult();
        result.isSuccessful = runResult.isSuccessful;
        result.replyText = runResult.replyText;
        result.latencyMilliseconds = runResult.latencyMilliseconds;
        result.totalTokens = runResult.totalTokens;
        result.errorMessage = runResult.errorMessage;

        return result;
    }

    // The template the agent would answer with: the one chosen when it is active, otherwise the default, otherwise a plain prompt that is never saved.
    private static AIPromptTemplate__c getPromptTemplate(Id promptTemplateId, String agentName) {

        // [1] Read the chosen template and the default
        AIPromptTemplate__c chosenTemplate = null;
        AIPromptTemplate__c defaultTemplate = null;

        for (AIPromptTemplate__c promptTemplate : [SELECT Id, Name, DeveloperName__c, Version__c, MaxResponseLength__c, AISystemContext__c, AITone__c, AIPrompt__c, AIExclusionRules__c, IsDefault__c FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND (Id = :promptTemplateId OR IsDefault__c = TRUE) WITH SYSTEM_MODE LIMIT 10]) {

            if (promptTemplate.Id == promptTemplateId) chosenTemplate = promptTemplate;
            else defaultTemplate = promptTemplate;
        }

        // [2] Fall back in order
        if (chosenTemplate != null) return chosenTemplate;
        if (defaultTemplate != null) return defaultTemplate;

        return new AIPromptTemplate__c(Name = agentName, AIPrompt__c = Label.AI_Wizard_Try_Default_Prompt);
    }
}
