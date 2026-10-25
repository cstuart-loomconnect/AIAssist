/*
Class Name: AIPlatformLogManager

=================================================================
=================================================================

Description: Records what went wrong by publishing AIPlatformLogEvent__e, without ever being the thing that goes wrong.

Step 1: Check there is something to log and build the event
Step 2: Skip quietly if the publish allowance is used up
Step 3: Cut the text fields to the event's field sizes and publish the event
Step 4: Swallow any failure so a log call never throws

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPlatformLogManager {

    // AIPlatformLogEvent__e field sizes: Text(255) and Long Text Area(32768).
    private static final Integer SHORT_TEXT_LENGTH = 255;
    private static final Integer LONG_TEXT_LENGTH = 32768;

    private static Boolean isAuditEntry = false;

    // Logs a caught exception as an error. Nothing is written to the debug log except the class name, because exception text can contain what the user typed.
    public static void logException(Exception caughtException, String className, String methodName) {

        try {

            // [1] Nothing to log without an exception, a class name and a method name
            if (caughtException == null || String.isBlank(className) || String.isBlank(methodName)) return;

            // [2] Build the event from the exception, including the cause when there is one
            AIPlatformLogEvent__e exceptionLogEvent = new AIPlatformLogEvent__e(ClassName__c = className, MethodName__c = methodName, ExceptionType__c = caughtException.getTypeName(), ExceptionMessage__c = caughtException.getMessage(), StackTrace__c = caughtException.getStackTraceString(), ExceptionLogDetail__c = className + '.' + methodName + ' threw ' + caughtException.getTypeName() + ': ' + caughtException.getMessage() + (caughtException.getCause() != null ? '\n\nCaused by: ' + caughtException.getCause() : ''), Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_ERROR);

            // [3] If a record failed to save, point the event at that record
            if (caughtException instanceof DmlException && ((DmlException) caughtException).getNumDml() > 0) exceptionLogEvent.RelatedRecordId__c = ((DmlException) caughtException).getDmlId(0);

            // [4] Publish only if the publish allowance is not used up
            if (Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()) {

                // [5] Stamp the time and user, and cut each text field to fit the event, because an over-length value would make the whole publish fail
                exceptionLogEvent.OccurredAt__c = System.now();
                exceptionLogEvent.UserId__c = UserInfo.getUserId();
                exceptionLogEvent.ClassName__c = exceptionLogEvent.ClassName__c == null ? null : exceptionLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
                exceptionLogEvent.MethodName__c = exceptionLogEvent.MethodName__c == null ? null : exceptionLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
                exceptionLogEvent.ExceptionType__c = exceptionLogEvent.ExceptionType__c == null ? null : exceptionLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
                exceptionLogEvent.ExceptionMessage__c = exceptionLogEvent.ExceptionMessage__c == null ? null : exceptionLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
                exceptionLogEvent.StackTrace__c = exceptionLogEvent.StackTrace__c == null ? null : exceptionLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
                exceptionLogEvent.ExceptionLogDetail__c = exceptionLogEvent.ExceptionLogDetail__c == null ? null : exceptionLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

                // [6] Publish the event
                Database.SaveResult exceptionPublishResult = EventBus.publish(exceptionLogEvent);

                // [7] There is nowhere left to log a failed publish, so write a debug line that names the class only, never the text
                if (!exceptionPublishResult.isSuccess()) System.debug(LoggingLevel.ERROR, 'AI Assist: a platform log event was not published from ' + exceptionLogEvent.ClassName__c + '.');
            }

        } catch (Exception ex) {
            // [8] Logging must never be the cause of a failure, and the text is never repeated here
            System.debug(LoggingLevel.ERROR, 'AI Assist: a log entry could not be built.');
        }
    }

    // Logs the failures in a list of save results as one entry: how many failed, and a line for each with its status code, message and fields.
    public static void logExceptions(List<Database.SaveResult> saveResults, String className, String methodName) {

        try {

            // [1] Nothing to log without save results, a class name and a method name
            if (saveResults == null || saveResults.isEmpty() || String.isBlank(className) || String.isBlank(methodName)) return;

            Integer failedCount = 0;
            List<Id> failedRecordIds = new List<Id>();
            List<String> errorLines = new List<String>();

            // [2] Go through the results, counting each failure and writing a line for each of its errors
            for (Integer resultIndex = 0; resultIndex < saveResults.size(); resultIndex++) {

                Database.SaveResult saveResult = saveResults[resultIndex];

                if (saveResult == null || saveResult.isSuccess()) continue;

                failedCount++;

                if (saveResult.getId() != null) failedRecordIds.add(saveResult.getId());

                for (Database.Error saveError : saveResult.getErrors()) {

                    errorLines.add('record ' + (resultIndex + 1) + ' of ' + saveResults.size() + ' failed: ' + saveError.getStatusCode() + ': ' + saveError.getMessage() + (saveError.getFields() != null && !saveError.getFields().isEmpty() ? ' [fields: ' + String.join(saveError.getFields(), ', ') + ']' : ''));
                }
            }

            // [3] Nothing failed, so there is nothing to log
            if (failedCount == 0) return;

            // [4] Build one event for the whole batch
            AIPlatformLogEvent__e dmlFailureLogEvent = new AIPlatformLogEvent__e(ClassName__c = className, MethodName__c = methodName, ExceptionType__c = AIAssistApplicationConstants.LOG_TYPE_DML_FAILURE, ExceptionMessage__c = failedCount + ' of ' + saveResults.size() + ' record(s) failed to save', ExceptionLogDetail__c = String.join(errorLines, '\n'), RelatedRecordId__c = failedRecordIds.isEmpty() ? null : failedRecordIds[0], Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_ERROR);

            // [5] Publish only if the publish allowance is not used up
            if (Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()) {

                // [6] Stamp the time and user, and cut each text field to fit the event
                dmlFailureLogEvent.OccurredAt__c = System.now();
                dmlFailureLogEvent.UserId__c = UserInfo.getUserId();
                dmlFailureLogEvent.ClassName__c = dmlFailureLogEvent.ClassName__c == null ? null : dmlFailureLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
                dmlFailureLogEvent.MethodName__c = dmlFailureLogEvent.MethodName__c == null ? null : dmlFailureLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
                dmlFailureLogEvent.ExceptionType__c = dmlFailureLogEvent.ExceptionType__c == null ? null : dmlFailureLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
                dmlFailureLogEvent.ExceptionMessage__c = dmlFailureLogEvent.ExceptionMessage__c == null ? null : dmlFailureLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
                dmlFailureLogEvent.StackTrace__c = dmlFailureLogEvent.StackTrace__c == null ? null : dmlFailureLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
                dmlFailureLogEvent.ExceptionLogDetail__c = dmlFailureLogEvent.ExceptionLogDetail__c == null ? null : dmlFailureLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

                // [7] Publish the event
                Database.SaveResult dmlPublishResult = EventBus.publish(dmlFailureLogEvent);

                // [8] There is nowhere left to log a failed publish, so write a debug line that names the class only, never the text
                if (!dmlPublishResult.isSuccess()) System.debug(LoggingLevel.ERROR, 'AI Assist: a platform log event was not published from ' + dmlFailureLogEvent.ClassName__c + '.');
            }

        } catch (Exception ex) {
            // [9] Logging must never be the cause of a failure, and the text is never repeated here
            System.debug(LoggingLevel.ERROR, 'AI Assist: a log entry could not be built.');
        }
    }

    // For something worth recording that is not an exception: a turn that failed, a publish that was refused. Severity is Warning.
    public static void logCustomMessage(String message, String logDetail, String className, String methodName, Id recordId) {

        // [1] Log it with the Warning severity
        logCustomMessage(message, logDetail, className, methodName, recordId, AIAssistApplicationConstants.LOG_SEVERITY_WARNING);
    }

    // An audit entry: a change to a credential or to who may use one. Info, not an error, and published even under org limit pressure, because a gap in the audit trail is worse than one more event.
    public static void logAudit(String message, String logDetail, String className, String methodName) {

        // [1] Mark the entry as an audit entry while it is logged
        isAuditEntry = true;

        try {

            // [2] Log it with the Info severity
            logCustomMessage(message, logDetail, className, methodName, null, AIAssistApplicationConstants.LOG_SEVERITY_INFO);

        } finally {
            // [3] Clear the mark whatever happened
            isAuditEntry = false;
        }
    }

    // As above with a severity.
    public static void logCustomMessage(String message, String logDetail, String className, String methodName, Id recordId, String severity) {

        try {

            // [1] Nothing to log when both the message and the detail are blank
            if (String.isBlank(message) && String.isBlank(logDetail)) return;

            // [2] Build the event from the message
            AIPlatformLogEvent__e customMessageLogEvent = new AIPlatformLogEvent__e(ClassName__c = className, MethodName__c = methodName, ExceptionType__c = AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE, ExceptionMessage__c = message, ExceptionLogDetail__c = logDetail, RelatedRecordId__c = recordId, Severity__c = severity);

            // [3] Publish only if the publish allowance is not used up
            if (Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()) {

                // [4] Stamp the time and user, and cut each text field to fit the event
                customMessageLogEvent.OccurredAt__c = System.now();
                customMessageLogEvent.UserId__c = UserInfo.getUserId();
                customMessageLogEvent.ClassName__c = customMessageLogEvent.ClassName__c == null ? null : customMessageLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
                customMessageLogEvent.MethodName__c = customMessageLogEvent.MethodName__c == null ? null : customMessageLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
                customMessageLogEvent.ExceptionType__c = customMessageLogEvent.ExceptionType__c == null ? null : customMessageLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
                customMessageLogEvent.ExceptionMessage__c = customMessageLogEvent.ExceptionMessage__c == null ? null : customMessageLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
                customMessageLogEvent.StackTrace__c = customMessageLogEvent.StackTrace__c == null ? null : customMessageLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
                customMessageLogEvent.ExceptionLogDetail__c = customMessageLogEvent.ExceptionLogDetail__c == null ? null : customMessageLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

                // [5] Publish the event
                Database.SaveResult customPublishResult = EventBus.publish(customMessageLogEvent);

                // [6] There is nowhere left to log a failed publish, so write a debug line that names the class only, never the text
                if (!customPublishResult.isSuccess()) System.debug(LoggingLevel.ERROR, 'AI Assist: a platform log event was not published from ' + customMessageLogEvent.ClassName__c + '.');
            }

        } catch (Exception ex) {
            // [7] Logging must never be the cause of a failure, and the text is never repeated here
            System.debug(LoggingLevel.ERROR, 'AI Assist: a log entry could not be built.');
        }
    }
}
