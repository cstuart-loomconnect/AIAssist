/*
Class Name: AIToolsSkillTestService

=================================================================
=================================================================

Description: Runs one question through an existing agent's model with the skill the AI Tools wizard is editing offered on its own, for the Test step. The skill does not need to be saved, active, or given to any agent: its data sources are allowed for this one test only. Workflow actions are only ever suggested by the model, so nothing is changed and nothing needs rolling back.

Step 1: Check the request, and load the agent and its model
Step 2: Build the skill as it is in the wizard, with its active tools, and the chat the question is asked in
Step 3: Run the question the same way a chat turn does, offering only this skill
Step 4: Report whether the model picked the skill, the reply and every step, and keep the result on a saved skill

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsSkillTestService {

    public class AIToolsSkillTestServiceException extends Exception {}

    // Runs the test and returns how it ended. A skill with a saved Id keeps the result and the time on its record.
    public static AIToolsSkillDataStructure.TestResult runTest(AIToolsSkillDataStructure.SkillDetail detail, AIToolsSkillDataStructure.TestRequest testRequest) {

        // [1] Refuse a user who may not use the tab, and a request that cannot be run
        AIAssistSettingsEditorService.requireManager();
        if (detail == null || String.isBlank(detail.developerName) || String.isBlank(detail.description)) throw new AIToolsSkillTestServiceException(Label.AI_ToolsSk_Error_Not_Ready);
        if (testRequest == null || testRequest.agentId == null) throw new AIToolsSkillTestServiceException(Label.AI_ToolsSk_Error_Agent_Required);
        if (String.isBlank(testRequest.question)) throw new AIToolsSkillTestServiceException(Label.AI_ToolsSk_Error_Question_Required);
        if (testRequest.question.length() > AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH) throw new AIToolsSkillTestServiceException(Label.AI_Wizard_Error_Message_Too_Long);

        // [2] Load the agent and its model
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, AIAgentPersona__c, IsActive__c, AIModelConfiguration__c, MaxToolCallingIterations__c, TokenTrackingMethod__c FROM AIAgent__c WHERE Id = :testRequest.agentId WITH SYSTEM_MODE LIMIT 1];
        if (agents.isEmpty()) throw new AIToolsSkillTestServiceException(Label.AI_ToolsSk_Error_Agent_Required);

        AIAgent__c agent = agents[0];
        Id modelId = agent.AIModelConfiguration__c;
        List<AIModelConfiguration__c> models = [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];
        if (models.isEmpty()) throw new AIToolsSkillTestServiceException(Label.AI_ToolsSk_Error_No_Model);

        // [3] Load the active tools of the skill in the order the wizard has them
        Map<Id, Integer> orderByRecordId = new Map<Id, Integer>();

        for (AIToolsSkillDataStructure.SkillTool tool : detail.tools == null ? new List<AIToolsSkillDataStructure.SkillTool>() : detail.tools) {

            if (tool?.recordId != null && !orderByRecordId.containsKey(tool.recordId)) orderByRecordId.put(tool.recordId, orderByRecordId.size());
        }

        Set<Id> toolRecordIds = orderByRecordId.keySet();
        AISkillService.SkillBundle skillBundle = new AISkillService.SkillBundle();
        skillBundle.skill = new AISkill__c(Id = detail.skillId, Name = String.isBlank(detail.skillName) ? detail.developerName : detail.skillName, DeveloperName__c = detail.developerName.trim(), Description__c = detail.description, Instructions__c = detail.instructions);
        String boundObjectName = null;

        for (AIDataSource__c dataSource : [SELECT Id, DeveloperName__c, Description__c, OutputDescription__c, InputSchema__c, MaxRows__c, TargetObject__c, BindingType__c FROM AIDataSource__c WHERE Id IN :toolRecordIds AND IsActive__c = TRUE WITH SYSTEM_MODE]) {

            skillBundle.dataSources.add(dataSource);
            if (dataSource.BindingType__c == AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND && String.isNotBlank(dataSource.TargetObject__c) && boundObjectName == null) boundObjectName = dataSource.TargetObject__c;
        }

        for (AIWorkflowAction__c action : [SELECT Id, DeveloperName__c, Description__c, OutputDescription__c, InputSchema__c FROM AIWorkflowAction__c WHERE Id IN :toolRecordIds AND IsActive__c = TRUE WITH SYSTEM_MODE]) {

            skillBundle.workflowActions.add(action);
        }

        // [4] A bound skill runs against one open record, so it needs one to test with
        if (boundObjectName != null && testRequest.recordId == null) throw new AIToolsSkillTestServiceException(String.format(Label.AI_ToolsSk_Error_Record_Required, new List<String>{boundObjectName}));

        // [5] Build the chat the question is asked in. It is never saved.
        String relatedObjectName = testRequest.recordId == null ? null : testRequest.recordId.getSObjectType().getDescribe().getName();
        AIConversation__c conversation = new AIConversation__c(AIAgent__c = agent.Id, RelatedRecordId__c = testRequest.recordId == null ? null : String.valueOf(testRequest.recordId), RelatedObjectAPIName__c = relatedObjectName);
        AIConversationMessage__c userMessage = new AIConversationMessage__c(Sender__c = AIAssistApplicationConstants.SENDER_USER, MessageBody__c = testRequest.question);
        AIPromptTemplate__c promptTemplate = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null).promptTemplate;

        if (promptTemplate != null) promptTemplate = AIPromptMergeFieldService.buildFilledTemplate(promptTemplate, AIPromptMergeFieldService.buildValues(agent, relatedObjectName, testRequest.recordId, true));

        // [6] Allow the skill's data sources for this test only, and run the question with this skill alone offered
        AIExecutionStepTracker trace = new AIExecutionStepTracker(null, null, false, false);
        AIAgentManager.AgentResult agentResult;

        for (AIDataSource__c dataSource : skillBundle.dataSources) AIDataSourceDispatcher.previewGrantedDataSourceIds.add(dataSource.Id);

        try {

            agentResult = AIAgentManager.executeAiMessage(agent, models[0], promptTemplate, null, conversation, new List<AIConversationMessage__c>{userMessage}, null, null, new List<AISkillService.SkillBundle>{skillBundle}, 1, trace);

        } finally {

            AIDataSourceDispatcher.previewGrantedDataSourceIds.clear();
        }

        // [7] Say how it ended: picked and answered, answered without the skill, or failed
        AIToolsSkillDataStructure.TestResult result = new AIToolsSkillDataStructure.TestResult();
        Boolean isAnswered = agentResult.isSuccessful && String.isNotBlank(agentResult.replyText);
        Boolean isPicked = String.isNotBlank(agentResult.selectedSkillName);
        Boolean hasFailedStep = false;

        for (AIExecutionStepTracker.StepEntry stepEntry : trace.steps) {

            AIToolsSkillDataStructure.TestStep testStep = new AIToolsSkillDataStructure.TestStep();
            testStep.stepType = stepEntry.stepType;
            testStep.detail = stepEntry.stepDetail;
            testStep.isSuccess = stepEntry.isSuccess != false;
            result.steps.add(testStep);

            if (stepEntry.isSuccess == false) hasFailedStep = true;
        }

        if (!isAnswered) result.status = AIAssistApplicationConstants.SKILL_TEST_STATUS_FAILED;
        else if (!isPicked) result.status = AIAssistApplicationConstants.SKILL_TEST_STATUS_NOT_PICKED;
        else result.status = hasFailedStep ? AIAssistApplicationConstants.SKILL_TEST_STATUS_FAILED : AIAssistApplicationConstants.SKILL_TEST_STATUS_PASSED;

        if (!isAnswered) result.message = Label.AI_ToolsSk_Error_Run_Failed;
        else if (!isPicked) result.message = Label.AI_ToolsSk_Test_Not_Picked;
        else if (hasFailedStep) result.message = Label.AI_ToolsSk_Test_Step_Failed;

        result.replyText = agentResult.replyText;
        result.elapsedMilliseconds = agentResult.latencyMilliseconds;
        result.totalTokens = agentResult.totalTokensUsed;

        for (AIWorkflowAction__c action : skillBundle.workflowActions) {

            if (action.Id == agentResult.suggestedWorkflowActionId) result.suggestedActionName = AIChatDataStructure.humanise(action.DeveloperName__c);
        }

        // [8] Keep the result on a saved skill, after every callout is done
        if (detail.skillId != null) Database.update(new AISkill__c(Id = detail.skillId, LastTestStatus__c = result.status, LastTestedOn__c = System.now()), AccessLevel.SYSTEM_MODE);

        return result;
    }
}
