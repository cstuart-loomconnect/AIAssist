/*
Class Name: AIPlatformLogEventHandler

=================================================================
=================================================================

Description: Saves published AIPlatformLogEvent__e entries as AIPlatformLog__c records, which
the Admin and Super User permission sets can read. Entries are dropped, not saved, while
AIAssistSettings__c.IsPlatformLoggingEnabled__c is off.

An event trigger runs as the Automated Process user, with no permission set, so the insert is
explicit system mode. It saves what it can: a log record that fails to save has nowhere else to
be reported, and must not stop the others.

Event triggers run in their own transaction, never inside the subscriber's, and this one writes
only to the package's own AIPlatformLog__c.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Severity copied across. Static run-once flag removed (it dropped every batch after the first). Debug statement removed.
3.0          Chandler Stuart          Restructured to the standard pattern: the trigger only routes by context to handleBeforeInsert, handleAfterUpdate and so on, each handler has its own exception type and a test seam, and a failure is logged and never stops the save.
*/

public inherited sharing class AIPlatformLogEventHandler {
  public class AIPlatformLogEventHandlerException extends Exception {
  }

  @TestVisible
  private static Boolean isTestCustomExceptionThrown = false;

  // Saves each event as a log record. A failure here is not logged through the log manager, which would publish another event into this same trigger.
  public static void handleAfterInsert(List<AIPlatformLogEvent__e> events) {
    try {
      if (
        !AIAssistSettingsService.isEnabled() ||
        !AIAssistSettingsService.isPlatformLoggingEnabled()
      )
        return;
      if (isTestCustomExceptionThrown) {
        throw new AIPlatformLogEventHandlerException(
          'Test exception for AIPlatformLogEventHandler.handleAfterInsert'
        );
      }

      if (events == null || events.isEmpty())
        return;

      List<AIPlatformLog__c> platformLogs = new List<AIPlatformLog__c>();

      for (AIPlatformLogEvent__e logEvent : events) {
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
    } catch (Exception caughtException) {
      System.debug(
        LoggingLevel.ERROR,
        'AI Assist: platform log events could not be saved.'
      );
    }
  }
}
