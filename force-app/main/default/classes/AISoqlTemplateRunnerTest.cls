/*
Class Name: AISoqlTemplateRunnerTest

=================================================================
=================================================================

Description: Testing utility for AISoqlTemplateRunner: running a data source SOQL template in user mode with bound values and a row cap.

=================================================================
=================================================================
Applicable Classes:

AISoqlTemplateRunner

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AISoqlTemplateRunnerTest {
  // testScenario1: A template runs with its bind values and returns the matching records.
  // testScenario2: A template without a LIMIT gets one, and the result is cut to the cap even if the template has a larger limit of its own.
  // testScenario3: A blank template returns no records, and a blank cap falls back to a safe default.
  // testScenario4: A broken template throws rather than returning an empty list, which the model would read as "no records found".

  @TestSetup
  static void setup() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = true;
    settings.IsExceptionLoggingEnabled__c = true;
    settings.IsPlatformLoggingEnabled__c = true;
    upsert settings;
  }

  @IsTest
  static void testScenario1() {
    List<Account> accounts = AIAssistTestDataFactory.createAccounts(3, true);

    Test.startTest();
    List<SObject> rows = AISoqlTemplateRunner.runTemplate(
      'SELECT Id, Name FROM Account WHERE Id = :accountId',
      new Map<String, Object>{ 'accountId' => accounts[0].Id },
      20
    );
    Test.stopTest();

    Assert.areEqual(1, rows.size(), 'One account matches the bound Id.');
    Assert.areEqual(accounts[0].Id, rows[0].Id, 'It is the right one.');
  }

  @IsTest
  static void testScenario2() {
    AIAssistTestDataFactory.createAccounts(30, true);

    Test.startTest();
    List<SObject> unlimited = AISoqlTemplateRunner.runTemplate(
      'SELECT Id FROM Account',
      null,
      10
    );
    List<SObject> overLimited = AISoqlTemplateRunner.runTemplate(
      'SELECT Id FROM Account LIMIT 25',
      null,
      10
    );
    Test.stopTest();

    Assert.areEqual(
      10,
      unlimited.size(),
      'A LIMIT is added when the template has none.'
    );
    Assert.areEqual(
      10,
      overLimited.size(),
      'A larger limit in the template is still cut to the cap.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAssistTestDataFactory.createAccounts(30, true);

    Test.startTest();
    List<SObject> blankTemplate = AISoqlTemplateRunner.runTemplate(
      '',
      null,
      10
    );
    List<SObject> defaultCap = AISoqlTemplateRunner.runTemplate(
      'SELECT Id FROM Account;',
      null,
      null
    );
    Test.stopTest();

    Assert.isTrue(blankTemplate.isEmpty(), 'Nothing to run.');
    Assert.areEqual(
      20,
      defaultCap.size(),
      'A trailing semicolon is tolerated and a missing cap falls back to 20.'
    );
  }

  @IsTest
  static void testScenario4() {
    Test.startTest();
    try {
      AISoqlTemplateRunner.runTemplate('SELECT Nothing FROM Account', null, 10);
      Assert.fail('A broken template should have thrown.');
    } catch (AISoqlTemplateRunner.AISoqlTemplateRunnerException ex) {
      Assert.isTrue(
        ex.getMessage().startsWith('Failed to run SOQL template'),
        'The error says the template failed.'
      );
      Assert.isNotNull(
        ex.getCause(),
        'The original error is kept as the cause.'
      );
    }
    Test.stopTest();
  }
}
