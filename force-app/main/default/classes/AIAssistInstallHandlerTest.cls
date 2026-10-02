/*
Class Name: AIAssistInstallHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIAssistInstallHandler: the post-install script creates the organisation settings rows from the field defaults and never overwrites what a subscriber configured.

=================================================================
=================================================================
Applicable Classes:

AIAssistInstallHandler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIAssistInstallHandlerTest {
  // testScenario1: A first install creates both organisation settings rows from the field defaults.
  // testScenario2: Reinstalling over existing settings never overwrites a configured value or creates a second row.
  // testScenario3: An upgrade leaves the settings alone, and a null context is tolerated.
  // testScenario5: When the job cannot be scheduled the install still succeeds, the settings are created and the failure is logged.
  // testScenario4: A first install schedules the daily housekeeping job once; installing again does not schedule a second, and an upgrade schedules none.

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
    delete [SELECT Id FROM AIAssistSettings__c];

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), null);
    Test.stopTest();

    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();

    Assert.isNotNull(settings.Id, 'The organisation settings row exists.');
    Assert.isTrue(
      settings.IsEnabled__c,
      'The application starts switched on, from the field default.'
    );
    Assert.areEqual(
      10,
      settings.ProcessingLockMinutes__c,
      'The field default for the lock time is applied.'
    );
    Assert.areEqual(
      30000,
      settings.CalloutTimeoutMilliseconds__c,
      'The callout timeout starts at its field default, so the first turn does not fail for want of it.'
    );
    Assert.isNotNull(uiSettings.Id, 'The organisation UI settings row exists.');
    Assert.isTrue(
      uiSettings.IsUserInitiatedChatEnabled__c,
      'Chat starts enabled, from the field default.'
    );
  }

  @IsTest
  static void testScenario2() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ProcessingLockMinutes__c = 25;
    update settings;

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), null);
    Test.stopTest();

    Assert.areEqual(
      25,
      AIAssistSettings__c.getOrgDefaults().ProcessingLockMinutes__c,
      'A configured value survives a reinstall.'
    );
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIAssistSettings__c],
      'No second row is created.'
    );
  }

  @IsTest
  static void testScenario3() {
    delete [SELECT Id FROM AIAssistSettings__c];

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), new Version(0, 0));
    new AIAssistInstallHandler().onInstall(null);
    Test.stopTest();

    Assert.areEqual(
      1,
      [SELECT COUNT() FROM AIAssistSettings__c],
      'Only the null-context call, which is treated as a first install, created a row; the upgrade created none.'
    );
  }

  @IsTest
  static void testScenario4() {
    // The org the tests run in may already have the job; the assertions are about what installing changes.
    Integer jobsBefore = [
      SELECT COUNT()
      FROM CronTrigger
      WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
    ];

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), new Version(1, 0));
    Integer jobsAfterUpgrade = [
      SELECT COUNT()
      FROM CronTrigger
      WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
    ];
    Test.testInstall(new AIAssistInstallHandler(), null);
    Test.testInstall(new AIAssistInstallHandler(), null);
    Id secondSchedule = AIMaintenanceScheduler.scheduleDaily();
    Test.stopTest();

    Assert.areEqual(jobsBefore, jobsAfterUpgrade, 'An upgrade schedules none.');
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE CronJobDetail.Name = :AIMaintenanceScheduler.JOB_NAME
      ],
      'A first install leaves exactly one job, however often it runs.'
    );
    Assert.isNull(secondSchedule, 'Already scheduled, so nothing is added.');
  }

  @IsTest
  static void testScenario5() {
    delete [SELECT Id FROM AIAssistUISettings__c];
    AIMaintenanceScheduler.isTestCustomExceptionThrown = true;

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), null);
    Test.stopTest();

    Assert.isNotNull(
      AIAssistUISettings__c.getOrgDefaults().Id,
      'The settings are created even though the job could not be scheduled.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIAssistInstallHandler'
      ],
      'Logged once.'
    );
  }
}
