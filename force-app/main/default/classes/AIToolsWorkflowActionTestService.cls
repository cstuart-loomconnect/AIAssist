/*
Class Name: AIToolsWorkflowActionTestService

=================================================================
=================================================================

Description: Runs a workflow action once from the AI Tools tab, the way the chat would, and undoes it afterwards unless the administrator switched Roll back off in a sandbox.

Step 1: Refuse a test that cannot be run safely: a screen flow, no record, or no roll back outside a sandbox
Step 2: Build the inputs the way the dispatcher does, with the page, user and fixed inputs filled by the server
Step 3: Run the Apex class or start the flow
Step 4: Read the outputs and what was changed, then roll back
Step 5: Return how it ended

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsWorkflowActionTestService {

    public class AIToolsWorkflowActionTestServiceException extends Exception {}

    private static final String APEX_OUTPUT_NAME = 'message';
    private static final String RECORD_ID_NAME = 'recordId';
    private static final String FLOW_OUTPUT_SUCCESS = 'isSuccess';
    private static final String FLOW_OUTPUT_ERROR = 'errorMessage';

    // Runs the action as it is in the wizard, which need not be saved. A refusal is an exception whose message is a Custom Label; a run that fails is a result with status Failed.
    public static AIToolsWorkflowActionDataStructure.TestResult runTest(AIToolsWorkflowActionDataStructure.ActionDetail detail, AIToolsWorkflowActionDataStructure.TestRequest request) {

        // [1] Refuse a user who may not use the tab, and a test with nothing to test
        AIAssistSettingsEditorService.requireManager();
        if (detail == null || request == null) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Not_Found);

        // [2] A screen flow needs a person to finish it
        Boolean isApex = detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
        if (detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Screen_Flow_No_Test);

        // [3] Without a roll back, only a sandbox may run it
        Boolean isSandbox = [SELECT IsSandbox FROM Organization WITH SYSTEM_MODE LIMIT 1].IsSandbox;
        if (request.shouldRollBack != true && !isSandbox) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Rollback_Sandbox);

        // [4] A class that says it does things that cannot be undone is only tested in a sandbox
        if (isApex && !isSandbox && String.isNotBlank(detail.apexClassName) && String.isNotBlank(AIToolsWorkflowActionEditorService.buildApexClassOption(detail.apexClassName).callouts)) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Callouts_Sandbox);

        // [5] An action with a page input needs a record to run on
        Map<String, Object> parameters = buildParameters(detail.inputSchema, request.inputValues);
        if (request.recordId == null && hasPageInput(detail.inputSchema)) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Record_Required);

        // [6] A flow must have an active version
        if (!isApex && !hasActiveVersion(detail.flowApiName)) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Flow_Inactive);

        // [7] Note where things stand, then run
        AIToolsWorkflowActionDataStructure.TestResult result = new AIToolsWorkflowActionDataStructure.TestResult();
        Savepoint startPoint = Database.setSavepoint();
        Integer rowsBefore = Limits.getDmlRows();
        Integer emailsBefore = Limits.getEmailInvocations();
        Integer calloutsBefore = Limits.getCallouts();
        Long startedAt = System.currentTimeMillis();
        Exception failure;

        try {

            if (isApex) runApexClass(detail, request, parameters, result);
            else runFlow(detail, request, parameters, result);

            result.status = AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED;

        } catch (Exception ex) {

            result.status = AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_FAILED;
            failure = ex;

            result.message = String.format(Label.AI_ToolsWa_Error_Test_Failed, new List<String>{ex.getMessage()});
        }

        // [8] Say what was changed and what cannot be undone
        result.elapsedMilliseconds = System.currentTimeMillis() - startedAt;
        result.recordsChanged = Limits.getDmlRows() - rowsBefore;
        if (Limits.getEmailInvocations() > emailsBefore) result.warnings.add('Email was sent. It cannot be rolled back.');
        if (Limits.getCallouts() > calloutsBefore) result.warnings.add('A callout was made. It cannot be rolled back.');

        // [8b] An action set to Read Only must not change records
        if (result.status == AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_PASSED && detail.executionType == AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY && result.recordsChanged > 0) {

            result.status = AIAssistApplicationConstants.WORKFLOW_TEST_STATUS_FAILED;
            result.message = String.format(Label.AI_ToolsWa_Error_ReadOnly_Changed, new List<String>{String.valueOf(result.recordsChanged)});
        }

        // [9] Undo it unless the administrator asked to keep it
        if (request.shouldRollBack == true) {

            Database.rollback(startPoint);
            result.isRolledBack = true;
        }

        // [10] Log a platform error, such as one from inside a packaged flow. This comes after the roll back, which would otherwise undo the log
        if (failure != null && failure.getTypeName().startsWith('System.')) AIPlatformLogManager.logException(failure, 'AIToolsWorkflowActionTestService', 'runTest');

        return result;
    }

    // Builds the inputs the way the dispatcher does: only what the schema declares, with the server's own inputs filled in, and never a recordId from the tab.
    private static Map<String, Object> buildParameters(String inputSchema, Map<String, Object> suppliedValues) {

        // [1] Keep only the inputs the schema declares as properties
        Map<String, Object> declaredValues = new Map<String, Object>();
        Set<String> declaredNames = new Set<String>();

        if (String.isNotBlank(inputSchema)) {

            Object properties = ((Map<String, Object>) JSON.deserializeUntyped(inputSchema)).get('properties');
            if (properties instanceof Map<String, Object>) declaredNames.addAll(((Map<String, Object>) properties).keySet());
        }

        for (String suppliedName : suppliedValues == null ? new Set<String>() : suppliedValues.keySet()) {

            if (declaredNames.contains(suppliedName)) declaredValues.put(suppliedName, suppliedValues.get(suppliedName));
        }

        // [2] Fill the inputs the server owns, then take out recordId, which is the record and nothing else
        Map<String, Object> parameters = AIWorkflowActionDispatcher.applyServerFilledInputs(inputSchema, declaredValues);

        for (String parameterName : parameters.keySet().clone()) {

            if (parameterName.equalsIgnoreCase(RECORD_ID_NAME)) parameters.remove(parameterName);
        }

        return parameters;
    }

    // True when the schema has an input the page fills.
    private static Boolean hasPageInput(String inputSchema) {

        // [1] No schema, no page input
        if (String.isBlank(inputSchema)) return false;

        // [2] Look for an input whose source is the page
        Object properties = ((Map<String, Object>) JSON.deserializeUntyped(inputSchema)).get('properties');

        if (!(properties instanceof Map<String, Object>)) return false;

        for (Object property : ((Map<String, Object>) properties).values()) {

            if (property instanceof Map<String, Object> && ((Map<String, Object>) property).get(AIAssistApplicationConstants.WORKFLOW_SCHEMA_SOURCE_KEY) == AIAssistApplicationConstants.WORKFLOW_INPUT_SOURCE_PAGE) return true;
        }

        return false;
    }

    // True when the flow has an active version.
    private static Boolean hasActiveVersion(String flowApiName) {

        // [1] Look for the active version
        Integer activeCount = [SELECT COUNT() FROM FlowDefinitionView WHERE ApiName = :flowApiName AND IsActive = TRUE WITH SYSTEM_MODE];

        return activeCount > 0;
    }

    // Runs the Apex class the way the dispatcher does and records its message.
    private static void runApexClass(AIToolsWorkflowActionDataStructure.ActionDetail detail, AIToolsWorkflowActionDataStructure.TestRequest request, Map<String, Object> parameters, AIToolsWorkflowActionDataStructure.TestResult result) {

        // [1] Check the class implements the interface before any of its code runs
        Type apexType = String.isBlank(detail.apexClassName) ? null : Type.forName('', detail.apexClassName.trim());
        if (apexType == null || !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)) throw new AIToolsWorkflowActionTestServiceException(Label.AI_ToolsWa_Error_Source_Invalid);

        // [2] Build the request the class receives
        AIWorkflowActionRequest actionRequest = new AIWorkflowActionRequest();
        actionRequest.recordId = request.recordId;
        actionRequest.inputParameters = new Map<String, Object>(parameters);
        actionRequest.userId = UserInfo.getUserId();
        actionRequest.actionName = detail.developerName;
        actionRequest.isConfirmed = true;

        // [3] Run it and keep the message
        AIWorkflowActionResponse response = ((IAIWorkflowActionExecutor) apexType.newInstance()).execute(actionRequest);
        AIToolsWorkflowActionDataStructure.OutputRow outputRow = new AIToolsWorkflowActionDataStructure.OutputRow();
        outputRow.name = APEX_OUTPUT_NAME;
        outputRow.value = response == null ? null : response.message;
        result.outputs.add(outputRow);
    }

    // Starts the flow the way the dispatcher does and reads its output variables.
    private static void runFlow(AIToolsWorkflowActionDataStructure.ActionDetail detail, AIToolsWorkflowActionDataStructure.TestRequest request, Map<String, Object> parameters, AIToolsWorkflowActionDataStructure.TestResult result) {

        // [1] Build the flow inputs, with the record as recordId
        Map<String, Object> flowInputs = new Map<String, Object>(parameters);
        if (request.recordId != null) flowInputs.put(RECORD_ID_NAME, request.recordId);

        // [2] Start the flow
        Flow.Interview interview = AIWorkflowActionDispatcher.createFlowInterview(detail.flowApiName, flowInputs);
        interview.start();

        // [3] Read each output variable the flow declares
        for (AIToolsWorkflowActionDataStructure.FlowVariableOption variable : AIToolsWorkflowActionEditorService.getFlowVariables(detail.flowApiName)) {

            if (variable.isOutput != true) continue;

            Object outputValue = interview.getVariableValue(variable.name);
            AIToolsWorkflowActionDataStructure.OutputRow outputRow = new AIToolsWorkflowActionDataStructure.OutputRow();
            outputRow.name = variable.name;
            outputRow.value = outputValue == null ? null : String.valueOf(outputValue);
            result.outputs.add(outputRow);
        }

        // [4] A flow that handled its own failure still ends normally, so read the usual signals: isSuccess set to false, or an errorMessage
        for (AIToolsWorkflowActionDataStructure.OutputRow outputRow : result.outputs) {

            if (outputRow.name == FLOW_OUTPUT_SUCCESS && outputRow.value == 'false') throw new AIToolsWorkflowActionTestServiceException(getFlowErrorText(result.outputs));
            if (outputRow.name == FLOW_OUTPUT_ERROR && String.isNotBlank(outputRow.value)) throw new AIToolsWorkflowActionTestServiceException(outputRow.value);
        }
    }

    // The text of the flow's errorMessage output, or a plain sentence when it has none.
    private static String getFlowErrorText(List<AIToolsWorkflowActionDataStructure.OutputRow> outputs) {

        for (AIToolsWorkflowActionDataStructure.OutputRow outputRow : outputs) {

            if (outputRow.name == FLOW_OUTPUT_ERROR && String.isNotBlank(outputRow.value)) return outputRow.value;
        }

        return FLOW_OUTPUT_SUCCESS + ' was false.';
    }
}
