/*
Class Name: AIExecutionStepRecorder

=================================================================
=================================================================

Description: Saves the execution steps (and masking records) for a turn that has just ended, as audit evidence.

Step 1: Skip the turn when there is no message, no steps, or step capture is Off
Step 2: Find the last provider call, the only one that carries the debug payloads
Step 3: Build one execution step per tracker entry
Step 4: Save the steps, logging any that fail
Step 5: Build one masking record per masked field under each saved step
Step 6: Save the masking records, logging any that fail

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIExecutionStepRecorder {
  // providerName and modelIdentifier label a Provider Call step the tracker did not label itself; the object model refuses one without both.
  public static void recordExecutionSteps(
    Id messageId,
    AIExecutionStepTracker executionTrace,
    String providerName,
    String modelIdentifier
  ) {
    try {
      // [1] Nothing to record when there is no message or no steps, or when capture is Off (a Workflow Action a user runs is still recorded by recordWorkflowActionStep)
      if (
        messageId == null ||
        executionTrace == null ||
        executionTrace.steps.isEmpty() ||
        AIAssistSettingsService.getSettings().StepCaptureMode__c ==
        AIAssistApplicationConstants.STEP_CAPTURE_OFF
      )
        return;

      // [2] Find the last provider call, because only that call keeps its payloads
      Integer lastProviderCallIndex = -1;

      for (
        Integer traceIndex = 0;
        traceIndex < executionTrace.steps.size();
        traceIndex++
      ) {
        // [3] A step the tracker did not label is a data source step when it names a data source, and a provider call otherwise
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
        // [4] Work out the step type the same way, then build the step with the fields every type shares
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

        // [5] Add the provider evidence to a provider call: names, counts and whether masking ran, never values
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

          // [6] Keep the payloads only in Full capture mode and only on the last call, because they are customer data and large
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

        // [7] Add the target and confirmation details to a workflow action
        if (type == AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION) {
          executionStep.TargetRecordId__c = entry.targetRecordId;
          executionStep.RequiredConfirmation__c = entry.requiredConfirmation;
          executionStep.ConfirmedBy__c = entry.confirmedBy;
          executionStep.ConfirmedDate__c = entry.confirmedDate;
        }

        stepsToInsert.add(executionStep);
      }

      // [8] Save the steps, logging any that fail
      AIMessagingDataService.insertAndLogFailures(
        stepsToInsert,
        'AIExecutionStepRecorder',
        'recordExecutionSteps'
      );

      // [9] Build one row per masked field under the step that sent the data (names and counts only, written once)
      List<AIPIIMaskingRecord__c> maskingRecords = new List<AIPIIMaskingRecord__c>();

      for (
        Integer maskingStepIndex = 0;
        maskingStepIndex < executionTrace.steps.size();
        maskingStepIndex++
      ) {
        // [10] Skip a step that did not save, because there is nothing to attach evidence to
        if (stepsToInsert[maskingStepIndex].Id == null)
          continue;

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

      // [11] Save the masking records, logging any that fail
      AIMessagingDataService.insertAndLogFailures(
        maskingRecords,
        'AIExecutionStepRecorder',
        'recordExecutionSteps'
      );
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
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
      // [1] Nothing to record without a message and an action
      if (messageId == null || action == null)
        return;

      // [2] Find the highest step order already on the message, so the new step goes last
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

      // [3] Count it as confirmed only when the user confirmed an action that asks for confirmation
      Boolean isConfirmed =
        wasConfirmed == true &&
        action.RequiresConfirmation__c == true;

      // [4] Save the step, logging any failure
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
    } catch (Exception ex) {
      AIPlatformLogManager.logException(
        ex,
        'AIExecutionStepRecorder',
        'recordWorkflowActionStep'
      );
    }
  }

  // Cuts a value to the field's size, because an over-length value fails the whole insert and would lose the evidence row with it.
  private static String truncate(String value, Integer maxLength) {
    // [1] Cut the value to the length, keeping null as null
    return value == null ? null : value.left(maxLength);
  }
}
