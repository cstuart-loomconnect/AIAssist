/*
Class Name: AIPromptTemplatesControllerTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplatesController: each method the AI Prompt Templates tab calls returns what the service returns, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplatesController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplatesControllerTest {

    // testScenario1: A manager calls every method the tab calls -> each returns what the service returns.
    // testScenario2: A manager reads a template that is gone, and sends moves that cannot be read -> the first shows its own label and the second the generic label with one platform log.
    // testScenario3: A user without the Manage Settings permission calls a read and a save -> both show the access label.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, two templates and a draft of the first
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, true);
            templates[1].DeveloperName__c = 'Second';
            update templates[1];

            AIPromptTemplatesDataStructure.TemplateDetail detail = AIPromptTemplatesEditorService.getTemplateDetail(templates[0].Id);
            detail.developerName = 'First';
            detail.prompt = 'Answer very briefly.';
            Map<String, Object> detailValues = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(detail));
            AIPromptTestMessage__c savedMessage = new AIPromptTestMessage__c(AIPromptTemplate__c = templates[0].Id, MessageBody__c = 'Saved');
            insert savedMessage;
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            AIPromptTemplatesDataStructure.ArchiveMove move = new AIPromptTemplatesDataStructure.ArchiveMove();
            move.agentId = agent.Id;
            move.newTemplateId = templates[1].Id;

            // [2] Call each method the tab calls
            Test.startTest();
                List<AIPromptTemplatesDataStructure.TemplateRow> rows = AIPromptTemplatesController.getTemplateRows();
                AIPromptTemplatesDataStructure.TemplateDetail readDetail = AIPromptTemplatesController.getTemplateDetail(templates[0].Id);
                List<AIPromptTemplatesDataStructure.MergeFieldOption> mergeFields = AIPromptTemplatesController.getMergeFieldOptions();
                List<AIPromptTemplatesDataStructure.AgentOption> agentOptions = AIPromptTemplatesController.getAgentOptions();
                AIPromptTemplatesDataStructure.PreviewResult preview = AIPromptTemplatesController.getPreview(detailValues, agent.Id, null);
                AIPromptTemplatesDataStructure.PublishImpact impact = AIPromptTemplatesController.getPublishImpact(detailValues);
                List<AIPromptTemplatesDataStructure.AgentUse> agentUses = AIPromptTemplatesController.getAgentUses(templates[0].Id);
                AIPromptTemplatesDataStructure.ArchiveOptions archiveOptions = AIPromptTemplatesController.getArchiveOptions(templates[0].Id);
                AIPromptTemplatesDataStructure.TryItResult tryItResult = AIPromptTemplatesController.runTryIt(detailValues, 'Hello', agent.Id, null, savedMessage.Id);
                AIPromptTemplatesDataStructure.TestMessage testMessage = AIPromptTemplatesController.saveTestMessage(templates[0].Id, 'Hello');
                List<AIPromptTemplatesDataStructure.TestMessage> testMessages = AIPromptTemplatesController.getTestMessages(templates[0].Id);
                AIPromptTemplatesDataStructure.TestMessage marked = AIPromptTemplatesController.setVerdict(testMessage.testMessageId, 'edited', 'Better');
                AIPromptTemplatesController.deleteTestMessage(testMessage.testMessageId);
                AIPromptTemplatesDataStructure.SaveResult saveResult = AIPromptTemplatesController.saveTemplate(detailValues);
                AIPromptTemplatesController.setDefaultTemplate(templates[1].Id);
                AIPromptTemplatesController.archiveTemplate(templates[0].Id, new List<Map<String, Object>>{ (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(move)) });
                AIPromptTemplatesController.activateTemplate(templates[0].Id);
            Test.stopTest();

            // [3] Check each answer
            Assert.areEqual(2, rows.size(), 'The list holds both templates.');
            Assert.areEqual(templates[0].Id, readDetail.templateId, 'The detail is the template.');
            Assert.areEqual(6, mergeFields.size(), 'Six merge fields are offered.');
            Assert.areEqual(1, agentOptions.size(), 'The agent is offered.');
            Assert.isFalse(preview.sections.isEmpty(), 'The preview has sections.');
            Assert.areEqual(readDetail.version + 1, impact.nextVersion, 'The change raises the version.');
            Assert.areEqual(1, agentUses.size(), 'The agent that has the template is listed.');
            Assert.areEqual(1, archiveOptions.agentUses.size(), 'The archive dialog lists the agent.');
            Assert.areEqual(2, testMessages.size(), 'Both saved test messages are listed.');
            Assert.isTrue(tryItResult.editedRun.isSuccessful, 'The message ran.');
            Assert.areEqual('Better', marked.editedVerdict, 'The reply was marked.');
            Assert.isTrue(saveResult.isSaved, 'The save works.');
            Assert.areEqual('First', saveResult.detail.developerName, 'The saved template is returned.');
            Assert.isTrue([SELECT IsDefault__c FROM AIPromptTemplate__c WHERE Id = :templates[1].Id].IsDefault__c, 'The second template became the default.');
            Assert.areEqual(templates[1].Id, [SELECT AIPromptTemplate__c FROM AIAgent__c WHERE Id = :agent.Id].AIPromptTemplate__c, 'The agent moved when its template was archived.');
            Assert.isTrue([SELECT IsActive__c FROM AIPromptTemplate__c WHERE Id = :templates[0].Id].IsActive__c, 'The template was brought back.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Prepare moves that cannot be read
            String readRefusal;
            String movesRefusal;

            // [2] Try both calls
            Test.startTest();
                try {
                    AIPromptTemplatesController.getTemplateDetail(UserInfo.getUserId());
                } catch (AuraHandledException ex) {
                    readRefusal = ex.getMessage();
                }

                try {
                    AIPromptTemplatesController.archiveTemplate(UserInfo.getUserId(), new List<Map<String, Object>>{ new Map<String, Object>{'agentId' => 'not an id'} });
                } catch (AuraHandledException ex) {
                    movesRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Read the logs back
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the labels and the one log
            Assert.areEqual(Label.AI_Prompts_Error_Not_Found, readRefusal, 'A template that is gone shows its own label.');
            Assert.areEqual(Label.AI_Error_Generic, movesRefusal, 'An unexpected failure shows the generic label.');
            Assert.areEqual(1, logs.size(), 'The unexpected failure is logged once.');
            Assert.areEqual('archiveTemplate', logs[0].MethodName__c, 'The log names the method.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            List<String> refusals = new List<String>();

            // [2] Call a read and a save as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try {
                        AIPromptTemplatesController.getTemplateRows();
                    } catch (AuraHandledException ex) {
                        refusals.add(ex.getMessage());
                    }

                    try {
                        AIPromptTemplatesController.saveTemplate(new Map<String, Object>());
                    } catch (AuraHandledException ex) {
                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check both were refused with the access label
            Assert.areEqual(new List<String>{Label.AI_Settings_Error_Access, Label.AI_Settings_Error_Access}, refusals, 'Both calls show the access label.');
        }
    }
}
