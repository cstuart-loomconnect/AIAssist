/*
Class Name: AIPlatformLogEventHandler

=================================================================
=================================================================

Description: Handler for managing AI Platform Log Event events related to AI Assist,
performing the business logic that runs on the AI Platform Log Event trigger.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPlatformLogEventHandler {
  public class AIPlatformLogEventHandlerException extends Exception {
  }

  private static Boolean isAfterInsertHandlerRunning = false;

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  // A failure here is not logged through the log manager, which would publish another event into this same trigger.
  public static void handleAfterInsert(List<AIPlatformLogEvent__e> logEvents) {
    try {
      if (!isAfterInsertHandlerRunning) {
        isAfterInsertHandlerRunning = true;

        if (isTestCustomExceptionThrown) {
          throw new AIPlatformLogEventHandlerException(
            'Test exception for AIPlatformLogEventHandler.handleAfterInsert'
          );
        }

        if (logEvents != null && !logEvents.isEmpty()) {
          saveEventsAsPlatformLogs(logEvents);
        }

        isAfterInsertHandlerRunning = false;
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'AI Assist: platform log events could not be saved.'
      );
    }
  }

  // Saves each event as a log record, unless platform logging has been switched off.
  private static void saveEventsAsPlatformLogs(
    List<AIPlatformLogEvent__e> logEvents
  ) {
    if (
      AIAssistSettingsService.getSettings().IsPlatformLoggingEnabled__c == false
    )
      return;
    List<AIPlatformLog__c> platformLogs = new List<AIPlatformLog__c>();

    for (AIPlatformLogEvent__e logEvent : logEvents) {
      platformLogs.add(
        new AIPlatformLog__c(
          ClassName__c = logEvent.ClassName__c,
          MethodName__c = logEvent.MethodName__c,
          OccurredAt__c = logEvent.OccurredAt__c,
          User__c = logEvent.UserId__c,
          ExceptionType__c = logEvent.ExceptionType__c,
          ExceptionMessage__c = logEvent.ExceptionMessage__c,
          StackTrace__c = logEvent.StackTrace__c,
          ExceptionLogDetail__c = logEvent.ExceptionLogDetail__c,
          RelatedRecordId__c = logEvent.RelatedRecordId__c,
          Severity__c = logEvent.Severity__c
        )
      );
    }

    Database.insert(platformLogs, false, AccessLevel.SYSTEM_MODE);
  }
}
