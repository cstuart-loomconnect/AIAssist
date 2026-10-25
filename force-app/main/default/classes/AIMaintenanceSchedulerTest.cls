/*
Class Name: AIMaintenanceSchedulerTest

=================================================================
=================================================================

Description: Testing utility for AIMaintenanceScheduler: the one scheduled job starts each housekeeping task, and starts nothing while the application is off.

=================================================================
=================================================================
Applicable Classes:

AIMaintenanceScheduler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMaintenanceSchedulerTest {

    // testScenario1: A scheduled run starts the housekeeping batches: conversation retention and idle closing -> both batches run once.
    // testScenario2: The job is scheduled through the platform's scheduler -> one CronTrigger with the given name exists.
    // testScenario3: Run while the application is switched off -> retention still runs and the idle batch does not.
    // testScenario4: A batch cannot be started (forced exception) -> the scheduler does not throw and one log is written for each batch.

    private static final String IDLE_BATCH_NAME = 'AIConversationIdleBatch';
    private static final String RETENTION_BATCH_NAME = 'AIConversationRetentionBatch';
    private static final String TEST_JOB_NAME = 'AI Assist maintenance test';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Run the scheduler
            Test.startTest();
                new AIMaintenanceScheduler().execute(null);
            Test.stopTest();

            // [2] Count the batch jobs that started
            Integer idleBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :IDLE_BATCH_NAME];
            Integer retentionBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :RETENTION_BATCH_NAME];

            // [3] Check each batch ran once
            Assert.areEqual(1, idleBatchCount, 'The idle batch should run once.');
            Assert.areEqual(1, retentionBatchCount, 'The retention batch should run once.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            Id jobId;

            // [1] Schedule the job through the platform scheduler
            Test.startTest();
                jobId = System.schedule(TEST_JOB_NAME, '0 0 3 * * ?', new AIMaintenanceScheduler());
            Test.stopTest();

            // [2] Count the scheduled jobs with the given name
            Integer scheduledCount = [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId AND CronJobDetail.Name = :TEST_JOB_NAME];

            // [3] Check the job is scheduled once
            Assert.areEqual(1, scheduledCount, 'The job should be scheduled once under the given name.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Switch the application off
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsEnabled__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            // [2] Run the scheduler
            Test.startTest();
                new AIMaintenanceScheduler().execute(null);
            Test.stopTest();

            // [3] Count the batch jobs that started
            Integer idleBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :IDLE_BATCH_NAME];
            Integer retentionBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :RETENTION_BATCH_NAME];

            // [4] Check retention ran and idle closing did not
            Assert.areEqual(0, idleBatchCount, 'Idle closing should wait for the application to be on.');
            Assert.areEqual(1, retentionBatchCount, 'Retention should still run while the application is off.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Force the scheduler to throw when starting a batch
            AIMaintenanceScheduler.isTestCustomExceptionThrown = true;

            // [2] Run the scheduler
            Test.startTest();
                new AIMaintenanceScheduler().execute(null);
            Test.stopTest();

            // [3] Count the batch jobs and the platform logs
            Integer idleBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :IDLE_BATCH_NAME];
            Integer retentionBatchCount = [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = :RETENTION_BATCH_NAME];
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'AIMaintenanceScheduler' AND MethodName__c = 'execute'];

            // [4] Check no batch started and one log was written for each
            Assert.areEqual(0, idleBatchCount, 'The idle batch should not start when the exception is forced.');
            Assert.areEqual(0, retentionBatchCount, 'The retention batch should not start when the exception is forced.');
            Assert.areEqual(2, logCount, 'One log should be written for each batch that could not start.');
        }
    }
}
