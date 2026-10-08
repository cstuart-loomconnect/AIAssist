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
  // testScenario6: A sandbox install leaves the application switched off with no org recorded; a production install switches it on and records the org.
  // testScenario7: An upgrade runs the numbered steps newer than the version upgraded from, once and in order; an upgrade from a version that already had them runs none, and a first install runs none.
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
    AIAssistInstallHandler.isSandboxOverride = false; // Tests run in a scratch org, which is a sandbox.

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), null);
    Test.stopTest();

    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();

    Assert.isNotNull(settings.Id, 'The organisation settings row exists.');
    Assert.isTrue(
      settings.IsEnabled__c,
      'The application starts switched on in production.'
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

  @IsTest
  static void testScenario6() {
    delete [SELECT Id FROM AIAssistSettings__c];
    AIAssistSettingsService.clearCache();

    Test.startTest();
    AIAssistInstallHandler.isSandboxOverride = true;
    Test.testInstall(new AIAssistInstallHandler(), null);
    AIAssistSettings__c inSandbox = AIAssistSettings__c.getOrgDefaults();
    AIAssistSettingsService.clearCache();
    Boolean isEnabledInSandbox = AIAssistSettingsService.isEnabled();

    delete [SELECT Id FROM AIAssistSettings__c];
    AIAssistInstallHandler.isSandboxOverride = false;
    Test.testInstall(new AIAssistInstallHandler(), null);
    AIAssistSettings__c inProduction = AIAssistSettings__c.getOrgDefaults();
    AIAssistSettingsService.clearCache();
    Boolean isEnabledInProduction = AIAssistSettingsService.isEnabled();
    Test.stopTest();

    Assert.isFalse(inSandbox.IsEnabled__c, 'A sandbox install is off.');
    Assert.isNull(inSandbox.ActivatedOrgId__c, 'And records no org.');
    Assert.isFalse(isEnabledInSandbox, 'So the application is inactive.');
    Assert.isTrue(inProduction.IsEnabled__c, 'A production install is on.');
    Assert.areEqual(
      UserInfo.getOrganizationId(),
      inProduction.ActivatedOrgId__c,
      'Recorded against this org.'
    );
    Assert.isTrue(isEnabledInProduction, 'And active.');
  }

  @IsTest
  static void testScenario7() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.ActivatedOrgId__c = null;
    update settings;
    AIAssistSettingsService.clearCache();

    Test.startTest();
    Test.testInstall(new AIAssistInstallHandler(), null);
    List<Integer> onFirstInstall = AIAssistInstallHandler.upgradeStepsRun.clone();
    Test.testInstall(new AIAssistInstallHandler(), new Version(0, 1));
    List<Integer> fromOlder = AIAssistInstallHandler.upgradeStepsRun.clone();
    AIAssistInstallHandler.upgradeStepsRun.clear();
    Test.testInstall(new AIAssistInstallHandler(), new Version(0, 2));
    Test.testInstall(new AIAssistInstallHandler(), new Version(3, 0));
    List<Integer> fromCurrent = AIAssistInstallHandler.upgradeStepsRun.clone();
    Test.stopTest();

    Assert.isTrue(onFirstInstall.isEmpty(), 'A first install runs no step.');
    Assert.areEqual(
      new List<Integer>{ 1 },
      fromOlder,
      'Every newer step, once, in order.'
    );
    Assert.isTrue(
      fromCurrent.isEmpty(),
      'A version that already had the steps runs none again.'
    );
    Assert.areEqual(
      UserInfo.getOrganizationId(),
      AIAssistSettings__c.getOrgDefaults().ActivatedOrgId__c,
      'Step 1 recorded the org.'
    );
  }
}
