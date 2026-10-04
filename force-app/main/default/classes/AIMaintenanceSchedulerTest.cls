/*
Class Name: AIMaintenanceSchedulerTest

=================================================================
=================================================================

Description: Testing utility for AIMaintenanceScheduler: the one scheduled job starts each housekeeping task, and starts nothing while the application is off.

=================================================================
=================================================================
Applicable Classes:

AIMaintenanceScheduler

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest
private class AIMaintenanceSchedulerTest {
  // testScenario1: A scheduled run starts the four housekeeping batches.
  // testScenario2: It can be scheduled and fires through the platform's scheduler.
  // testScenario3: Switched off, retention and the usage totals still run and only the idle batch does not.
  // testScenario4: A batch that cannot be started is logged and the others still start.

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
    Test.startTest();
    new AIMaintenanceScheduler().execute(null);
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIConversationIdleBatch'
      ],
      'Idle batch.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIConversationRetentionBatch'
      ],
      'Retention batch.'
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIRecordRetentionBatch'
      ] >= 1,
      'Logs, violations, steps and messages, as one chained batch.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIOrgUsageTotalsBatch'
      ],
      'Usage totals.'
    );
  }

  @IsTest
  static void testScenario2() {
    String jobId;

    Test.startTest();
    jobId = System.schedule(
      'AI Assist maintenance test',
      '0 0 3 * * ?',
      new AIMaintenanceScheduler()
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CronTrigger
        WHERE Id = :jobId AND CronJobDetail.Name = 'AI Assist maintenance test'
      ],
      'Scheduled.'
    );
  }

  @IsTest
  static void testScenario3() {
    AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
    settings.IsEnabled__c = false;
    update settings;
    AIAssistSettingsService.cachedSettings = null;

    Test.startTest();
    new AIMaintenanceScheduler().execute(null);
    Test.stopTest();

    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIConversationIdleBatch'
      ],
      'Idle closing waits for the application to be on.'
    );
    Assert.areEqual(
      3,
      [
          SELECT COUNT_DISTINCT(ApexClass.Name)
          FROM AsyncApexJob
          WHERE
            ApexClass.Name IN (
              'AIConversationRetentionBatch',
              'AIRecordRetentionBatch',
              'AIOrgUsageTotalsBatch'
            )
        ][0]
        .get('expr0'),
      'Retention (conversations and the record kinds) and the usage totals run while off.'
    );
  }

  @IsTest
  static void testScenario4() {
    AIMaintenanceScheduler.isTestCustomExceptionThrown = true;

    Test.startTest();
    try {
      new AIMaintenanceScheduler().execute(null);
    } catch (Exception ex) {
      Assert.fail('The scheduler must never throw: ' + ex.getMessage());
    }
    Test.stopTest();

    Assert.areEqual(
      4,
      [
        SELECT COUNT()
        FROM AIPlatformLog__c
        WHERE ClassName__c = 'AIMaintenanceScheduler'
      ],
      'One log for each batch that could not start.'
    );
  }
}
