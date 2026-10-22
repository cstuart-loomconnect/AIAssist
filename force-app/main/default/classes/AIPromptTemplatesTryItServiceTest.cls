/*
Class Name: AIPromptTemplatesTryItServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplatesTryItService: a message is run with a template's saved and edited wording, and the replies are kept on a saved test message.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplatesTryItService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplatesTryItServiceTest {

    // testScenario1: A saved template is tried with an edit and a saved test message -> both wordings reply, and the replies and a passed status are kept on the test message with its marks cleared.
    // testScenario2: A template that is not saved is tried -> only the edited wording is run.
    // testScenario3: The model refuses every call -> neither run is successful, each shows the safe message, and the test message is marked failed.
    // testScenario4: A blank message, a message that is too long, no agent, and an agent with no model are tried -> each is refused with its own label.
    // testScenario5: A user with only the end user permission set tries a message -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a saved template with a test message that was marked, and an edit of the template
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIPromptTestMessage__c testMessage = new AIPromptTestMessage__c(AIPromptTemplate__c = template.Id, MessageBody__c = 'Will rates fall?', SavedVerdict__c = 'Worse', EditedVerdict__c = 'Better');
            insert testMessage;

            AIPromptTemplatesDataStructure.TemplateDetail detail = AIPromptTemplatesEditorService.getTemplateDetail(template.Id);
            detail.prompt = 'Answer in one line for {!Agent.Name}.';

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Run the saved message
            AIPromptTemplatesDataStructure.TryItResult result;

            Test.startTest();
                result = AIPromptTemplatesTryItService.runTryIt(detail, 'Will rates fall?', agent.Id, null, testMessage.Id);
            Test.stopTest();

            // [3] Read the test message back
            AIPromptTestMessage__c savedMessage = [SELECT LastRunOn__c, LastRunStatus__c, LastSavedReply__c, LastEditedReply__c, SavedVerdict__c, EditedVerdict__c FROM AIPromptTestMessage__c WHERE Id = :testMessage.Id];

            // [4] Check both runs and the saved message
            Assert.isTrue(result.savedRun.isSuccessful, 'The saved wording replied.');
            Assert.isTrue(result.editedRun.isSuccessful, 'The edited wording replied.');
            Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, result.editedRun.replyText, 'The reply is the model\'s.');
            Assert.areEqual(2, AIAssistTestProviderMock.callCount, 'The model was called once for each wording.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_TEST_STATUS_PASSED, savedMessage.LastRunStatus__c, 'The run passed.');
            Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, savedMessage.LastSavedReply__c, 'The saved reply is kept.');
            Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, savedMessage.LastEditedReply__c, 'The edited reply is kept.');
            Assert.isNotNull(savedMessage.LastRunOn__c, 'The time of the run is kept.');
            Assert.isNull(savedMessage.SavedVerdict__c, 'The old saved mark is cleared.');
            Assert.isNull(savedMessage.EditedVerdict__c, 'The old edited mark is cleared.');
            Assert.areEqual(testMessage.Id, result.testMessage.testMessageId, 'The updated message is returned.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and a template that is not saved
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIPromptTemplatesDataStructure.TemplateDetail detail = new AIPromptTemplatesDataStructure.TemplateDetail();
            detail.templateName = 'Draft';
            detail.prompt = 'Answer briefly.';

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Run a message that is not saved
            AIPromptTemplatesDataStructure.TryItResult result;

            Test.startTest();
                result = AIPromptTemplatesTryItService.runTryIt(detail, 'Hello', agent.Id, null, null);
            Test.stopTest();

            // [3] Check only the edited wording ran
            Assert.isNull(result.savedRun, 'There is no saved wording to run.');
            Assert.isTrue(result.editedRun.isSuccessful, 'The edited wording replied.');
            Assert.isNull(result.testMessage, 'No test message was updated.');
            Assert.areEqual(1, AIAssistTestProviderMock.callCount, 'The model was called once.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a saved template and a test message, and make the model refuse
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            AIPromptTestMessage__c testMessage = new AIPromptTestMessage__c(AIPromptTemplate__c = template.Id, MessageBody__c = 'Hello');
            insert testMessage;

            AIPromptTemplatesDataStructure.TemplateDetail detail = AIPromptTemplatesEditorService.getTemplateDetail(template.Id);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

            // [2] Run the message
            AIPromptTemplatesDataStructure.TryItResult result;

            Test.startTest();
                result = AIPromptTemplatesTryItService.runTryIt(detail, 'Hello', agent.Id, null, testMessage.Id);
            Test.stopTest();

            // [3] Read the test message back
            AIPromptTestMessage__c savedMessage = [SELECT LastRunStatus__c FROM AIPromptTestMessage__c WHERE Id = :testMessage.Id];

            // [4] Check both runs failed with the safe message
            Assert.isFalse(result.savedRun.isSuccessful, 'The saved run failed.');
            Assert.isFalse(result.editedRun.isSuccessful, 'The edited run failed.');
            Assert.areEqual(Label.AI_Prompts_Error_Run_Failed, result.editedRun.errorMessage, 'The message is the safe label, not the provider\'s text.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_TEST_STATUS_FAILED, savedMessage.LastRunStatus__c, 'The test message is marked failed.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a model and an agent with none
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIAgent__c noModelAgent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
            AIPromptTemplatesDataStructure.TemplateDetail detail = new AIPromptTemplatesDataStructure.TemplateDetail();
            List<String> refusals = new List<String>();

            // [2] Try each bad call
            Test.startTest();
                try { AIPromptTemplatesTryItService.runTryIt(detail, ' ', agent.Id, null, null); } catch (AIPromptTemplatesTryItService.AIPromptTemplatesTryItServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesTryItService.runTryIt(detail, 'x'.repeat(AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH + 1), agent.Id, null, null); } catch (AIPromptTemplatesTryItService.AIPromptTemplatesTryItServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesTryItService.runTryIt(detail, 'Hello', null, null, null); } catch (AIPromptTemplatesTryItService.AIPromptTemplatesTryItServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesTryItService.runTryIt(detail, 'Hello', noModelAgent.Id, null, null); } catch (AIPromptTemplatesTryItService.AIPromptTemplatesTryItServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each refusal
            Assert.areEqual(new List<String>{Label.AI_Prompts_Error_Message_Required, Label.AI_Prompts_Error_Message_Too_Long, Label.AI_Prompts_Error_Agent_Required, Label.AI_Prompts_Error_Agent_No_Model}, refusals, 'Each bad call shows its own label.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String refusal;

            // [2] Try a message as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {
                        AIPromptTemplatesTryItService.runTryIt(null, 'Hello', null, null, null);
                    } catch (Exception ex) {
                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the access label
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label is shown.');
        }
    }
}
