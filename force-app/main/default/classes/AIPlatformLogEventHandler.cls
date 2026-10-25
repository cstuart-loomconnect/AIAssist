/*
Class Name: AIPlatformLogEventHandler

=================================================================
=================================================================

Description: Saves published AIPlatformLogEvent__e events as AIPlatformLog__c records.

Step 1: Receive the events from the trigger, once per transaction
Step 2: Turn each event into a log record and save them all
Step 3: Swallow any failure, because logging it would publish another event into this same trigger

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPlatformLogEventHandler {

    public class AIPlatformLogEventHandlerException extends Exception {}

    private static Boolean isAfterInsertHandlerRunning = false;

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Saves the events as log records. A failure here is not logged through the log manager, which would publish another event into this same trigger.
    public static void handleAfterInsert(List<AIPlatformLogEvent__e> logEvents) {

        try {

            // [1] Do nothing if this handler is already running
            if (isAfterInsertHandlerRunning) return;

            isAfterInsertHandlerRunning = true;

            // [2] Throw on purpose when a test asks for it
            if (isTestCustomExceptionThrown) throw new AIPlatformLogEventHandlerException('Test exception for AIPlatformLogEventHandler.handleAfterInsert');

            // [3] Save the events as log records
            if (logEvents != null && !logEvents.isEmpty()) saveEventsAsPlatformLogs(logEvents);

            // [4] Let the handler run again next time
            isAfterInsertHandlerRunning = false;

        } catch (Exception ex) {

            // [5] Write only a debug line, because there is nowhere safe left to log to
            System.debug(LoggingLevel.ERROR, 'AI Assist: platform log events could not be saved.');
        }
    }

    // Saves each event as a log record.
    private static void saveEventsAsPlatformLogs(List<AIPlatformLogEvent__e> logEvents) {

        List<AIPlatformLog__c> platformLogs = new List<AIPlatformLog__c>();

        // [1] Make one log record for each event
        for (AIPlatformLogEvent__e logEvent : logEvents) {

            platformLogs.add(new AIPlatformLog__c(ClassName__c = logEvent.ClassName__c, MethodName__c = logEvent.MethodName__c, OccurredAt__c = logEvent.OccurredAt__c, User__c = logEvent.UserId__c, ExceptionType__c = logEvent.ExceptionType__c, ExceptionMessage__c = logEvent.ExceptionMessage__c, StackTrace__c = logEvent.StackTrace__c, ExceptionLogDetail__c = logEvent.ExceptionLogDetail__c, RelatedRecordId__c = logEvent.RelatedRecordId__c, Severity__c = logEvent.Severity__c));
        }

        // [2] Save them all, letting each succeed or fail on its own
        Database.insert(platformLogs, false, AccessLevel.SYSTEM_MODE);
    }
}
