/*
Class Name: AIToolsControllerTest

=================================================================
=================================================================

Description: Testing utility for AIToolsController: each method the AI Tools tab calls returns what the service returns, and a refusal reaches the tab as a readable message.

=================================================================
=================================================================
Applicable Classes:

AIToolsController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsControllerTest {

    // testScenario1: A manager calls every method the tab calls -> each returns what the service returns.
    // testScenario2: A manager saves nothing, reads a data source that does not exist and asks for the fields of no object -> each refusal reaches the tab as its own label.
    // testScenario3: A user without the Manage Settings permission calls a read and a save -> both show the access label.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a data source and an account
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id, Name FROM Account WHERE Id = :recordId', true)[0];
            AIToolsDataStructure.TestRequest request = new AIToolsDataStructure.TestRequest();
            request.recordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;

            // [2] Call each method the tab calls
            Test.startTest();
                List<AIToolsDataStructure.DataSourceRow> rows = AIToolsController.getDataSourceRows();
                AIToolsDataStructure.DataSourceDetail detail = AIToolsController.getDataSourceDetail(dataSource.Id);
                List<AIToolsDataStructure.AgentUse> agents = AIToolsController.getAgentUses(dataSource.Id);
                List<AIToolsDataStructure.ObjectOption> objects = AIToolsController.getObjectOptions();
                List<AIToolsDataStructure.FieldOption> fields = AIToolsController.getFieldOptions('Account');
                List<AIToolsDataStructure.ApexClassOption> classes = AIToolsController.getApexClassOptions();
                List<AIAssistSettingsDataStructure.OwnerOption> users = AIToolsController.findUsers('Assist Tester');
                AIToolsDataStructure.SoqlValidation validation = AIToolsController.validateSoql(detail.soqlTemplate, true, 20);
                detail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
                AIToolsDataStructure.TestResult testResult = AIToolsController.runTest((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(detail)), (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(request)));
                detail.developerName = 'ChangedByController';
                detail.description = 'Reads accounts.';
                AIToolsDataStructure.SaveResult saveResult = AIToolsController.saveDataSource((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(detail)), (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(request)));
            Test.stopTest();

            // [3] Check each answer
            Assert.areEqual(1, rows.size(), 'The list holds the data source.');
            Assert.areEqual(dataSource.Id, detail.dataSourceId, 'The detail is the data source.');
            Assert.isTrue(agents.isEmpty(), 'No agent uses it.');
            Assert.isFalse(objects.isEmpty(), 'Objects are offered.');
            Assert.isFalse(fields.isEmpty(), 'Fields are offered.');
            Assert.isNotNull(classes, 'The Apex classes are returned.');
            Assert.isFalse(users.isEmpty(), 'Users are found.');
            Assert.isTrue(validation.isValid, 'The query is valid.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, testResult.status, 'The test passes.');
            Assert.isTrue(saveResult.isSaved, 'The save works.');
            Assert.areEqual('ChangedByController', saveResult.row.developerName, 'The saved row is returned.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a data source with nothing in it, and ask for a missing data source
            AIToolsDataStructure.DataSourceDetail emptyDetail = new AIToolsDataStructure.DataSourceDetail();
            String saveRefusal;
            String readRefusal;
            String fieldRefusal;

            // [2] Try each call and keep each message
            Test.startTest();
                try {

                    AIToolsController.saveDataSource((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(emptyDetail)), null);
                } catch (AuraHandledException ex) {

                    saveRefusal = ex.getMessage();
                }

                try {

                    AIToolsController.getDataSourceDetail(UserInfo.getUserId());
                } catch (AuraHandledException ex) {

                    readRefusal = ex.getMessage();
                }

                try {

                    AIToolsController.getFieldOptions(null);
                } catch (AuraHandledException ex) {

                    fieldRefusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the tab gets a readable message for each refusal
            Assert.areEqual(Label.AI_Tools_Error_Name_Required, saveRefusal, 'A refusal reaches the tab as its own label.');
            Assert.areEqual(Label.AI_Tools_Error_Not_Found, readRefusal, 'A data source that is gone reaches the tab as its own label.');
            Assert.areEqual(Label.AI_Tools_Error_Object, fieldRefusal, 'A missing object reaches the tab as its own label.');
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

                        AIToolsController.getDataSourceRows();
                    } catch (AuraHandledException ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsController.saveDataSource((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new AIToolsDataStructure.DataSourceDetail())), null);
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
