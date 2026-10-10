/*
Class Name: AIPlatformLogEventHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIPlatformLogEventHandler: saving published log events as AIPlatformLog__c records.

=================================================================
=================================================================
Applicable Classes:

AIPlatformLogEventHandler: Coverage TBC
AIPlatformLogEventTrigger: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPlatformLogEventHandlerTest {

    // testScenario1: Publishing an event saves every one of its fields on the AIPlatformLog__c record it creates.
    // testScenario2: Publishing more than two hundred events reaches the trigger in chunks and every one is saved.
    // testScenario3: While the application is switched off, publishing an event saves nothing.
    // testScenario4: Calling AIPlatformLogEventHandler.handleAfterInsert with null or empty inputs does nothing.
    // testScenario5: When AIPlatformLogEventHandler.isTestCustomExceptionThrown forces an exception, it is caught and not logged, and nothing is saved.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Build a log event with every field set
        Id relatedRecordId = AIAssistTestDataFactory.createAIAgents(1, null, true)[0].Id;
        Datetime occurredAt = Datetime.now().addMinutes(-5);

        AIPlatformLogEvent__e logEvent = new AIPlatformLogEvent__e(ClassName__c = 'SomeClass', MethodName__c = 'someMethod', OccurredAt__c = occurredAt, UserId__c = UserInfo.getUserId(), ExceptionType__c = 'System.DmlException', ExceptionMessage__c = 'Short message', StackTrace__c = 'Stack trace', ExceptionLogDetail__c = 'Long detail', RelatedRecordId__c = relatedRecordId, Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_WARNING);

        // [2] Publish the event
        Test.startTest();
            EventBus.publish(logEvent);
        Test.stopTest();

        // [3] Read the saved log back
        AIPlatformLog__c log = [SELECT ClassName__c, MethodName__c, OccurredAt__c, User__c, ExceptionType__c, ExceptionMessage__c, StackTrace__c, ExceptionLogDetail__c, RelatedRecordId__c, Severity__c FROM AIPlatformLog__c];

        // [4] Check every field was copied onto the log
        Assert.areEqual('SomeClass', log.ClassName__c, 'The class name should be copied across.');
        Assert.areEqual('someMethod', log.MethodName__c, 'The method name should be copied across.');
        Assert.areEqual(occurredAt, log.OccurredAt__c, 'The time it happened should be copied across.');

        Assert.areEqual(UserInfo.getUserId(), log.User__c, 'The user should be copied across.');
        Assert.areEqual('System.DmlException', log.ExceptionType__c, 'The exception type should be copied across.');
        Assert.areEqual('Short message', log.ExceptionMessage__c, 'The message should be copied across.');

        Assert.areEqual('Stack trace', log.StackTrace__c, 'The stack trace should be copied across.');
        Assert.areEqual('Long detail', log.ExceptionLogDetail__c, 'The detail should be copied across.');

        Assert.areEqual(String.valueOf(relatedRecordId), log.RelatedRecordId__c, 'The related record should be copied across.');
        Assert.areEqual(AIAssistApplicationConstants.LOG_SEVERITY_WARNING, log.Severity__c, 'The severity should be copied across.');
    }

    @IsTest static void testScenario2() {

        // [1] Build 201 log events
        List<AIPlatformLogEvent__e> logEvents = new List<AIPlatformLogEvent__e>();

        for (Integer eventIndex = 0; eventIndex < 201; eventIndex++) {
            logEvents.add(new AIPlatformLogEvent__e(ClassName__c = 'BulkClass', MethodName__c = 'bulk' + eventIndex, ExceptionType__c = 'Test', ExceptionMessage__c = 'Bulk ' + eventIndex, Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_INFO));
        }

        // [2] Publish the events
        Test.startTest();
            EventBus.publish(logEvents);
        Test.stopTest();

        // [3] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'BulkClass'];

        // [4] Check every event was saved
        Assert.areEqual(201, logCount, 'No event should be dropped because it fell in a later chunk.');
    }

    @IsTest static void testScenario3() {

        // [1] Switch the application off
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = false;
        update settings;

        AIAssistSettingsService.cachedSettings = null;

        // [2] Build a log event
        AIPlatformLogEvent__e logEvent = new AIPlatformLogEvent__e(ClassName__c = 'OffClass', MethodName__c = 'off', ExceptionType__c = 'Test', Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_INFO);

        // [3] Publish the event
        Test.startTest();
            EventBus.publish(logEvent);
        Test.stopTest();

        // [4] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = 'OffClass'];

        // [5] Check nothing was saved
        Assert.areEqual(0, logCount, 'A switched-off application should save no log records.');
    }

    @IsTest static void testScenario4() {

        // [1] Call the handler with null and empty input
        Test.startTest();
            AIPlatformLogEventHandler.handleAfterInsert(null);
            AIPlatformLogEventHandler.handleAfterInsert(new List<AIPlatformLogEvent__e>());
        Test.stopTest();

        // [2] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [3] Check nothing was saved
        Assert.areEqual(0, logCount, 'There was nothing to save.');
    }

    @IsTest static void testScenario5() {

        // [1] Force the handler to throw
        AIPlatformLogEventHandler.isTestCustomExceptionThrown = true;

        // [2] Build a log event
        AIPlatformLogEvent__e logEvent = new AIPlatformLogEvent__e(ClassName__c = 'FailClass', MethodName__c = 'fail', ExceptionType__c = 'Test', Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_INFO);

        // [3] Publish the event
        Test.startTest();
            EventBus.publish(logEvent);
        Test.stopTest();

        // [4] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [5] Check nothing was saved or logged
        Assert.areEqual(0, logCount, 'A failure saving log events should not save anything, and is not itself logged because that would loop.');
    }
}
