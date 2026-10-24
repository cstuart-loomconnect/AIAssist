/*
Class Name: AISoqlTemplateValidatorTest

=================================================================
=================================================================

Description: Testing utility for AISoqlTemplateValidator: the errors, warnings and fixes shown while an admin writes or builds a SOQL template.

=================================================================
=================================================================
Applicable Classes:

AISoqlTemplateValidator: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AISoqlTemplateValidatorTest {

    // testScenario1: A query that filters on the open record and an agent input is checked -> it is valid with both binds listed and the open record found as an Account.
    // testScenario2: A query with a field that is close to a real one and a wrong parent field is checked -> each is an error with the closest name as the fix.
    // testScenario3: A query with no LIMIT, a LIMIT over 200 and a LIMIT of 50 is checked -> the first is a warning with a fix, the second an error with a fix and the third is clean.
    // testScenario4: A query that compares a field to a typed record id is checked -> a warning on the right line offers to turn it into a bind named after the field.
    // testScenario5: A DELETE, a FOR UPDATE, a bind as the object name, text that is not a query and an unknown object are checked -> each is refused with its own message.
    // testScenario6: A query that uses :recordId is checked as unbound, and one that never uses it as bound -> the first is an error and the second a warning.
    // testScenario7: A query with one level of sub-query and one with two levels is checked -> the first is valid and the second is refused.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write a valid query that filters on the open record and an agent input
            String soql = 'SELECT Id, Name, StageName FROM Opportunity\nWHERE AccountId = :recordId\n  AND CloseDate <= :closeBefore\nORDER BY CloseDate ASC\nLIMIT 20';

            // [2] Check it
            Test.startTest();
                AIToolsDataStructure.SoqlValidation validation = AISoqlTemplateValidator.validate(soql, true, 20);
            Test.stopTest();

            // [3] Check it is valid, with both binds and the Account as the open record
            Assert.isTrue(validation.isValid, 'A good query is valid.');
            Assert.areEqual(0, validation.problems.size(), 'A good query has no problems.');
            Assert.areEqual(new List<String>{'recordId', 'closeBefore'}, validation.binds, 'The binds are listed in the order they appear.');
            Assert.areEqual('Opportunity', validation.objectApiName, 'The queried object is found.');
            Assert.areEqual('Account', validation.recordObjectApiName, 'The open record is an Account because AccountId is compared to :recordId.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write a query with a field that does not exist but is close to a real one
            String soql = 'SELECT Id, Name, Stage, Owner.Nme FROM Opportunity WHERE AccountId = :recordId LIMIT 20';

            // [2] Check it
            Test.startTest();
                AIToolsDataStructure.SoqlValidation validation = AISoqlTemplateValidator.validate(soql, true, 20);
            Test.stopTest();

            // [3] Check each missing field is an error with the closest name as the fix
            Assert.isFalse(validation.isValid, 'A missing field makes the query invalid.');
            Assert.areEqual(2, validation.problems.size(), 'Both missing fields are reported.');
            Assert.areEqual('StageName', validation.problems[0].fixText, 'Stage is fixed to StageName.');
            Assert.areEqual(soql.indexOf('Stage'), validation.problems[0].fixStart, 'The fix starts where the wrong name starts.');
            Assert.areEqual(String.format(Label.AI_Tools_Soql_Field_Suggest, new List<String>{'Stage', 'Opportunity', 'StageName'}), validation.problems[0].message, 'The message names the closest field.');
            Assert.areEqual('Name', validation.problems[1].fixText, 'A wrong field on a parent is fixed to the parent field.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write three queries: no LIMIT, a LIMIT over 200, and a LIMIT of 50
            String noLimit = 'SELECT Id FROM Account';
            String highLimit = 'SELECT Id FROM Account LIMIT 500';
            String goodLimit = 'SELECT Id FROM Account LIMIT 50';

            // [2] Check each
            Test.startTest();
                AIToolsDataStructure.SoqlValidation noLimitResult = AISoqlTemplateValidator.validate(noLimit, false, 30);
                AIToolsDataStructure.SoqlValidation highLimitResult = AISoqlTemplateValidator.validate(highLimit, false, 30);
                AIToolsDataStructure.SoqlValidation goodLimitResult = AISoqlTemplateValidator.validate(goodLimit, false, 30);
            Test.stopTest();

            // [3] Check a missing LIMIT is a warning with a fix, a high one is an error with a fix, and a good one is clean
            Assert.isTrue(noLimitResult.isValid, 'A missing LIMIT is only a warning.');
            Assert.areEqual(AIAssistApplicationConstants.TOOLS_PROBLEM_WARNING, noLimitResult.problems[0].severity, 'The missing LIMIT is a warning.');
            Assert.areEqual('\nLIMIT 30', noLimitResult.problems[0].fixText, 'The fix adds the max rows as the LIMIT.');
            Assert.areEqual(noLimit.length(), noLimitResult.problems[0].fixStart, 'The fix is added at the end.');
            Assert.isFalse(highLimitResult.isValid, 'A LIMIT over 200 is an error.');
            Assert.areEqual('200', highLimitResult.problems[0].fixText, 'The fix lowers the LIMIT to 200.');
            Assert.areEqual(0, goodLimitResult.problems.size(), 'A LIMIT of 50 has no problems.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write a query that compares the owner to a typed record id
            String soql = 'SELECT Id FROM Account\nWHERE OwnerId = \'' + UserInfo.getUserId() + '\'\nLIMIT 5';

            // [2] Check it
            Test.startTest();
                AIToolsDataStructure.SoqlValidation validation = AISoqlTemplateValidator.validate(soql, false, 20);
            Test.stopTest();

            // [3] Check the typed id is a warning on line 3 that can be turned into an input named after the field
            Assert.isTrue(validation.isValid, 'A typed id is only a warning.');
            Assert.areEqual(1, validation.problems.size(), 'One problem is reported.');
            Assert.areEqual(2, validation.problems[0].line, 'The warning is on the line that holds the id.');
            Assert.areEqual(Label.AI_Tools_Soql_Hard_Coded_Id, validation.problems[0].message, 'The warning says a typed id will not exist in other orgs.');
            Assert.areEqual(':ownerId', validation.problems[0].fixText, 'The fix is a bind named after the field.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write queries that are not a single SELECT
            String deleteQuery = 'DELETE FROM Account';
            String lockQuery = 'SELECT Id FROM Account LIMIT 5 FOR UPDATE';
            String dynamicQuery = 'SELECT Id FROM :objectName LIMIT 5';
            String nonsense = 'show me the accounts';
            String missingObject = 'SELECT Id FROM NoSuchObject__c LIMIT 5';

            // [2] Check each
            Test.startTest();
                AIToolsDataStructure.SoqlValidation deleteResult = AISoqlTemplateValidator.validate(deleteQuery, false, 20);
                AIToolsDataStructure.SoqlValidation lockResult = AISoqlTemplateValidator.validate(lockQuery, false, 20);
                AIToolsDataStructure.SoqlValidation dynamicResult = AISoqlTemplateValidator.validate(dynamicQuery, false, 20);
                AIToolsDataStructure.SoqlValidation nonsenseResult = AISoqlTemplateValidator.validate(nonsense, false, 20);
                AIToolsDataStructure.SoqlValidation missingResult = AISoqlTemplateValidator.validate(missingObject, false, 20);
            Test.stopTest();

            // [3] Check each is refused with its own message
            Assert.areEqual(String.format(Label.AI_Tools_Soql_Only_Select, new List<String>{'DELETE'}), deleteResult.problems[0].message, 'DELETE is refused.');
            Assert.areEqual(String.format(Label.AI_Tools_Soql_Only_Select, new List<String>{'UPDATE'}), lockResult.problems[0].message, 'FOR UPDATE is refused.');
            Assert.areEqual(Label.AI_Tools_Soql_Object_Bind, dynamicResult.problems[0].message, 'A bind as the object name is refused.');
            Assert.areEqual(Label.AI_Tools_Soql_Shape, nonsenseResult.problems[0].message, 'Text that is not a query is refused.');
            Assert.areEqual(String.format(Label.AI_Tools_Soql_Object_Missing, new List<String>{'NoSuchObject__c'}), missingResult.problems[0].message, 'An unknown object is refused.');
            Assert.isFalse(deleteResult.isValid || lockResult.isValid || dynamicResult.isValid || nonsenseResult.isValid || missingResult.isValid, 'None of them is valid.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write a query that uses :recordId, and one that never does
            String usesRecordId = 'SELECT Id FROM Contact WHERE AccountId = :recordId LIMIT 5';
            String neverUsesRecordId = 'SELECT Id FROM Contact LIMIT 5';

            // [2] Check the first as unbound and the second as bound
            Test.startTest();
                AIToolsDataStructure.SoqlValidation unboundResult = AISoqlTemplateValidator.validate(usesRecordId, false, 20);
                AIToolsDataStructure.SoqlValidation boundResult = AISoqlTemplateValidator.validate(neverUsesRecordId, true, 20);
            Test.stopTest();

            // [3] Check :recordId is an error when unbound and a warning when bound but unused
            Assert.isFalse(unboundResult.isValid, ':recordId on an unbound data source is an error.');
            Assert.areEqual(Label.AI_Tools_Soql_Record_Id_Unbound, unboundResult.problems[0].message, 'The error says :recordId is only filled when bound.');
            Assert.isTrue(boundResult.isValid, 'A bound data source that never uses :recordId is only a warning.');
            Assert.areEqual(Label.AI_Tools_Soql_Record_Id_Unused, boundResult.problems[0].message, 'The warning says the query never uses :recordId.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Write a query with one level of sub-query and one with two levels
            String oneLevel = 'SELECT Id, (SELECT Id, LastName FROM Contacts) FROM Account LIMIT 5';
            String twoLevels = 'SELECT Id, (SELECT Id, (SELECT Id FROM Cases) FROM Contacts) FROM Account LIMIT 5';

            // [2] Check each
            Test.startTest();
                AIToolsDataStructure.SoqlValidation oneLevelResult = AISoqlTemplateValidator.validate(oneLevel, false, 20);
                AIToolsDataStructure.SoqlValidation twoLevelsResult = AISoqlTemplateValidator.validate(twoLevels, false, 20);
            Test.stopTest();

            // [3] Check one level is fine and two levels are refused
            Assert.isTrue(oneLevelResult.isValid, 'One level of sub-query is allowed.');
            Assert.isFalse(twoLevelsResult.isValid, 'Two levels of sub-query are refused.');
            Assert.areEqual(Label.AI_Tools_Soql_Subquery_Depth, twoLevelsResult.problems[0].message, 'The error says sub-queries may only be 1 level deep.');
        }
    }
}
