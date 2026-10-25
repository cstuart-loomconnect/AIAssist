/*
Class Name: AIModelsControllerTest

=================================================================
=================================================================

Description: Testing utility for AIModelsController: the Apex calls of the AI Agent Models tab.

=================================================================
=================================================================
Applicable Classes:

AIModelsController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIModelsControllerTest {

    // testScenario1: A manager reads the page, tests, saves and switches a model off through the controller -> each call returns what the service returns.
    // testScenario2: A user without the Manage Settings permission calls the controller -> the access label is shown, and nothing is logged for it.
    // testScenario3: A manager asks for a model that does not exist -> the not found label is shown.
    // testScenario4: A save fails on the platform because the name is too long -> the generic label is shown and the error is logged once.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {

            // [1] Build a model that is saved, one that is not, and a provider that answers
            AIModelConfiguration__c savedModel = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, true);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Call each method
            Test.startTest();
                AIModelsDataStructure.ModelsPage page = AIModelsController.getModelsPage();
                AIModelsDataStructure.TestResult testResult = AIModelsController.testConnection(view);
                AIModelsDataStructure.SaveResult saveResult = AIModelsController.saveModel(view);
                AIModelsDataStructure.SwitchOffOptions options = AIModelsController.getSwitchOffOptions(savedModel.Id);
                List<AIModelsDataStructure.ModelView> views = AIModelsController.switchOffModel(savedModel.Id, new List<AIModelsDataStructure.SwitchOffMove>());
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(1, page.models.size(), 'The page should list the saved model.');
            Assert.isTrue(testResult.isSuccessful, 'The test should pass.');
            Assert.isTrue(saveResult.isSaved, 'The model should be saved.');
            Assert.areEqual(0, options.agentUses.size(), 'No agent uses the model.');
            Assert.areEqual(2, views.size(), 'Both models should be returned.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {

            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String refusal;

            // [2] Call the controller as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIModelsController.getModelsPage(); } catch (AuraHandledException ex) { refusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label should be shown.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'A refusal is not an error, so nothing should be logged.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {

            // [1] Build the Id of a model that was never saved
            Id missingId = AIModelConfiguration__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            String refusal;

            // [2] Ask for its switch off options
            Test.startTest();
                try { AIModelsController.getSwitchOffOptions(missingId); } catch (AuraHandledException ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Models_Error_Not_Found, refusal, 'The not found label should be shown.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {

            // [1] Build a model whose name is longer than the field allows, which the platform refuses on save
            AIModelsDataStructure.ModelView view = AIAssistTestDataFactory.createAIModelView(AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC, false);
            view.modelName = 'x'.repeat(300);
            String refusal;

            // [2] Save it
            Test.startTest();
                try { AIModelsController.saveModel(view); } catch (AuraHandledException ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Read the log
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Generic, refusal, 'The generic label should be shown.');
            Assert.areEqual(1, logs.size(), 'The error should be logged once.');
            Assert.areEqual('AIModelsController', logs[0].ClassName__c, 'The log should name the controller.');
            Assert.areEqual('saveModel', logs[0].MethodName__c, 'The log should name the method.');
        }
    }
}
