/*
Class Name: AIDataSourceTestServiceTest

=================================================================
=================================================================

Description: Testing utility for AIDataSourceTestService: running a data source definition once and reporting rows, hidden fields, masked fields and failures.

=================================================================
=================================================================
Applicable Classes:

AIDataSourceTestService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIDataSourceTestServiceTest {

    // testScenario1: A bound SOQL data source is tested with a record -> it passes with the row, a flattened parent column and the queries used.
    // testScenario2: A bound data source with no record, a query that cannot run and a data source with no query are tested -> each fails with its own reason.
    // testScenario3: A data source that may return one row is tested with two matching accounts -> one row comes back with a too many rows warning.
    // testScenario4: A user with no permission to read a field is checked -> the test is partial with the field removed from the table.
    // testScenario5: An executor class, a class that is not an executor and a data source with no class are tested -> the first passes cut to the row cap and the others fail.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    // Stands in for a subscriber's Apex data source: it returns every account it is shown.
    public class AccountExecutor implements IAIDataSourceExecutor {
        public AIDataSourceResponse execute(AIDataSourceRequest request) {
            return new AIDataSourceResponse([SELECT Id, Name FROM Account ORDER BY Name]);
        }
    }

    // A class a subscriber named by mistake: it exists but is not an executor.
    public class NotAnExecutor {
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account and a bound SOQL data source that reads it
            List<Account> accounts = AIAssistTestDataFactory.createAccounts(1, true);
            AIToolsDataStructure.DataSourceDetail detail = new AIToolsDataStructure.DataSourceDetail();
            detail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            detail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            detail.soqlTemplate = 'SELECT Id, Name, Owner.Name FROM Account WHERE Id = :recordId';
            detail.maxRows = 20;
            AIToolsDataStructure.TestRequest request = new AIToolsDataStructure.TestRequest();
            request.recordId = accounts[0].Id;

            // [2] Run the test
            Test.startTest();
                AIToolsDataStructure.TestResult result = AIDataSourceTestService.runTest(detail, request);
            Test.stopTest();

            // [3] Check it passed with the account in the table, the parent flattened and no column removed
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, result.status, 'The data source passes.');
            Assert.areEqual(1, result.rowCount, 'One row came back.');
            Assert.areEqual(accounts[0].Name, result.rows[0].get('Name'), 'The row holds the account name.');
            Assert.isTrue(result.rows[0].containsKey('Owner.Name'), 'A parent field is flattened into its own column.');
            Assert.areEqual(2, result.columns.size(), 'There is a column for the name and one for the owner name.');
            Assert.isTrue(result.removedFields.isEmpty(), 'No field was removed.');
            Assert.isTrue(result.queriesUsed >= 1, 'The test counts the queries it used.');
            Assert.isNull(result.runAsName, 'No other user was checked.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a bound data source and a query that cannot run
            AIToolsDataStructure.DataSourceDetail boundDetail = new AIToolsDataStructure.DataSourceDetail();
            boundDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            boundDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            boundDetail.soqlTemplate = 'SELECT Id FROM Account WHERE Id = :recordId';
            AIToolsDataStructure.DataSourceDetail brokenDetail = new AIToolsDataStructure.DataSourceDetail();
            brokenDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            brokenDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            brokenDetail.soqlTemplate = 'SELECT Id, NoSuchField__c FROM Account';
            AIToolsDataStructure.DataSourceDetail blankDetail = new AIToolsDataStructure.DataSourceDetail();
            blankDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            blankDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;

            // [2] Run each with no record
            Test.startTest();
                AIToolsDataStructure.TestResult noRecordResult = AIDataSourceTestService.runTest(boundDetail, null);
                AIToolsDataStructure.TestResult brokenResult = AIDataSourceTestService.runTest(brokenDetail, null);
                AIToolsDataStructure.TestResult blankResult = AIDataSourceTestService.runTest(blankDetail, null);
            Test.stopTest();

            // [3] Check each failed with its own reason
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_FAILED, noRecordResult.status, 'A bound data source with no record fails.');
            Assert.areEqual(Label.AI_Tools_Error_Record_Required, noRecordResult.message, 'The reason says a record is needed.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_FAILED, brokenResult.status, 'A query that cannot run fails.');
            Assert.isTrue(String.isNotBlank(brokenResult.message), 'The reason is shown.');
            Assert.areEqual(Label.AI_Tools_Error_No_Template, blankResult.message, 'A data source with no query fails.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two accounts and a data source that may return only one row
            AIAssistTestDataFactory.createAccounts(2, true);
            AIToolsDataStructure.DataSourceDetail detail = new AIToolsDataStructure.DataSourceDetail();
            detail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            detail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            detail.soqlTemplate = 'SELECT Id, Name FROM Account ORDER BY Name';
            detail.maxRows = 1;

            // [2] Run the test
            Test.startTest();
                AIToolsDataStructure.TestResult result = AIDataSourceTestService.runTest(detail, null);
            Test.stopTest();

            // [3] Check one row came back and the test says more matched
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, result.status, 'A result that was cut short still passes.');
            Assert.areEqual(1, result.rowCount, 'Only one row comes back.');
            Assert.areEqual(1, result.warnings.size(), 'One warning says more rows matched.');
            Assert.isTrue(result.warnings[0].startsWith('Too many rows'), 'The warning says there were too many rows.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a data source the other user has no permission to read, and a user with no AI Assist permission set
            AIDataSource__c dataSource = AIAssistTestDataFactory.createAIDataSources(1, AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL, 'SELECT Id FROM Account', true)[0];
            dataSource.Description__c = 'Visible to the admin only';
            update dataSource;
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIToolsDataStructure.DataSourceDetail detail = new AIToolsDataStructure.DataSourceDetail();
            detail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_SOQL;
            detail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            detail.soqlTemplate = 'SELECT Id, Description__c FROM AIDataSource__c WHERE Id = :recordId';
            AIToolsDataStructure.TestRequest request = new AIToolsDataStructure.TestRequest();
            request.recordId = dataSource.Id;
            request.runAsUserId = users[0].Id;

            // [2] Run the test checking the other user
            Test.startTest();
                AIToolsDataStructure.TestResult result = AIDataSourceTestService.runTest(detail, request);
            Test.stopTest();

            // [3] Check it ran but the field is removed and its value is taken out
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PARTIAL, result.status, 'It ran but the other user cannot see everything.');
            Assert.areEqual(new List<String>{'Description__c'}, result.removedFields, 'The field the user cannot read is listed.');
            Assert.isTrue(result.columns[0].isRemoved, 'The column is marked as removed.');
            Assert.isNull(result.rows[0].get('Description__c'), 'The value is taken out of the row.');
            Assert.areEqual(users[0].FirstName + ' ' + users[0].LastName, result.runAsName, 'The user checked is named.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an account and two Apex data sources: one is an executor and one is not
            AIAssistTestDataFactory.createAccounts(1, true);
            AIToolsDataStructure.DataSourceDetail executorDetail = new AIToolsDataStructure.DataSourceDetail();
            executorDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
            executorDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            executorDetail.apexClassName = 'AIDataSourceTestServiceTest.AccountExecutor';
            executorDetail.maxRows = 1;
            AIToolsDataStructure.DataSourceDetail wrongDetail = new AIToolsDataStructure.DataSourceDetail();
            wrongDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
            wrongDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;
            wrongDetail.apexClassName = 'AIDataSourceTestServiceTest.NotAnExecutor';
            AIToolsDataStructure.DataSourceDetail blankDetail = new AIToolsDataStructure.DataSourceDetail();
            blankDetail.sourceType = AIAssistApplicationConstants.DATA_SOURCE_TYPE_APEX;
            blankDetail.bindingType = AIAssistApplicationConstants.DATA_SOURCE_BINDING_UNBOUND;

            // [2] Run each
            Test.startTest();
                AIToolsDataStructure.TestResult executorResult = AIDataSourceTestService.runTest(executorDetail, null);
                AIToolsDataStructure.TestResult wrongResult = AIDataSourceTestService.runTest(wrongDetail, null);
                AIToolsDataStructure.TestResult blankResult = AIDataSourceTestService.runTest(blankDetail, null);
            Test.stopTest();

            // [3] Check the executor ran, cut to the row cap, and the others failed
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_TEST_STATUS_PASSED, executorResult.status, 'An executor class passes.');
            Assert.areEqual(1, executorResult.rowCount, 'The rows are cut to the row cap.');
            Assert.areEqual(String.format(Label.AI_Tools_Error_Class_Not_Executor, new List<String>{'AIDataSourceTestServiceTest.NotAnExecutor'}), wrongResult.message, 'A class that is not an executor is refused.');
            Assert.areEqual(Label.AI_Tools_Error_Apex_Class, blankResult.message, 'A data source with no class is refused.');
        }
    }
}
