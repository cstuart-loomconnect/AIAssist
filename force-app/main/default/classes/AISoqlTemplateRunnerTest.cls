/*
Class Name: AISoqlTemplateRunnerTest

=================================================================
=================================================================

Description: Testing utility for AISoqlTemplateRunner: running a data source SOQL template in user mode with bound values and a row cap.

=================================================================
=================================================================
Applicable Classes:

AISoqlTemplateRunner: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AISoqlTemplateRunnerTest {

    // testScenario1: A template is run with its bind values -> the matching records are returned.
    // testScenario2: A template without a LIMIT, and one with a larger LIMIT, are run with a cap of 10 -> both results are cut to 10.
    // testScenario3: A blank template and a blank cap are run -> no records for the blank template, and the cap falls back to 20.
    // testScenario4: A broken template is run -> it throws with the original error as the cause, rather than returning an empty list.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create three accounts
        List<Account> accounts = AIAssistTestDataFactory.createAccounts(3, true);

        // [2] Run a template with a bind value
        Test.startTest();
            List<SObject> rows = AISoqlTemplateRunner.runTemplate('SELECT Id, Name FROM Account WHERE Id = :accountId', new Map<String, Object>{ 'accountId' => accounts[0].Id }, 20);
        Test.stopTest();

        // [3] Check only the matching account is returned
        Assert.areEqual(1, rows.size(), 'One account matches the bound Id.');
        Assert.areEqual(accounts[0].Id, rows[0].Id, 'It is the right one.');
    }

    @IsTest static void testScenario2() {

        // [1] Create 30 accounts
        AIAssistTestDataFactory.createAccounts(30, true);

        // [2] Run a template with no LIMIT and one with a larger LIMIT, both capped at 10
        Test.startTest();
            List<SObject> unlimited = AISoqlTemplateRunner.runTemplate('SELECT Id FROM Account', null, 10);
            List<SObject> overLimited = AISoqlTemplateRunner.runTemplate('SELECT Id FROM Account LIMIT 25', null, 10);
        Test.stopTest();

        // [3] Check both results are cut to 10
        Assert.areEqual(10, unlimited.size(), 'A LIMIT is added when the template has none.');
        Assert.areEqual(10, overLimited.size(), 'A larger limit in the template is still cut to the cap.');
    }

    @IsTest static void testScenario3() {

        // [1] Create 30 accounts
        AIAssistTestDataFactory.createAccounts(30, true);

        // [2] Run a blank template and a template with no cap
        Test.startTest();
            List<SObject> blankTemplate = AISoqlTemplateRunner.runTemplate('', null, 10);
            List<SObject> defaultCap = AISoqlTemplateRunner.runTemplate('SELECT Id FROM Account;', null, null);
        Test.stopTest();

        // [3] Check the blank template returns nothing and the cap falls back to 20
        Assert.areEqual(0, blankTemplate.size(), 'Nothing to run.');
        Assert.areEqual(20, defaultCap.size(), 'A trailing semicolon is tolerated and a missing cap falls back to 20.');
    }

    @IsTest static void testScenario4() {

        // [1] Prepare to capture the error
        String errorMessage;
        Exception errorCause;

        // [2] Run a broken template
        Test.startTest();
            try {
                AISoqlTemplateRunner.runTemplate('SELECT Nothing FROM Account', null, 10);
            } catch (AISoqlTemplateRunner.AISoqlTemplateRunnerException ex) {
                errorMessage = ex.getMessage();
                errorCause = ex.getCause();
            }
        Test.stopTest();

        // [3] Check it threw with the original error as the cause
        Assert.isNotNull(errorMessage, 'A broken template should have thrown.');
        Assert.areEqual(true, errorMessage.startsWith('Failed to run SOQL template'), 'The error says the template failed.');
        Assert.isNotNull(errorCause, 'The original error is kept as the cause.');
    }
}
