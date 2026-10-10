/*
Class Name: AIMessagingDataService

=================================================================
=================================================================

Description: Every write the messaging layer makes to data the end user cannot write, and the one place a write is marked as trusted.

Step 1: Raise the trusted-write counter that AIConversationMessageTriggerHandler reads
Step 2: Insert, update or delete in system mode, because the fields written are system-managed
Step 3: Throw a generic error, or log the failure, depending on the method called
Step 4: Lower the counter again, even when the write threw

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIMessagingDataService {

    public class AIMessagingDataServiceException extends Exception {}

    @TestVisible
    private static Integer writeDepth = 0;

    // True while a write made through this class is running, read by the message trigger.
    public static Boolean isTrustedWrite() {

        // [1] Report whether a trusted write is in progress
        return writeDepth > 0;
    }

    // Inserts in system mode and throws on the first failure: a generic message for the user, the real error in the log.
    public static void insertOrThrow(List<SObject> records) {

        // [1] Insert the records, throwing on failure
        write(records, true, true, null, null);
    }

    // Updates in system mode and throws on the first failure: a generic message for the user, the real error in the log.
    public static void updateOrThrow(List<SObject> records) {

        // [1] Update the records, throwing on failure
        write(records, false, true, null, null);
    }

    // Inserts in system mode for bookkeeping that must never fail the turn it describes. A failure is logged, not thrown.
    public static void insertAndLogFailures(List<SObject> records, String className, String methodName) {

        // [1] Insert the records, logging any failure
        write(records, true, false, className, methodName);
    }

    // Updates in system mode for bookkeeping that must never fail the turn it describes. A failure is logged, not thrown.
    public static void updateAndLogFailures(List<SObject> records, String className, String methodName) {

        // [1] Update the records, logging any failure
        write(records, false, false, className, methodName);
    }

    // Deletes in system mode and returns how many were deleted. A record that cannot be deleted is logged once and the rest still go.
    public static Integer deleteAndLogFailures(List<SObject> records, String className, String methodName) {

        // [1] Nothing to delete
        if (records == null || records.isEmpty()) return 0;

        // [2] Start counting deletes and remember whether a failure has been logged
        Integer deletedCount = 0;
        Boolean isFailureLogged = false;

        // [3] Delete in system mode, letting the good records through if some fail
        for (Database.DeleteResult deleteResult : Database.delete(records, false, AccessLevel.SYSTEM_MODE)) {

            // [4] Count a success, or log only the first failure
            if (deleteResult.isSuccess()) {

                deletedCount++;

            } else if (!isFailureLogged) {

                isFailureLogged = true;
                AIPlatformLogManager.logCustomMessage('A record could not be deleted: ' + deleteResult.getErrors()[0].getStatusCode(), deleteResult.getErrors()[0].getMessage(), className, methodName, deleteResult.getId());
            }
        }

        // [5] Return how many were deleted
        return deletedCount;
    }

    // Inserts or updates in system mode with the trusted-write counter raised, then throws or logs failures as asked.
    private static void write(List<SObject> records, Boolean isInsert, Boolean shouldThrow, String className, String methodName) {

        // [1] Nothing to write
        if (records == null || records.isEmpty()) return;

        // [2] Mark the write as trusted so the message trigger lets non-User messages through
        writeDepth++;

        try {

            // [3] Write in system mode, letting the good records through if some fail
            List<Database.SaveResult> saveResults = isInsert ? Database.insert(records, false, AccessLevel.SYSTEM_MODE) : Database.update(records, false, AccessLevel.SYSTEM_MODE);

            // [4] For quiet writes, log every failure and carry on
            if (!shouldThrow) {

                AIPlatformLogManager.logExceptions(saveResults, className, methodName);
                return;
            }

            // [5] For strict writes, log the real error and throw the generic one on the first failure
            for (Database.SaveResult saveResult : saveResults) {

                if (!saveResult.isSuccess()) {

                    AIPlatformLogManager.logCustomMessage('Failed to ' + (isInsert ? 'insert' : 'update') + ' record: ' + saveResult.getErrors()[0].getStatusCode() + ' ' + saveResult.getErrors()[0].getMessage(), null, 'AIMessagingDataService', 'write', null);
                    throw new AIMessagingDataServiceException(Label.AI_Error_Generic);
                }
            }

        } finally {

            // [6] Lower the counter even when a write throws, or a later user insert in the transaction could forge a sender
            writeDepth--;
        }
    }
}
