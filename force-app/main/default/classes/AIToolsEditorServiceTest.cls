/*
Class Name: AIToolsEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIToolsEditorService: listing, offering, checking, testing and saving the data sources the AI Tools tab edits.

=================================================================
=================================================================
Applicable Classes:

AIToolsEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIToolsEditorServiceTest {

    // testScenario1: A manager reads the list, one data source and its agents -> the agent counts and fields are right.
    // testScenario2: A manager reads the objects, the fields of Account and the fields of a missing object -> Account is offered, Id is left out, and the missing object is refused.
    // testScenario3: A manager reads the Apex classes, checks a query and searches users -> the stub class is listed with its described inputs.
    // testScenario4: A manager saves a SOQL data source with a test and an Apex data source without -> each is saved with the right fields and test result.
    // testScenario5: A manager saves a data source with no name, a bad API name, a broken query, a taken API name and no class -> each is refused.
    // testScenario6: A manager edits a data source that an agent uses -> it is refused untested, not saved when the test fails, and saved when the test passes.
    // testScenario7: A user without the Manage Settings permission calls every method -> each is refused with the access label.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two data sources and switch one on for an active agent
            List<AIDataSource__c> dataSources = AIAssistTestDataFactory.createAIDataSources(2, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true);
            AIModelConfiguration__c modelConfiguration = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, modelConfiguration.Id, true)[0];
            AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{dataSources[0]}, true);

            // [2] Read the list, one detail and the agents of each
            Test.startTest();
                List<AIToolsDataStructure.DataSourceRow> rows = AIToolsEditorService.getDataSourceRows();
                AIToolsDataStructure.DataSourceDetail detail = AIToolsEditorService.getDataSourceDetail(dataSources[0].Id);
                List<AIToolsDataStructure.AgentUse> usedAgents = AIToolsEditorService.getAgentUses(dataSources[0].Id);
                List<AIToolsDataStructure.AgentUse> unusedAgents = AIToolsEditorService.getAgentUses(dataSources[1].Id);
            Test.stopTest();

            // [3] Count the agents of each row
            Map<Id, Integer> agentCountById = new Map<Id, Integer>();

            for (AIToolsDataStructure.DataSourceRow row : rows) agentCountById.put(row.dataSourceId, row.agentCount);

            // [4] Check the list, the detail and the agents
            Assert.areEqual(1, agentCountById.get(dataSources[0].Id), 'The data source in use counts its agent.');
            Assert.areEqual(0, agentCountById.get(dataSources[1].Id), 'The data source not in use counts none.');
            Assert.areEqual(dataSources[0].SourceName__c, detail.sourceName, 'The detail holds the name.');
            Assert.areEqual('SELECT Id FROM Account', detail.soqlTemplate, 'The detail holds the query.');
            Assert.areEqual(1, detail.agentCount, 'The detail holds the agent count.');
            Assert.areEqual(agent.Id, usedAgents[0].agentId, 'The agent is listed.');
            Assert.isTrue(unusedAgents.isEmpty(), 'A data source not in use has no agents.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Name an object that does not exist
            String missingObject = 'NoSuchObject__c';
            String refusal;

            // [2] Read the objects and the fields of Account, and ask for the fields of a missing object
            Test.startTest();
                List<AIToolsDataStructure.ObjectOption> objects = AIToolsEditorService.getObjectOptions();
                List<AIToolsDataStructure.FieldOption> fields = AIToolsEditorService.getFieldOptions('Account');
                try {

                    AIToolsEditorService.getFieldOptions(missingObject);
                } catch (Exception ex) {

                    refusal = ex.getMessage();
                }
            Test.stopTest();

            // [3] Collect what came back
            Set<String> objectNames = new Set<String>();
            Map<String, AIToolsDataStructure.FieldOption> fieldByName = new Map<String, AIToolsDataStructure.FieldOption>();

            for (AIToolsDataStructure.ObjectOption option : objects) objectNames.add(option.apiName);

            for (AIToolsDataStructure.FieldOption option : fields) fieldByName.put(option.apiName, option);

            // [4] Check the lists
            Assert.isTrue(objectNames.contains('Account'), 'Account can be queried.');
            Assert.isTrue(fieldByName.containsKey('Name'), 'The name field is offered.');
            Assert.isFalse(fieldByName.containsKey('Id'), 'Id is left out because every query selects it.');
            Assert.areEqual('User', fieldByName.get('OwnerId').referenceTo, 'A lookup says which object it points to.');
            Assert.areEqual(Label.AI_Tools_Error_Object, refusal, 'A missing object is refused.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Check an Apex data source stub is findable
            String stubName = 'AIDataSourceTestStub';

            // [2] Read the Apex classes, check a query, and search users
            Test.startTest();
                List<AIToolsDataStructure.ApexClassOption> classes = AIToolsEditorService.getApexClassOptions();
                AIToolsDataStructure.SoqlValidation validation = AIToolsEditorService.validateSoql('SELECT Id FROM Account LIMIT 5', false, 20);
                List<AIAssistSettingsDataStructure.OwnerOption> users = AIToolsEditorService.findUsers('Assist Tester');
            Test.stopTest();

            // [3] Find the stub among the classes
            AIToolsDataStructure.ApexClassOption stubOption;

            for (AIToolsDataStructure.ApexClassOption option : classes) {

                if (option.className == stubName) stubOption = option;
            }

            // [4] Check the stub is listed with the inputs it describes
            Assert.isNotNull(stubOption, 'A class that implements the executor is listed.');
            Assert.areEqual('recordId, includeCommitments', stubOption.declaredInputNames, 'The inputs the class describes are listed by name.');
            Assert.isNotNull(stubOption.declaredInputSchema, 'The schema the class returned is kept.');
            Assert.isTrue(validation.isValid, 'The query is checked.');
            Assert.isFalse(users.isEmpty(), 'The user search finds the test user.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a new SOQL data source and a request that tests it
            AIToolsDataStructure.DataSourceDetail detail = new AIToolsDataStructure.DataSourceDetail();
            detail.sourceName = 'Open opportunities';
            detail.developerName = 'OpenOpportunities';
            detail.description = 'Lists the open opportunities.';
            detail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            detail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            detail.soqlTemplate = 'SELECT Id, Name FROM Opportunity LIMIT 20';
            detail.maxRows = 20;
            detail.isActive = true;

            // [2] Save it with a test, and save an Apex data source with none
            Test.startTest();
                AIToolsDataStructure.SaveResult soqlResult = AIToolsEditorService.saveDataSource(detail, new AIToolsDataStructure.TestRequest());
                AIToolsDataStructure.DataSourceDetail apexDetail = new AIToolsDataStructure.DataSourceDetail();
                apexDetail.sourceName = 'Stub';
                apexDetail.developerName = 'Stub';
                apexDetail.description = 'A stub.';
                apexDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
                apexDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
                apexDetail.apexClassName = 'AIDataSourceTestStub';
                apexDetail.targetObject = 'FactFind__c';
                apexDetail.isActive = false;
                AIToolsDataStructure.SaveResult apexResult = AIToolsEditorService.saveDataSource(apexDetail, null);
            Test.stopTest();

            // [3] Read both back
            AIDataSource__c soqlRecord = [SELECT SourceType__c, TargetObject__c, SOQLTemplate__c, ApexClassName__c, LastTestStatus__c, LastTestedOn__c FROM AIDataSource__c WHERE Id = :soqlResult.row.dataSourceId];
            AIDataSource__c apexRecord = [SELECT SourceType__c, TargetObject__c, SOQLTemplate__c, ApexClassName__c, LastTestStatus__c, IsActive__c FROM AIDataSource__c WHERE Id = :apexResult.row.dataSourceId];

            // [4] Check what was saved
            Assert.isTrue(soqlResult.isSaved, 'The SOQL data source is saved.');
            Assert.areEqual('Opportunity', soqlRecord.TargetObject__c, 'The object is read from the query.');
            Assert.isNull(soqlRecord.ApexClassName__c, 'A SOQL data source holds no class.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, soqlRecord.LastTestStatus__c, 'The test result is kept.');
            Assert.isNotNull(soqlRecord.LastTestedOn__c, 'The test time is kept.');
            Assert.isTrue(apexResult.isSaved, 'The Apex data source is saved.');
            Assert.areEqual('AIDataSourceTestStub', apexRecord.ApexClassName__c, 'The class is kept.');
            Assert.areEqual('FactFind__c', apexRecord.TargetObject__c, 'The object the class returns is kept.');
            Assert.isNull(apexRecord.SOQLTemplate__c, 'An Apex data source holds no query.');
            Assert.isNull(apexRecord.LastTestStatus__c, 'A data source saved with no test has no result.');
            Assert.isFalse(apexRecord.IsActive__c, 'The active switch is kept.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a data source that is missing things, one with a bad API name, one with a query that has errors and one with a name that is taken
            AIDataSource__c existing = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            AIToolsDataStructure.DataSourceDetail noName = new AIToolsDataStructure.DataSourceDetail();
            AIToolsDataStructure.DataSourceDetail badApiName = new AIToolsDataStructure.DataSourceDetail();
            badApiName.sourceName = 'A';
            badApiName.description = 'A';
            badApiName.developerName = 'has space';
            AIToolsDataStructure.DataSourceDetail brokenQuery = new AIToolsDataStructure.DataSourceDetail();
            brokenQuery.sourceName = 'B';
            brokenQuery.description = 'B';
            brokenQuery.developerName = 'BrokenQuery';
            brokenQuery.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            brokenQuery.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            brokenQuery.soqlTemplate = 'SELECT Id, Nope FROM Account LIMIT 5';
            AIToolsDataStructure.DataSourceDetail taken = new AIToolsDataStructure.DataSourceDetail();
            taken.sourceName = 'C';
            taken.description = 'C';
            taken.developerName = existing.DeveloperName__c;
            taken.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
            taken.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            taken.apexClassName = 'AIDataSourceTestStub';
            AIToolsDataStructure.DataSourceDetail noClass = new AIToolsDataStructure.DataSourceDetail();
            noClass.sourceName = 'D';
            noClass.description = 'D';
            noClass.developerName = 'NoClass';
            noClass.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
            List<String> refusals = new List<String>();

            // [2] Try each save and keep each message
            Test.startTest();
                for (AIToolsDataStructure.DataSourceDetail detail : new List<AIToolsDataStructure.DataSourceDetail>{noName, badApiName, brokenQuery, taken, noClass}) {

                    try {

                        AIToolsEditorService.saveDataSource(detail, null);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check each was refused with its own message
            Assert.areEqual(5, refusals.size(), 'Every bad save is refused.');
            Assert.areEqual(Label.AI_Tools_Error_Name_Required, refusals[0], 'A data source with no name is refused.');
            Assert.areEqual(Label.AI_Tools_Error_Developer_Name, refusals[1], 'A bad API name is refused.');
            Assert.areEqual(Label.AI_Tools_Error_Query_Invalid, refusals[2], 'A query with errors is refused.');
            Assert.isTrue(refusals[3].containsIgnoreCase('duplicate'), 'An API name that is taken is refused.');
            Assert.areEqual(Label.AI_Tools_Error_Apex_Class, refusals[4], 'An Apex data source with no class is refused.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Switch a data source on for an active agent, and build an edit that cannot run
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account LIMIT 5', true)[0];
            AIModelConfiguration__c modelConfiguration = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, modelConfiguration.Id, true)[0];
            AIAssistTestDataFactory.createAIAgentDataSources(agent.Id, new List<AIDataSource__c>{dataSource}, true);
            AIToolsDataStructure.DataSourceDetail edit = AIToolsEditorService.getDataSourceDetail(dataSource.Id);
            edit.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            edit.description = 'Reads accounts.';
            String untestedRefusal;

            // [2] Save the edit with no test, with a bound data source and no record, and with a record
            Test.startTest();
                try {

                    AIToolsEditorService.saveDataSource(edit, null);
                } catch (Exception ex) {

                    untestedRefusal = ex.getMessage();
                }

                AIToolsDataStructure.SaveResult failedResult = AIToolsEditorService.saveDataSource(edit, new AIToolsDataStructure.TestRequest());
                edit.soqlTemplate = 'SELECT Id, Name FROM Account WHERE Id = :recordId LIMIT 5';
                AIToolsDataStructure.TestRequest request = new AIToolsDataStructure.TestRequest();
                request.recordId = AIAssistTestDataFactory.createAccounts(1, true)[0].Id;
                AIToolsDataStructure.SaveResult passedResult = AIToolsEditorService.saveDataSource(edit, request);
            Test.stopTest();

            // [3] Read the record back
            AIDataSource__c saved = [SELECT BindingType__c, SOQLTemplate__c, LastTestStatus__c FROM AIDataSource__c WHERE Id = :dataSource.Id];

            // [4] Check the change only went live once it passed
            Assert.areEqual(Label.AI_Tools_Error_Test_Required, untestedRefusal, 'A data source agents use cannot be saved untested.');
            Assert.isFalse(failedResult.isSaved, 'A change that fails its test is not saved.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_FAILED, failedResult.testResult.status, 'The failed test is returned.');
            Assert.isTrue(passedResult.isSaved, 'A change that passes its test is saved.');
            Assert.areEqual(AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND, saved.BindingType__c, 'The new binding went live.');
            Assert.areEqual('SELECT Id, Name FROM Account WHERE Id = :recordId LIMIT 5', saved.SOQLTemplate__c, 'The new query went live.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, saved.LastTestStatus__c, 'The passing result is kept.');
            Assert.areEqual(1, passedResult.row.agentCount, 'The row counts the agent.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            List<String> refusals = new List<String>();

            // [2] Call each method as that user and keep each message
            Test.startTest();
                System.runAs(users[0]) {
                    try {

                        AIToolsEditorService.getDataSourceRows();
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.getDataSourceDetail(dataSource.Id);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.getAgentUses(dataSource.Id);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.getObjectOptions();
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.getFieldOptions('Account');
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.getApexClassOptions();
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.findUsers('Assist');
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.validateSoql('SELECT Id FROM Account', false, 20);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.runTest(new AIToolsDataStructure.DataSourceDetail(), null);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }

                    try {

                        AIToolsEditorService.saveDataSource(new AIToolsDataStructure.DataSourceDetail(), null);
                    } catch (Exception ex) {

                        refusals.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check every call was refused with the access label
            Assert.areEqual(10, refusals.size(), 'All ten calls are refused.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'Every refusal shows the access label.');
        }
    }
}
