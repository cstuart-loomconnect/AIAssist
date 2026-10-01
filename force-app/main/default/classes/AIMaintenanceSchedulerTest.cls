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
  // testScenario3: Switched off, it starts nothing.

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
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM AsyncApexJob
        WHERE ApexClass.Name = 'AIRecordRetentionBatch'
      ],
      'Logs and violations.'
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
        WHERE
          ApexClass.Name IN (
            'AIConversationIdleBatch',
            'AIConversationRetentionBatch',
            'AIRecordRetentionBatch'
          )
      ],
      'Nothing while off.'
    );
  }
}
