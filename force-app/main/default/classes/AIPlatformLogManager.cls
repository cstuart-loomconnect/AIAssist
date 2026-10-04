/*
Class Name: AIPlatformLogManager

=================================================================
=================================================================

Description: Records what went wrong, without ever being the thing that goes wrong.

Every entry is published as AIPlatformLogEvent__e (PublishImmediately), so it survives the
rollback of the transaction that raised it, and AIPlatformLogEventHandler saves it as an
AIPlatformLog__c record. Publishing is skipped, silently, when exception logging is switched off
or the transaction has used its Publish Immediately allowance; a log call never throws.

Text fields are cut to the event's field sizes before publishing, because an over-length value
makes the whole publish fail and the entry would be lost. The full text of a long message
stays in ExceptionLogDetail__c.

Nothing is written to the debug log: exception messages can contain what the user typed or a
provider echoed back, and a debug log is readable by far more people than the platform log.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Severity stamped. Debug statements removed (they carried exception text). Allowance check uses Publish Immediately, not DML statements. Delete and Upsert overloads dropped (nothing calls them).
3.0          Chandler Stuart          Under org limit pressure only errors are published; logCustomMessage takes a severity.
*/

public inherited sharing class AIPlatformLogManager {
  // AIPlatformLogEvent__e field sizes: Text(255) and Long Text Area(32768).
  private static final Integer SHORT_TEXT_LENGTH = 255;
  private static final Integer LONG_TEXT_LENGTH = 32768;

  public static void logException(
    Exception caughtException,
    String className,
    String methodName
  ) {
    try {
      if (
        caughtException == null ||
        String.isBlank(className) ||
        String.isBlank(methodName)
      )
        return;

      AIPlatformLogEvent__e exceptionLogEvent = new AIPlatformLogEvent__e(
        ClassName__c = className,
        MethodName__c = methodName,
        ExceptionType__c = caughtException.getTypeName(),
        ExceptionMessage__c = caughtException.getMessage(),
        StackTrace__c = caughtException.getStackTraceString(),
        ExceptionLogDetail__c = className +
          '.' +
          methodName +
          ' threw ' +
          caughtException.getTypeName() +
          ': ' +
          caughtException.getMessage() +
          (caughtException.getCause() != null
            ? '\n\nCaused by: ' + caughtException.getCause()
            : ''),
        Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_ERROR
      );

      if (
        caughtException instanceof DmlException &&
        ((DmlException) caughtException).getNumDml() > 0
      )
        exceptionLogEvent.RelatedRecordId__c = ((DmlException) caughtException)
          .getDmlId(0);

      if (
        AIAssistSettingsService.isExceptionLoggingEnabled() &&
        Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()
      ) {
        exceptionLogEvent.OccurredAt__c = System.now();
        exceptionLogEvent.UserId__c = UserInfo.getUserId();
        exceptionLogEvent.ClassName__c = exceptionLogEvent.ClassName__c == null
          ? null
          : exceptionLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
        exceptionLogEvent.MethodName__c = exceptionLogEvent.MethodName__c ==
          null
          ? null
          : exceptionLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
        exceptionLogEvent.ExceptionType__c = exceptionLogEvent.ExceptionType__c ==
          null
          ? null
          : exceptionLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
        exceptionLogEvent.ExceptionMessage__c = exceptionLogEvent.ExceptionMessage__c ==
          null
          ? null
          : exceptionLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
        exceptionLogEvent.StackTrace__c = exceptionLogEvent.StackTrace__c ==
          null
          ? null
          : exceptionLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
        exceptionLogEvent.ExceptionLogDetail__c = exceptionLogEvent.ExceptionLogDetail__c ==
          null
          ? null
          : exceptionLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

        Database.SaveResult exceptionPublishResult = EventBus.publish(
          exceptionLogEvent
        );

        // Nowhere left to log a failed publish. The debug line names the class only, never the text.
        if (!exceptionPublishResult.isSuccess())
          System.debug(
            LoggingLevel.ERROR,
            'AI Assist: a platform log event was not published from ' +
              exceptionLogEvent.ClassName__c +
              '.'
          );
      }
    } catch (Exception loggingFailure) {
      System.debug(
        LoggingLevel.ERROR,
        'AI Assist: a log entry could not be built.'
      ); // Logging must never be the cause of a failure, and the text is never repeated here.
    }
  }

  // Logs the failures in a list of save results as one entry: how many failed, and a line for each with its status code, message and fields.
  public static void logExceptions(
    List<Database.SaveResult> saveResults,
    String className,
    String methodName
  ) {
    try {
      if (
        saveResults == null ||
        saveResults.isEmpty() ||
        String.isBlank(className) ||
        String.isBlank(methodName)
      )
        return;

      Integer failedCount = 0;
      List<Id> failedRecordIds = new List<Id>();
      List<String> errorLines = new List<String>();

      for (
        Integer resultIndex = 0; resultIndex < saveResults.size(); resultIndex++
      ) {
        Database.SaveResult saveResult = saveResults[resultIndex];
        if (saveResult == null || saveResult.isSuccess())
          continue;

        failedCount++;
        if (saveResult.getId() != null)
          failedRecordIds.add(saveResult.getId());

        for (Database.Error saveError : saveResult.getErrors()) {
          errorLines.add(
            'record ' +
              (resultIndex + 1) +
              ' of ' +
              saveResults.size() +
              ' failed: ' +
              saveError.getStatusCode() +
              ': ' +
              saveError.getMessage() +
              (saveError.getFields() != null && !saveError.getFields().isEmpty()
                ? ' [fields: ' + String.join(saveError.getFields(), ', ') + ']'
                : '')
          );
        }
      }

      if (failedCount == 0)
        return; // Nothing failed, nothing to log.

      AIPlatformLogEvent__e dmlFailureLogEvent = new AIPlatformLogEvent__e(
        ClassName__c = className,
        MethodName__c = methodName,
        ExceptionType__c = AIAssistApplicationConstants.LOG_TYPE_DML_FAILURE,
        ExceptionMessage__c = failedCount +
          ' of ' +
          saveResults.size() +
          ' record(s) failed to save',
        ExceptionLogDetail__c = String.join(errorLines, '\n'),
        RelatedRecordId__c = failedRecordIds.isEmpty()
          ? null
          : failedRecordIds[0],
        Severity__c = AIAssistApplicationConstants.LOG_SEVERITY_ERROR
      );

      if (
        AIAssistSettingsService.isExceptionLoggingEnabled() &&
        Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()
      ) {
        dmlFailureLogEvent.OccurredAt__c = System.now();
        dmlFailureLogEvent.UserId__c = UserInfo.getUserId();
        dmlFailureLogEvent.ClassName__c = dmlFailureLogEvent.ClassName__c ==
          null
          ? null
          : dmlFailureLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
        dmlFailureLogEvent.MethodName__c = dmlFailureLogEvent.MethodName__c ==
          null
          ? null
          : dmlFailureLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
        dmlFailureLogEvent.ExceptionType__c = dmlFailureLogEvent.ExceptionType__c ==
          null
          ? null
          : dmlFailureLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
        dmlFailureLogEvent.ExceptionMessage__c = dmlFailureLogEvent.ExceptionMessage__c ==
          null
          ? null
          : dmlFailureLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
        dmlFailureLogEvent.StackTrace__c = dmlFailureLogEvent.StackTrace__c ==
          null
          ? null
          : dmlFailureLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
        dmlFailureLogEvent.ExceptionLogDetail__c = dmlFailureLogEvent.ExceptionLogDetail__c ==
          null
          ? null
          : dmlFailureLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

        Database.SaveResult dmlPublishResult = EventBus.publish(
          dmlFailureLogEvent
        );

        // Nowhere left to log a failed publish. The debug line names the class only, never the text.
        if (!dmlPublishResult.isSuccess())
          System.debug(
            LoggingLevel.ERROR,
            'AI Assist: a platform log event was not published from ' +
              dmlFailureLogEvent.ClassName__c +
              '.'
          );
      }
    } catch (Exception loggingFailure) {
      System.debug(
        LoggingLevel.ERROR,
        'AI Assist: a log entry could not be built.'
      ); // Logging must never be the cause of a failure, and the text is never repeated here.
    }
  }

  // For something worth recording that is not an exception: a turn that failed, a publish that was refused. Severity is Warning.
  public static void logCustomMessage(
    String message,
    String logDetail,
    String className,
    String methodName,
    Id recordId
  ) {
    logCustomMessage(
      message,
      logDetail,
      className,
      methodName,
      recordId,
      AIAssistApplicationConstants.LOG_SEVERITY_WARNING
    );
  }

  private static Boolean isAuditEntry = false;

  // An audit entry: a change to a credential or to who may use one. Info, not an error, and published even under org limit pressure, because a gap in the audit trail is worse than one more event.
  public static void logAudit(
    String message,
    String logDetail,
    String className,
    String methodName
  ) {
    isAuditEntry = true;
    try {
      logCustomMessage(
        message,
        logDetail,
        className,
        methodName,
        null,
        AIAssistApplicationConstants.LOG_SEVERITY_INFO
      );
    } finally {
      isAuditEntry = false;
    }
  }

  // As above with a severity. Under org limit pressure (AIOrgLimitMonitor) only an Error is published: a log entry is itself an event, and the allowance is the thing running out.
  public static void logCustomMessage(
    String message,
    String logDetail,
    String className,
    String methodName,
    Id recordId,
    String severity
  ) {
    try {
      if (String.isBlank(message) && String.isBlank(logDetail))
        return;
      if (
        severity != AIAssistApplicationConstants.LOG_SEVERITY_ERROR &&
        !isAuditEntry &&
        AIOrgLimitMonitor.isErrorOnlyLogging()
      )
        return;

      AIPlatformLogEvent__e customMessageLogEvent = new AIPlatformLogEvent__e(
        ClassName__c = className,
        MethodName__c = methodName,
        ExceptionType__c = AIAssistApplicationConstants.LOG_TYPE_CUSTOM_MESSAGE,
        ExceptionMessage__c = message,
        ExceptionLogDetail__c = logDetail,
        RelatedRecordId__c = recordId,
        Severity__c = severity
      );

      if (
        AIAssistSettingsService.isExceptionLoggingEnabled() &&
        Limits.getPublishImmediateDML() < Limits.getLimitPublishImmediateDML()
      ) {
        customMessageLogEvent.OccurredAt__c = System.now();
        customMessageLogEvent.UserId__c = UserInfo.getUserId();
        customMessageLogEvent.ClassName__c = customMessageLogEvent.ClassName__c ==
          null
          ? null
          : customMessageLogEvent.ClassName__c.left(SHORT_TEXT_LENGTH);
        customMessageLogEvent.MethodName__c = customMessageLogEvent.MethodName__c ==
          null
          ? null
          : customMessageLogEvent.MethodName__c.left(SHORT_TEXT_LENGTH);
        customMessageLogEvent.ExceptionType__c = customMessageLogEvent.ExceptionType__c ==
          null
          ? null
          : customMessageLogEvent.ExceptionType__c.left(SHORT_TEXT_LENGTH);
        customMessageLogEvent.ExceptionMessage__c = customMessageLogEvent.ExceptionMessage__c ==
          null
          ? null
          : customMessageLogEvent.ExceptionMessage__c.left(SHORT_TEXT_LENGTH);
        customMessageLogEvent.StackTrace__c = customMessageLogEvent.StackTrace__c ==
          null
          ? null
          : customMessageLogEvent.StackTrace__c.left(LONG_TEXT_LENGTH);
        customMessageLogEvent.ExceptionLogDetail__c = customMessageLogEvent.ExceptionLogDetail__c ==
          null
          ? null
          : customMessageLogEvent.ExceptionLogDetail__c.left(LONG_TEXT_LENGTH);

        Database.SaveResult customPublishResult = EventBus.publish(
          customMessageLogEvent
        );

        // Nowhere left to log a failed publish. The debug line names the class only, never the text.
        if (!customPublishResult.isSuccess())
          System.debug(
            LoggingLevel.ERROR,
            'AI Assist: a platform log event was not published from ' +
              customMessageLogEvent.ClassName__c +
              '.'
          );
      }
    } catch (Exception loggingFailure) {
      System.debug(
        LoggingLevel.ERROR,
        'AI Assist: a log entry could not be built.'
      ); // Logging must never be the cause of a failure, and the text is never repeated here.
    }
  }
}
