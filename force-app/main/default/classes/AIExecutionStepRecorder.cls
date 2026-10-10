/*
Class Name: AIExecutionStepRecorder

=================================================================
=================================================================

Description: Saves what ran to produce a reply as one JSON trace on the message (AIConversationMessage__c.ExecutionTraceJson__c), plus the masking records, as audit evidence.

Step 1: Skip the turn when there is no message, no steps, or the user has step capture off
Step 2: Find the last provider call, the only one that carries the iteration counts and the debug payloads
Step 3: Build one trace entry per tracker entry
Step 4: Trim the middle of an over-long trace so it fits the field
Step 5: Save the trace and, in Full capture mode, the debug payloads on the message
Step 6: Build and save one masking record per masked field, against the message and the step that masked it
Step 7: Append a workflow action the user runs later to the end of the saved trace

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
2.0          Chandler Stuart          One JSON trace on the message replaces a record per step
*/

public without sharing class AIExecutionStepRecorder {

    private static final Integer OMISSION_ENTRY_ALLOWANCE = 200; // Room kept for the entry that says how many steps were taken out.

    // One step of the trace as it is stored. The user sees only stepType, status, ms and stepDetail; the rest is for administrators and for the chat window to work out sources and whether an action has run. Names only, never values.
    public class TraceStep {
        public Integer step;
        public String stepType;
        public String status;
        public Long ms;
        public String stepDetail;
        public String dataSource;
        public String targetObject;
        public String provider;
        public String model;
        public Decimal recordsSent;
        public Decimal fieldsSentCount;
        public String objectsSent;
        public String fieldsSent;
        public Integer iterationsUsed;
        public Integer iterationsMax;
        public Integer attempt;
        public String workflowActionId;
        public String workflowActionName;
        public String targetRecordId;
        public Boolean requiredConfirmation;
        public String confirmedBy;
        public Datetime confirmedDate;
    }

    // Saves the trace of a turn. providerName and modelIdentifier label a Provider Call step the tracker did not label itself.
    public static void recordExecutionSteps(Id messageId, AIExecutionStepTracker executionTrace, String providerName, String modelIdentifier) {

        try {

            // [1] Do nothing when there is no message or no steps, or when the user has step capture off (a workflow action a user runs is still recorded by recordWorkflowActionStep)
            if (messageId == null || executionTrace == null || executionTrace.steps.isEmpty() || !executionTrace.shouldCaptureSteps) return;

            // [2] Find the last provider call, because only that call keeps its iteration counts and payloads
            Integer lastProviderCallIndex = -1;

            for (Integer traceIndex = 0; traceIndex < executionTrace.steps.size(); traceIndex++) {

                if (getStepType(executionTrace.steps[traceIndex]) == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL) lastProviderCallIndex = traceIndex;
            }

            List<TraceStep> traceSteps = new List<TraceStep>();

            for (Integer stepIndex = 0; stepIndex < executionTrace.steps.size(); stepIndex++) {

                // [3] Build the entry with the fields every type shares
                AIExecutionStepTracker.StepEntry entry = executionTrace.steps[stepIndex];
                String type = getStepType(entry);

                TraceStep traceStep = new TraceStep();
                traceStep.step = stepIndex + 1;
                traceStep.stepType = type;
                traceStep.status = String.isNotBlank(entry.status) ? entry.status : (entry.isSuccess ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED);
                traceStep.ms = entry.durationMilliseconds;
                traceStep.stepDetail = truncate(entry.stepDetail, AIAssistApplicationConstants.STEP_DETAIL_LENGTH);
                traceStep.dataSource = entry.dataSourceName;
                traceStep.targetObject = entry.targetObject;

                // [4] For a provider call, add the evidence of what was sent: names and counts, never the values
                if (type == AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL) {

                    traceStep.provider = String.isNotBlank(entry.provider) ? entry.provider : providerName;
                    traceStep.model = String.isNotBlank(entry.modelIdentifier) ? entry.modelIdentifier : modelIdentifier;
                    traceStep.recordsSent = entry.recordsSentCount;
                    traceStep.fieldsSentCount = entry.fieldsSentCount;
                    traceStep.objectsSent = truncate(entry.objectsSent, AIAssistApplicationConstants.STEP_OBJECTS_SENT_LENGTH);
                    traceStep.fieldsSent = truncate(entry.fieldsSent, AIAssistApplicationConstants.STEP_FIELDS_SENT_LENGTH);

                    if (stepIndex == lastProviderCallIndex) {

                        traceStep.iterationsUsed = executionTrace.toolCallingIterationsUsed;
                        traceStep.iterationsMax = executionTrace.toolCallingIterationsMax;
                        traceStep.attempt = executionTrace.attemptNumber;
                    }
                }

                // [5] For a workflow action, add the action and the confirmation details
                if (type == AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION) {

                    traceStep.workflowActionId = entry.workflowActionId == null ? null : String.valueOf(entry.workflowActionId);
                    traceStep.workflowActionName = entry.workflowActionName;
                    traceStep.targetRecordId = entry.targetRecordId;
                    traceStep.requiredConfirmation = entry.requiredConfirmation;
                    traceStep.confirmedBy = entry.confirmedBy == null ? null : String.valueOf(entry.confirmedBy);
                    traceStep.confirmedDate = entry.confirmedDate;
                }

                traceSteps.add(traceStep);
            }

            // [6] Save the trace on the message. The payloads go in their own fields, and only in Full capture mode and from the last call, because they hold customer data and are large.
            AIConversationMessage__c message = new AIConversationMessage__c(Id = messageId, ExecutionTraceJson__c = serializeTrace(traceSteps));

            if (executionTrace.captureFullDetail) {

                message.DebugRequestJson__c = truncate(executionTrace.lastRequestJson, AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH);
                message.DebugResponseJson__c = truncate(executionTrace.lastResponseJson, AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH);
                message.DebugSentPreviewText__c = truncate(executionTrace.sentPreviewText, AIAssistApplicationConstants.STEP_SENT_PREVIEW_LENGTH);
            }

            AIMessagingDataService.updateAndLogFailures(new List<SObject>{ message }, 'AIExecutionStepRecorder', 'recordExecutionSteps');

            // [7] Build one record per masked field, against the message and the step that masked it (names and counts only, written once)
            List<AIPIIMaskingRecord__c> maskingRecords = new List<AIPIIMaskingRecord__c>();

            for (Integer maskingStepIndex = 0; maskingStepIndex < executionTrace.steps.size(); maskingStepIndex++) {

                for (AIExecutionStepTracker.MaskingEntry maskingEntry : executionTrace.steps[maskingStepIndex].maskingEntries) {

                    maskingRecords.add(new AIPIIMaskingRecord__c(AIConversationMessage__c = messageId, StepOrder__c = maskingStepIndex + 1, SourceObject__c = maskingEntry.sourceObject, SourceField__c = maskingEntry.sourceField, PIIFieldType__c = maskingEntry.piiFieldType, ComplianceGroup__c = maskingEntry.complianceGroup, MaskingStrategy__c = maskingEntry.maskingStrategy, ValuesMasked__c = maskingEntry.valuesMasked, Outcome__c = String.isBlank(maskingEntry.outcome) ? AIAssistApplicationConstants.MASKING_OUTCOME_MASKED : maskingEntry.outcome));
                }
            }

            // [8] Save the masking records, logging any that fail
            AIMessagingDataService.insertAndLogFailures(maskingRecords, 'AIExecutionStepRecorder', 'recordExecutionSteps');

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIExecutionStepRecorder', 'recordExecutionSteps');
        }
    }

    // Adds the evidence of one workflow action to the end of the message's trace, whatever came of it: Success, Failed, Blocked (refused before it ran) or Cancelled (declined at the confirmation). Never throws.
    public static void recordWorkflowActionStep(Id messageId, AIWorkflowAction__c action, Id recordId, String status, Boolean wasConfirmed, Long durationMilliseconds) {

        try {

            // [1] Do nothing without a message and an action
            if (messageId == null || action == null) return;

            // [2] Lock the message while the trace is read and written, so two actions confirmed together do not overwrite each other
            List<AIConversationMessage__c> messages = [SELECT Id, ExecutionTraceJson__c FROM AIConversationMessage__c WHERE Id = :messageId WITH SYSTEM_MODE LIMIT 1 FOR UPDATE];
            if (messages.isEmpty()) return;

            List<TraceStep> traceSteps = parseTrace(messages[0].ExecutionTraceJson__c);

            // [3] Find the highest step number already on the message, so the new step goes last
            Integer highestStep = 0;

            for (TraceStep existingStep : traceSteps) {

                if (existingStep.step != null && existingStep.step > highestStep) highestStep = existingStep.step;
            }

            // [4] Count it as confirmed only when the user confirmed an action that asks for confirmation
            Boolean isConfirmed = wasConfirmed == true && action.RequiresConfirmation__c == true;
            String actionName = String.isBlank(action.ActionName__c) ? 'the suggested action' : action.ActionName__c;

            TraceStep actionStep = new TraceStep();
            actionStep.step = highestStep + 1;
            actionStep.stepType = AIAssistApplicationConstants.STEP_TYPE_WORKFLOW_ACTION;
            actionStep.status = status;
            actionStep.ms = durationMilliseconds;
            actionStep.stepDetail = getWorkflowActionDetail(actionName, action.TargetObject__c, status);
            actionStep.targetObject = action.TargetObject__c;
            actionStep.workflowActionId = String.valueOf(action.Id);
            actionStep.workflowActionName = actionName;
            actionStep.targetRecordId = recordId == null ? null : String.valueOf(recordId);
            actionStep.requiredConfirmation = action.RequiresConfirmation__c == true;
            actionStep.confirmedBy = isConfirmed ? String.valueOf(UserInfo.getUserId()) : null;
            actionStep.confirmedDate = isConfirmed ? System.now() : null;
            traceSteps.add(actionStep);

            // [5] Save the trace, logging any failure
            messages[0].ExecutionTraceJson__c = serializeTrace(traceSteps);
            AIMessagingDataService.updateAndLogFailures(new List<SObject>{ messages[0] }, 'AIExecutionStepRecorder', 'recordWorkflowActionStep');

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AIExecutionStepRecorder', 'recordWorkflowActionStep');
        }
    }

    // Reads a saved trace. Blank or unreadable text gives an empty list, so a damaged trace never breaks the chat.
    public static List<TraceStep> parseTrace(String traceJson) {

        // [1] Nothing saved is an empty trace
        if (String.isBlank(traceJson)) return new List<TraceStep>();

        // [2] Read the entries, oldest first
        try {

            return (List<TraceStep>) JSON.deserialize(traceJson, List<TraceStep>.class);

        } catch (Exception ex) {

            return new List<TraceStep>();
        }
    }

    // Turns the trace into the text that is stored. If it would not fit the field, entries are taken out after the first quarter (keeping the start and the end) and one entry says how many.
    @TestVisible
    private static String serializeTrace(List<TraceStep> traceSteps) {

        // [1] Serialise each entry without empty values to keep the trace small, and add up the length once
        List<String> entryJsons = new List<String>();
        Integer totalLength = 2;

        for (TraceStep traceStep : traceSteps) {

            String entryJson = JSON.serialize(traceStep, true);
            entryJsons.add(entryJson);
            totalLength += entryJson.length() + 1;
        }

        // [2] Everything fits, so keep it all
        if (totalLength <= AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH) return '[' + String.join(entryJsons, ',') + ']';

        // [3] Take entries out just after the first quarter until what is left fits, leaving room for the entry that says how many went
        Integer omitAt = Math.max(1, entryJsons.size() / 4);
        Integer removedCount = 0;

        while (totalLength > AIAssistApplicationConstants.STEP_JSON_FIELD_LENGTH - OMISSION_ENTRY_ALLOWANCE && entryJsons.size() > 4) {

            Integer removeIndex = Math.min(omitAt, entryJsons.size() - 2);
            totalLength -= entryJsons[removeIndex].length() + 1;
            entryJsons.remove(removeIndex);
            removedCount++;
        }

        // [4] Say how many were taken out, in the place they were taken from
        TraceStep omittedStep = new TraceStep();
        omittedStep.stepType = AIAssistApplicationConstants.STEP_TYPE_OTHER;
        omittedStep.status = AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS;
        omittedStep.stepDetail = removedCount + ' steps are not shown because the trace was too long.';
        entryJsons.add(Math.min(omitAt, entryJsons.size() - 1), JSON.serialize(omittedStep, true));

        return '[' + String.join(entryJsons, ',') + ']';
    }

    // The plain wording for a workflow action step. It names the action and the object, never the record's values.
    private static String getWorkflowActionDetail(String actionName, String targetObject, String status) {

        // [1] Say what came of the action
        String onObject = String.isBlank(targetObject) ? '' : ' on ' + targetObject;

        if (status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS) return 'Ran ' + actionName + onObject + '.';
        if (status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED) return actionName + onObject + ' failed.';
        if (status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED) return actionName + onObject + ' was blocked before it ran.';
        if (status == AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED) return 'The user declined ' + actionName + onObject + '.';

        return actionName + onObject + '.';
    }

    // A step the tracker did not label is a data source step when it names a data source, and a provider call otherwise.
    private static String getStepType(AIExecutionStepTracker.StepEntry entry) {

        // [1] Use the label when there is one
        if (String.isNotBlank(entry.stepType)) return entry.stepType;

        // [2] Otherwise work it out
        return entry.dataSourceId != null ? AIAssistApplicationConstants.STEP_TYPE_DATA_SOURCE : AIAssistApplicationConstants.STEP_TYPE_PROVIDER_CALL;
    }

    // Cuts a value to the field's size, because an over-length value fails the whole update and would lose the evidence with it.
    private static String truncate(String value, Integer maxLength) {

        // [1] Cut the value to the length, keeping null as null
        return value == null ? null : value.left(maxLength);
    }
}
