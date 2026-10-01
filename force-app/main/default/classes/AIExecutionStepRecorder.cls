/*
Class Name: AIExecutionStepRecorder

=================================================================
=================================================================

Description: Turns one AIExecutionStepTracker into the AIExecutionStep__c rows (and the
AIPIIMaskingRecord__c rows under them) for a turn that has just ended.

This is audit evidence, so it is written for every turn, successful or failed, and whether or
not debug mode is on:
- A Provider Call step carries the provider and model, how many records and fields were sent, the
  object and field NAMES (never values), and whether masking ran. One AIPIIMaskingRecord__c is
  written per masked field.
- Data Source and Workflow Action steps carry their target and outcome.
- The request, response and sent preview are the only debug-only part: captured when the
  tracker's captureFullDetail is on, and only on the last provider call, because the tracker
  only ever holds the most recent call's.

Steps are children of a message: the AI reply when there is one, the user's message when the
turn failed. A step the object model would refuse (a provider call with no provider or model) is
logged and skipped; it never turns a finished answer into a failure.

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          Rebuilt for the object model: step types, provider evidence, masking records, every turn and failed turns, not only successful turns with debug on.
*/

public inherited sharing class AIExecutionStepRecorder {
  // providerName and modelIdentifier label a Provider Call step the tracker did not label itself; the object model refuses one without both.
  public static void recordExecutionSteps(
    Id messageId,
    AIExecutionStepTracker executionTrace,
    String providerName,
    String modelIdentifier
  ) {
    try {
      if (
        messageId == null ||
        executionTrace == null ||
        executionTrace.steps.isEmpty()
      )
        return;

      Integer lastProviderCallIndex = -1;
      for (
        Integer traceIndex = 0;
        traceIndex < executionTrace.steps.size();
        traceIndex++
      ) {
        // A step the tracker did not label is a data source step when it names a data source, a provider call otherwise.
        String traceStepType = String.isNotBlank(
            executionTrace.steps[traceIndex].stepType
          )
          ? executionTrace.steps[traceIndex].stepType
          : (executionTrace.steps[traceIndex].dataSourceId != null
              ? AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE
              : AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL);
        if (
          traceStepType == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL
        )
          lastProviderCallIndex = traceIndex;
      }

      List<AIExecutionStep__c> stepsToInsert = new List<AIExecutionStep__c>();

      for (
        Integer stepIndex = 0;
        stepIndex < executionTrace.steps.size();
        stepIndex++
      ) {
        AIExecutionStepTracker.StepEntry entry = executionTrace.steps[
          stepIndex
        ];
        String type = String.isNotBlank(entry.stepType)
          ? entry.stepType
          : (entry.dataSourceId != null
              ? AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE
              : AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL);

        AIExecutionStep__c executionStep = new AIExecutionStep__c(
          AIConversationMessage__c = messageId,
          StepType__c = type,
          AIDataSource__c = entry.dataSourceId,
          AIWorkflowAction__c = entry.workflowActionId,
          StepOrder__c = stepIndex + 1,
          Status__c = String.isNotBlank(entry.status)
            ? entry.status
            : (entry.isSuccess
                ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS
                : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED),
          DurationMilliseconds__c = entry.durationMilliseconds,
          ToolCallingIterationsUsed__c = executionTrace.toolCallingIterationsUsed,
          ToolCallingIterationsMax__c = executionTrace.toolCallingIterationsMax,
          AttemptNumber__c = executionTrace.attemptNumber,
          TargetObject__c = entry.targetObject
        );

        if (type == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL) {
          executionStep.Provider__c = String.isNotBlank(entry.provider)
            ? entry.provider
            : providerName;
          executionStep.ModelIdentifier__c = String.isNotBlank(
              entry.modelIdentifier
            )
            ? entry.modelIdentifier
            : modelIdentifier;
          executionStep.RecordsSentCount__c = entry.recordsSentCount;
          executionStep.FieldsSentCount__c = entry.fieldsSentCount;
          executionStep.ObjectsSent__c = truncate(
            entry.objectsSent,
            AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH
          );
          executionStep.FieldsSent__c = truncate(
            entry.fieldsSent,
            AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH
          );
          executionStep.PIIMaskingApplied__c = entry.piiMaskingApplied;

          // Payloads are customer data: kept only for a user with debug mode on, and only for the last call.
          if (
            executionTrace.captureFullDetail &&
            stepIndex == lastProviderCallIndex
          ) {
            executionStep.RequestJson__c = truncate(
              executionTrace.lastRequestJson,
              AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH
            );
            executionStep.ResponseJson__c = truncate(
              executionTrace.lastResponseJson,
              AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH
            );
            executionStep.SentPreviewText__c = truncate(
              executionTrace.sentPreviewText,
              AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH
            );
          }
        }

        if (type == AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION) {
          executionStep.TargetRecordId__c = entry.targetRecordId;
          executionStep.RequiredConfirmation__c = entry.requiredConfirmation;
          executionStep.ConfirmedBy__c = entry.confirmedBy;
          executionStep.ConfirmedDate__c = entry.confirmedDate;
        }

        stepsToInsert.add(executionStep);
      }

      AIMessagingDataService.insertAndLogFailures(
        stepsToInsert,
        'AIExecutionStepRecorder',
        'recordExecutionSteps'
      );

      // One row per masked field, under the step that sent the data. Names and counts only; write-once evidence.
      List<AIPIIMaskingRecord__c> maskingRecords = new List<AIPIIMaskingRecord__c>();

      for (
        Integer maskingStepIndex = 0;
        maskingStepIndex < executionTrace.steps.size();
        maskingStepIndex++
      ) {
        if (stepsToInsert[maskingStepIndex].Id == null)
          continue; // The step did not save, so there is nothing to attach evidence to.

        for (
          AIExecutionStepTracker.MaskingEntry maskingEntry : executionTrace.steps[
              maskingStepIndex
            ]
            .maskingEntries
        ) {
          maskingRecords.add(
            new AIPIIMaskingRecord__c(
              AIExecutionStep__c = stepsToInsert[maskingStepIndex].Id,
              SourceObject__c = maskingEntry.sourceObject,
              SourceField__c = maskingEntry.sourceField,
              PIIFieldType__c = maskingEntry.piiFieldType,
              ComplianceGroup__c = maskingEntry.complianceGroup,
              MaskingStrategy__c = maskingEntry.maskingStrategy,
              ValuesMasked__c = maskingEntry.valuesMasked,
              Outcome__c = String.isBlank(maskingEntry.outcome)
                ? AIAssistApplicationConstants.MASKING_OUTCOME_MASKED
                : maskingEntry.outcome
            )
          );
        }
      }

      AIMessagingDataService.insertAndLogFailures(
        maskingRecords,
        'AIExecutionStepRecorder',
        'recordExecutionSteps'
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIExecutionStepRecorder',
        'recordExecutionSteps'
      );
    }
  }

  // Evidence of one Workflow Action, whatever came of it: Success, Failed, Blocked (refused before it ran) or Cancelled (declined at the confirmation). Added after the steps the turn recorded. Never throws.
  public static void recordWorkflowActionStep(
    Id messageId,
    AIWorkflowAction__c action,
    Id recordId,
    String status,
    Boolean wasConfirmed,
    Long durationMilliseconds
  ) {
    try {
      if (messageId == null || action == null)
        return;

      List<AggregateResult> highestOrderRows = [
        SELECT MAX(StepOrder__c) highestOrder
        FROM AIExecutionStep__c
        WHERE AIConversationMessage__c = :messageId
        WITH SYSTEM_MODE
      ];
      Decimal highestOrder = highestOrderRows.isEmpty() ||
        highestOrderRows[0].get('highestOrder') == null
        ? 0
        : (Decimal) highestOrderRows[0].get('highestOrder');

      Boolean isConfirmed =
        wasConfirmed == true &&
        action.RequiresConfirmation__c == true;

      AIMessagingDataService.insertAndLogFailures(
        new List<SObject>{
          new AIExecutionStep__c(
            AIConversationMessage__c = messageId,
            StepType__c = AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION,
            AIWorkflowAction__c = action.Id,
            StepOrder__c = highestOrder + 1,
            Status__c = status,
            DurationMilliseconds__c = durationMilliseconds,
            TargetObject__c = action.TargetObject__c,
            TargetRecordId__c = recordId == null
              ? null
              : String.valueOf(recordId),
            RequiredConfirmation__c = action.RequiresConfirmation__c == true,
            ConfirmedBy__c = isConfirmed ? UserInfo.getUserId() : null,
            ConfirmedDate__c = isConfirmed ? System.now() : null
          )
        },
        'AIExecutionStepRecorder',
        'recordWorkflowActionStep'
      );
    } catch (Exception caughtException) {
      AIPlatformLogManager.logException(
        caughtException,
        'AIExecutionStepRecorder',
        'recordWorkflowActionStep'
      );
    }
  }

  // Cut to the field's size: an over-length value fails the whole insert and would lose the evidence row with it.
  private static String truncate(String value, Integer maxLength) {
    return value == null ? null : value.left(maxLength);
  }
}
