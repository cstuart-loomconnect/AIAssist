/*
Class Name: AIPlatformLogManagerTest

=================================================================
=================================================================

Description: Testing utility for AIPlatformLogManager: what is published as an event, what is saved as a log, and that logging never throws.

=================================================================
=================================================================
Applicable Classes:

AIPlatformLogManager: Coverage TBC
AIPlatformLogEventHandler: Coverage TBC
AIPlatformLogEventTrigger: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPlatformLogManagerTest {

    // testScenario1: logException publishes one error event that is saved as one AIPlatformLog__c with the class, method, exception type, message, user and the record the DML failed on.
    // testScenario2: A message longer than the event field is cut to 255 characters so the publish succeeds, and the full text stays in the detail.
    // testScenario3: logExceptions logs a batch of save results as one entry that counts the failures and names each failed record and its error.
    // testScenario4: A batch where every record saved logs nothing.
    // testScenario5: logCustomMessage records a warning with the related record, and does nothing when both the message and the detail are blank.
    // testScenario6: Missing input is ignored without throwing: no exception, no class name, no method name and no save results.
    // testScenario7: With exception logging switched off nothing is published, so nothing is saved.
    // testScenario8: With platform logging switched off events are published but dropped rather than saved as records.

    private static final String CLASS_NAME = 'AIPlatformLogManagerTest';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an agent and make an invalid update that throws a real DmlException
        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
        agent.ConversationRetentionDays__c = -1;

        // The validation rule refuses this update, which gives us a real DmlException to log
        DmlException dmlException;

        try {
            update agent;
        } catch (DmlException ex) {
            dmlException = ex;
        }

        // [2] Check the update was refused
        Assert.isNotNull(dmlException, 'The validation rule should have refused the update.');

        // [3] Log the exception
        Test.startTest();
            AIPlatformLogManager.logException(dmlException, CLASS_NAME, 'testScenario1');
        Test.stopTest();

        // [4] Read the saved log back
        List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c, ExceptionType__c, ExceptionMessage__c, Severity__c, User__c, OccurredAt__c, ExceptionLogDetail__c, RelatedRecordId__c FROM AIPlatformLog__c];

        // [5] Check the log records the exception, the user and the failed record
        Assert.areEqual(1, logs.size(), 'One exception should be one log.');

        Assert.areEqual(CLASS_NAME, logs[0].ClassName__c, 'The class that logged it should be recorded.');
        Assert.areEqual('testScenario1', logs[0].MethodName__c, 'The method that logged it should be recorded.');

        Assert.areEqual('System.DmlException', logs[0].ExceptionType__c, 'The exception type should be recorded.');
        Assert.isTrue(logs[0].ExceptionMessage__c.contains('1 or more'), 'The exception message should be the validation rule\'s.');
        Assert.areEqual(AIAssistApplicationConstants.LOG_SEVERITY_ERROR, logs[0].Severity__c, 'An exception should be an error.');

        Assert.areEqual(UserInfo.getUserId(), logs[0].User__c, 'The user it happened to should be recorded.');
        Assert.isNotNull(logs[0].OccurredAt__c, 'The time it happened should be recorded.');
        Assert.areEqual(String.valueOf(agent.Id), logs[0].RelatedRecordId__c, 'The record the DML failed on should be recorded.');
        Assert.isTrue(logs[0].ExceptionLogDetail__c.contains('testScenario1'), 'The detail should name the method.');
    }

    @IsTest static void testScenario2() {

        // [1] Build a message longer than the event field
        String longMessage = 'x'.repeat(1000);

        // [2] Log an exception and a custom message with the long text
        Test.startTest();
            AIPlatformLogManager.logException(new NullPointerException(), CLASS_NAME, 'testScenario2');
            AIPlatformLogManager.logCustomMessage(longMessage, longMessage, CLASS_NAME, 'testScenario2', null);
        Test.stopTest();

        // [3] Read the custom message log back
        AIPlatformLog__c customLog = [SELECT ExceptionMessage__c, ExceptionLogDetail__c FROM AIPlatformLog__c WHERE ExceptionType__c = :AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE];

        // [4] Check the message was cut to 255 characters and the detail kept in full
        Assert.areEqual(255, customLog.ExceptionMessage__c.length(), 'The message should be cut to the field size, or the whole publish would be refused.');
        Assert.areEqual(1000, customLog.ExceptionLogDetail__c.length(), 'The detail should keep the full text.');
    }

    @IsTest static void testScenario3() {

        // [1] Insert two agents where the second is refused
        List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, null, false);
        agents[1].ConversationRetentionDays__c = -1; // Refused by the object model's validation rule.
        List<Database.SaveResult> saveResults = Database.insert(agents, false);

        // [2] Log the save results
        Test.startTest();
            AIPlatformLogManager.logExceptions(saveResults, CLASS_NAME, 'testScenario3');
        Test.stopTest();

        // [3] Read the saved log back
        List<AIPlatformLog__c> logs = [SELECT ExceptionType__c, ExceptionMessage__c, ExceptionLogDetail__c, Severity__c FROM AIPlatformLog__c];

        // [4] Check one entry counts the failure and names the failed record
        Assert.areEqual(1, logs.size(), 'A batch with failures should be one entry, not one per record.');

        Assert.areEqual(AIAssistApplicationConstants.LOG_TYPE_DML_FAILURE, logs[0].ExceptionType__c, 'It should be a save failure.');
        Assert.areEqual('1 of 2 record(s) failed to save', logs[0].ExceptionMessage__c, 'It should count the failures.');

        Assert.isTrue(logs[0].ExceptionLogDetail__c.contains('record 2 of 2'), 'The detail should name the failed record.');
        Assert.isTrue(logs[0] .ExceptionLogDetail__c.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION'), 'The detail should include the status code of the refusal.');
        Assert.areEqual(AIAssistApplicationConstants.LOG_SEVERITY_ERROR, logs[0].Severity__c, 'A save failure should be an error.');
    }

    @IsTest static void testScenario4() {

        // [1] Insert two valid agents
        List<Database.SaveResult> saveResults = Database.insert(AIAssistTestDataFactory.createAIAgents(2, null, false), false);

        // [2] Log the save results
        Test.startTest();
            AIPlatformLogManager.logExceptions(saveResults, CLASS_NAME, 'testScenario4');
        Test.stopTest();

        // [3] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [4] Check nothing was logged
        Assert.areEqual(0, logCount, 'Nothing failed, so nothing should be logged.');
    }

    @IsTest static void testScenario5() {

        // [1] Create an agent to relate the message to
        Id relatedRecordId = AIAssistTestDataFactory.createAIAgents(1, null, true)[0].Id;

        // [2] Log a custom message, then a blank one
        Test.startTest();
            AIPlatformLogManager.logCustomMessage('Worth knowing', 'Some detail', CLASS_NAME, 'testScenario5', relatedRecordId);
            AIPlatformLogManager.logCustomMessage(null, '', CLASS_NAME, 'testScenario5', null);
        Test.stopTest();

        // [3] Read the saved logs back
        List<AIPlatformLog__c> logs = [SELECT ExceptionType__c, Severity__c, RelatedRecordId__c, ExceptionLogDetail__c FROM AIPlatformLog__c];

        // [4] Check only the real message was logged as a warning with its record
        Assert.areEqual(1, logs.size(), 'The blank message should not be logged.');

        Assert.areEqual(AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE, logs[0].ExceptionType__c, 'It should be a custom message.');
        Assert.areEqual(AIAssistApplicationConstants.LOG_SEVERITY_WARNING, logs[0].Severity__c, 'A custom message should be a warning.');

        Assert.areEqual(String.valueOf(relatedRecordId), logs[0].RelatedRecordId__c, 'The record it is about should be recorded.');
        Assert.areEqual('Some detail', logs[0].ExceptionLogDetail__c, 'The detail should be recorded.');
    }

    @IsTest static void testScenario6() {

        // [1] Log missing exceptions, class names, method names and save results
        Test.startTest();
            AIPlatformLogManager.logException(null, CLASS_NAME, 'testScenario6');
            AIPlatformLogManager.logException(new NullPointerException(), '', 'testScenario6');
            AIPlatformLogManager.logException(new NullPointerException(), CLASS_NAME, null);
            AIPlatformLogManager.logExceptions(null, CLASS_NAME, 'testScenario6');
            AIPlatformLogManager.logExceptions(new List<Database.SaveResult>(), CLASS_NAME, 'testScenario6');
        Test.stopTest();

        // [2] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [3] Check nothing was logged and nothing threw
        Assert.areEqual(0, logCount, 'Invalid input should log nothing, and should not throw.');
    }

    @IsTest static void testScenario7() {

        // [1] Switch exception logging off
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsExceptionLoggingEnabled__c = false;
        update settings;

        AIAssistSettingsService.cachedSettings = null;

        // [2] Log an exception
        Test.startTest();
            AIPlatformLogManager.logException(new NullPointerException(), CLASS_NAME, 'testScenario7');
        Test.stopTest();

        // [3] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [4] Check nothing was saved
        Assert.areEqual(0, logCount, 'Nothing was published, so nothing should be saved.');
    }

    @IsTest static void testScenario8() {

        // [1] Switch platform logging off
        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsPlatformLoggingEnabled__c = false;
        update settings;

        AIAssistSettingsService.cachedSettings = null;

        // [2] Log an exception
        Test.startTest();
            AIPlatformLogManager.logException(new NullPointerException(), CLASS_NAME, 'testScenario8');
        Test.stopTest();

        // [3] Count the saved logs
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [4] Check the event was dropped rather than saved
        Assert.areEqual(0, logCount, 'With platform logging off the event should be dropped rather than saved.');
    }
}
