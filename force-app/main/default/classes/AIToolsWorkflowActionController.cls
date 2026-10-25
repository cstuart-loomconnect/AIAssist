/*
Class Name: AIToolsWorkflowActionController

=================================================================
=================================================================

Description: The Apex controller behind the Workflow Actions panel of the AI Tools tab.

Step 1: Read the list of workflow actions and one action in full
Step 2: List the flows, flow variables and Apex classes the wizard can choose from
Step 3: Save an action and test it
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsWorkflowActionController {

    public class AIToolsWorkflowActionControllerException extends Exception {}

    // Every workflow action, for the list.
    @AuraEnabled
    public static List<AIToolsWorkflowActionDataStructure.ActionRow> getActions() {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.getActions();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getActions');
        }
    }

    // One workflow action with everything the wizard edits.
    @AuraEnabled
    public static AIToolsWorkflowActionDataStructure.ActionDetail getAction(Id actionId) {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.getAction(actionId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAction');
        }
    }

    // The active flows to pick from: screen flows when isScreenFlow is true, otherwise autolaunched flows.
    @AuraEnabled
    public static List<AIToolsWorkflowActionDataStructure.FlowOption> getFlows(Boolean isScreenFlow) {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.getFlows(isScreenFlow);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getFlows');
        }
    }

    // The input and output variables of a flow.
    @AuraEnabled
    public static List<AIToolsWorkflowActionDataStructure.FlowVariableOption> getFlowVariables(String flowApiName) {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.getFlowVariables(flowApiName);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getFlowVariables');
        }
    }

    // The Apex classes that implement IAIWorkflowActionExecutor.
    @AuraEnabled
    public static List<AIToolsWorkflowActionDataStructure.ApexClassOption> getApexClasses() {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.getApexClasses();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getApexClasses');
        }
    }

    // Saves one workflow action, creating it when it is new, and returns it as a list row.
    @AuraEnabled
    public static AIToolsWorkflowActionDataStructure.ActionRow saveAction(Map<String, Object> actionDetail) {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionEditorService.saveAction(buildActionDetail(actionDetail));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveAction');
        }
    }

    // Runs the action once, as it is in the wizard, and rolls it back unless asked not to.
    @AuraEnabled
    public static AIToolsWorkflowActionDataStructure.TestResult runTest(Map<String, Object> actionDetail, Map<String, Object> testRequest) {

        try {

            // [1] Do the work
            return AIToolsWorkflowActionTestService.runTest(buildActionDetail(actionDetail), buildTestRequest(testRequest));

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'runTest');
        }
    }

    // Reads the action the tab sent as plain values. The tab sends plain values because the platform did not fill in a class passed straight from the page.
    private static AIToolsWorkflowActionDataStructure.ActionDetail buildActionDetail(Map<String, Object> values) {

        // [1] No values mean no action
        if (values == null) return null;

        // [2] Read the values into the class
        return (AIToolsWorkflowActionDataStructure.ActionDetail) JSON.deserialize(JSON.serialize(values), AIToolsWorkflowActionDataStructure.ActionDetail.class);
    }

    // Reads the test request the tab sent as plain values.
    private static AIToolsWorkflowActionDataStructure.TestRequest buildTestRequest(Map<String, Object> values) {

        // [1] No values mean no test request
        if (values == null) return null;

        // [2] Read the values into the class one by one, because JSON.deserialize cannot fill a Map of Object
        AIToolsWorkflowActionDataStructure.TestRequest testRequest = new AIToolsWorkflowActionDataStructure.TestRequest();
        Object recordId = values.get('recordId');
        Object shouldRollBack = values.get('shouldRollBack');
        Object inputValues = values.get('inputValues');

        if (recordId != null && String.isNotBlank(String.valueOf(recordId))) testRequest.recordId = Id.valueOf(String.valueOf(recordId));
        if (shouldRollBack instanceof Boolean) testRequest.shouldRollBack = (Boolean) shouldRollBack;
        if (inputValues instanceof Map<String, Object>) testRequest.inputValues = (Map<String, Object>) inputValues;

        return testRequest;
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIToolsWorkflowActionController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
