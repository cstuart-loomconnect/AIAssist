/*
Class Name: AIWorkflowActionDispatcher

=================================================================
=================================================================

Description: Runs one Workflow Action a user has chosen to run from a suggestion in the chat. The counterpart of AIDataSourceDispatcher, with the extra care an action that can change data needs.

Step 1: Check the application is on and the user may run Workflow Actions on this agent
Step 2: Read the action in system mode and check it is active and assigned to the agent
Step 3: Check the user has confirmed, when the action requires it
Step 4: Keep only the inputs the action declares, and set recordId from the server
Step 5: Run the Apex class, or check the user can reach every record and start the Flow
Step 6: Record a Success, Failed or Blocked step on the reply the action was suggested on, then return the output or throw the refusal
Step 7: For a Screen Flow, make the same checks, hand the window the flow and its inputs, and record how it ended

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIWorkflowActionDispatcher {

    public class AIWorkflowActionDispatcherException extends Exception {}

    private static final String FLOW_OUTPUT_VARIABLE_NAME = 'output'; // A convention: Apex cannot discover a Flow's declared outputs.

    // Runs the action and records what happened. Every refusal is an exception whose message is a Custom Label; the user never sees class or flow names. messageId is the reply the action was suggested on, where the evidence is recorded. recordId may be null for an action that does not work on a record.
    public static Object runWorkflowAction(Id workflowActionId, Id agentId, Id messageId, Id recordId, Map<String, Object> inputParameters, Boolean isConfirmed) {

        AIWorkflowAction__c action = null;
        Boolean hasRun = false;
        Long startedAt = System.currentTimeMillis();
        Object output = null;
        Exception problem = null;

        try {

            // [1] Check the application, the setting, the agent and the assignment, and read the action
            action = getPermittedAction(workflowActionId, agentId);

            // [2] An action that requires confirmation runs only when the user has confirmed
            if (action.RequiresConfirmation__c == true && isConfirmed != true) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Confirmation_Required);

            // [3] Keep only the inputs the action declares; the browser can send anything
            Map<String, Object> parameters = filterDeclaredInputs(action.InputSchema__c, inputParameters, workflowActionId);

            // [4] Remove recordId: it is the conversation's record and nothing else, even when the schema declares an input of that name
            for (String declaredName : parameters.keySet().clone()) {

                if (declaredName.equalsIgnoreCase('recordId')) parameters.remove(declaredName);
            }

            hasRun = true;

            if (action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX) {

                // [5] An Apex action needs a class name
                if (String.isBlank(action.ApexClassName__c)) {

                    AIPlatformLogManager.logCustomMessage('Action ' + action.DeveloperName__c + ' has no Apex class.', null, 'AIWorkflowActionDispatcher', 'runWorkflowAction', null);

                    throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);
                }

                // [6] Check the class implements the interface before anything in it runs, because the name was typed by a subscriber and even constructing a class runs its code. The empty namespace finds the subscriber's own unprefixed classes; the one-argument form looks only in the package's namespace once this is managed code
                Type apexType = Type.forName('', action.ApexClassName__c.trim());

                if (apexType == null || !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)) {

                    AIPlatformLogManager.logCustomMessage('Apex class ' + action.ApexClassName__c + ' was not found or does not implement IAIWorkflowActionExecutor.', null, 'AIWorkflowActionDispatcher', 'runWorkflowAction', null);

                    throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);
                }

                // [7] Find the conversation the action was suggested in
                List<AIConversationMessage__c> suggestingMessages = messageId == null ? new List<AIConversationMessage__c>() : [SELECT AIConversation__c FROM AIConversationMessage__c WHERE Id = :messageId WITH SYSTEM_MODE LIMIT 1];

                // [8] Build the request the class receives
                AIWorkflowActionRequest request = new AIWorkflowActionRequest();
                request.recordId = recordId;
                request.inputParameters = new Map<String, Object>(parameters);
                request.conversationId = suggestingMessages.isEmpty() ? null : suggestingMessages[0].AIConversation__c;
                request.agentId = agentId;
                request.userId = UserInfo.getUserId();
                request.actionName = action.DeveloperName__c;
                request.isConfirmed = isConfirmed == true;

                // [9] Run the class in the user's transaction, with the sharing it declares for itself
                AIWorkflowActionResponse response = ((IAIWorkflowActionExecutor) apexType.newInstance()).execute(request);
                output = response == null ? null : response.message;

            } else if (action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW) {

                // [10] A Flow action needs a Flow name
                if (String.isBlank(action.FlowAPIName__c)) {

                    AIPlatformLogManager.logCustomMessage('Action ' + action.DeveloperName__c + ' has no Flow.', null, 'AIWorkflowActionDispatcher', 'runWorkflowAction', null);

                    throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);
                }

                // [11] Build the Flow inputs, with the conversation's record as recordId
                Map<String, Object> flowInputs = new Map<String, Object>(parameters);

                if (recordId != null) flowInputs.put('recordId', recordId);

                // [12] Note every input that is a record Id. A value that is not a record Id is not a record and is passed as it is
                Map<Id, String> inputNameByRecordId = new Map<Id, String>();

                for (String inputName : flowInputs.keySet()) {

                    Id passedId = flowInputs.get(inputName) instanceof Id || flowInputs.get(inputName) instanceof String ? AIChatDataStructure.getIdOrNull(String.valueOf(flowInputs.get(inputName))) : null;

                    if (passedId != null) inputNameByRecordId.put(passedId, inputName);
                }

                // [13] A Flow started from Apex does not run as the user: it runs in system context, so the user's object and field permissions are not applied. Check here that the user can read each record it is handed, or edit it when the action writes
                Boolean isWrite = action.ExecutionType__c == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
                Set<Id> refusedRecordIds = inputNameByRecordId.keySet().clone();

                if (refusedRecordIds.size() <= AIAssistApplicationConstants.MAX_FLOW_RECORD_INPUTS) {

                    for (UserRecordAccess access : [SELECT RecordId, HasReadAccess, HasEditAccess FROM UserRecordAccess WHERE UserId = :UserInfo.getUserId() AND RecordId IN :inputNameByRecordId.keySet() WITH SYSTEM_MODE]) {

                        if (isWrite ? access.HasEditAccess : access.HasReadAccess) refusedRecordIds.remove(access.RecordId);
                    }
                }

                // [14] Refuse, and log which inputs, when the user cannot reach a record. The Flow does not start
                if (!refusedRecordIds.isEmpty()) {

                    List<String> refusedInputs = new List<String>();

                    for (Id refusedRecordId : refusedRecordIds) refusedInputs.add(inputNameByRecordId.get(refusedRecordId) + ' = ' + refusedRecordId);

                    AIPlatformLogManager.logCustomMessage('Flow action ' + action.DeveloperName__c + ' was not run: user ' + UserInfo.getUserId() + ' has no ' + (isWrite ? 'edit' : 'read') + ' access to a record passed to the Flow.', 'Share the record with the user, or change the action so it does not pass it. Inputs refused: ' + String.join(refusedInputs, ', ').abbreviate(900), 'AIWorkflowActionDispatcher', 'runWorkflowAction', workflowActionId);
                    hasRun = false;

                    throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Not_Permitted);
                }

                // [15] Start the Flow and read its output
                Flow.Interview interview = Flow.Interview.createInterview(action.FlowAPIName__c, flowInputs);
                interview.start();
                output = interview.getVariableValue(FLOW_OUTPUT_VARIABLE_NAME);

            } else {

                // [16] Any other action type is not supported
                AIPlatformLogManager.logCustomMessage('Action ' + action.DeveloperName__c + ' has an unsupported type.', null, 'AIWorkflowActionDispatcher', 'runWorkflowAction', null);

                throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);
            }

        } catch (Exception ex) {

            // [17] Log a system error in full and show the user only the Action Failed label; a refusal of our own is passed on as it is
            if (ex.getTypeName().startsWith('System.')) {

                AIPlatformLogManager.logException(ex, 'AIWorkflowActionDispatcher', 'runWorkflowAction');
                problem = new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);

            } else {

                problem = ex;
            }
        }

        // [18] Work out the outcome: Success, Failed (it ran and failed) or Blocked (refused before it ran)
        String status = problem == null ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS : (hasRun && problem.getMessage() == Label.AI_Error_Action_Failed ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_BLOCKED);

        // [19] Record the outcome on the reply; a refusal before the action was even read has nothing to attach the evidence to
        AIExecutionStepRecorder.recordWorkflowActionStep(messageId, action, recordId, status, isConfirmed, System.currentTimeMillis() - startedAt);

        // [20] Pass on the refusal, or return the output
        if (problem != null) throw problem;

        return output;
    }

    // A Screen Flow cannot run from Apex, so it is shown in the window, where it runs as the user and the platform applies the user's own permissions. This makes the same checks as an action that runs on the server and hands the window the flow and its inputs. recordId is the conversation's record and nothing else.
    public static AIChatDataStructure.ScreenFlowLaunch prepareScreenFlow(Id workflowActionId, Id agentId, Id recordId, Map<String, Object> inputParameters, Boolean isConfirmed) {

        // [1] Make the checks every action starts with
        AIWorkflowAction__c action = getPermittedAction(workflowActionId, agentId);

        // [2] Only a Screen Flow with a flow name is shown in the window
        if (action.ActionType__c != AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW || String.isBlank(action.FlowAPIName__c)) {

            AIPlatformLogManager.logCustomMessage('Action ' + action.DeveloperName__c + ' is not a Screen Flow with a Flow name.', null, 'AIWorkflowActionDispatcher', 'prepareScreenFlow', workflowActionId);

            throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Failed);
        }

        // [3] An action that requires confirmation starts only when the user has confirmed
        if (action.RequiresConfirmation__c == true && isConfirmed != true) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Confirmation_Required);

        // [4] Keep only the declared inputs, and never a recordId from the browser
        Map<String, Object> parameters = filterDeclaredInputs(action.InputSchema__c, inputParameters, workflowActionId);

        for (String declaredName : parameters.keySet().clone()) {

            if (declaredName.equalsIgnoreCase('recordId')) parameters.remove(declaredName);
        }

        // [5] Build the input variables, with the conversation's record as recordId
        AIChatDataStructure.ScreenFlowLaunch launch = new AIChatDataStructure.ScreenFlowLaunch();
        launch.flowApiName = action.FlowAPIName__c.trim();

        for (String inputName : parameters.keySet()) {

            launch.inputVariables.add(buildFlowVariable(inputName, parameters.get(inputName), getDeclaredType(action.InputSchema__c, inputName)));
        }

        if (recordId != null) launch.inputVariables.add(new Map<String, Object>{ 'name' => 'recordId', 'type' => 'String', 'value' => String.valueOf(recordId) });

        // [6] Return what the window needs
        return launch;
    }

    // The window reports how the Screen Flow ended: Finished, Error or Cancelled. This is the evidence on the reply. It is the browser's word, so it can only record a step on a Screen Flow action that is assigned to the agent, never run anything.
    public static void recordScreenFlowOutcome(Id workflowActionId, Id agentId, Id messageId, Id recordId, String outcome, Boolean isConfirmed) {

        // [1] Only an active Screen Flow action assigned to the agent has a step to record
        AIWorkflowAction__c action = getAssignedAction(workflowActionId, agentId);

        if (action == null || action.ActionType__c != AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW) return;

        // [2] Finished is a Success, Error is Failed, and anything else means the user closed it first
        String status = outcome == 'FINISHED' ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS : outcome == 'ERROR' ? AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED : AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED;

        // [3] Record it on the reply the action was suggested on
        AIExecutionStepRecorder.recordWorkflowActionStep(messageId, action, recordId, status, isConfirmed, null);
    }

    // The JSON Schema type of one declared input, or string when the schema does not say.
    private static String getDeclaredType(String inputSchema, String inputName) {

        try {

            Map<String, Object> properties = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(inputSchema)).get('properties');
            Map<String, Object> property = (Map<String, Object>) properties.get(inputName);

            String jsonType = property.get('type') == null ? 'string' : String.valueOf(property.get('type'));
            String format = property.get('format') == null ? null : String.valueOf(property.get('format'));

            return jsonType == 'integer' || jsonType == 'number' ? 'Number' : jsonType == 'boolean' ? 'Boolean' : format == 'date' ? 'Date' : format == 'date-time' ? 'DateTime' : 'String';

        } catch (Exception ex) {
            return 'String';
        }
    }

    // One input in the shape lightning-flow takes. A value that does not fit its declared type is passed as text, which the Flow then rejects as it would any bad input.
    private static Map<String, Object> buildFlowVariable(String inputName, Object value, String flowType) {

        Object typedValue = value;

        try {

            if (value == null) typedValue = null;
            else if (flowType == 'Number') typedValue = value instanceof Decimal || value instanceof Integer || value instanceof Long ? value : (Object) Decimal.valueOf(String.valueOf(value));
            else if (flowType == 'Boolean') typedValue = value instanceof Boolean ? value : (Object) Boolean.valueOf(String.valueOf(value));
            else typedValue = String.valueOf(value);

        } catch (Exception ex) {

            flowType = 'String';
            typedValue = String.valueOf(value);
        }

        return new Map<String, Object>{ 'name' => inputName, 'type' => flowType, 'value' => typedValue };
    }

    // The checks every run of an action starts with, whether it runs on the server or in the window as a Screen Flow. Returns the action, or throws a refusal that is a Custom Label.
    private static AIWorkflowAction__c getPermittedAction(Id workflowActionId, Id agentId) {

        // [1] Report the application switch first: with AI Assist off nothing else matters
        if (!AIAssistSettingsService.isEnabled()) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Application_Inactive);

        // [2] The UI settings must switch Workflow Actions on for this user
        if (AIAssistSettingsService.getUiSettings().IsWorkflowActionsEnabled__c != true) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Not_Permitted);

        // [3] Make the same access check the message validator makes: an inactive agent, or one the user has since been removed from, runs nothing
        AIAgent__c agent = getAgent(agentId);

        if (agent == null || agent.IsActive__c != true || !AIMessageValidator.isUserAllowedOnAgent(agent, UserInfo.getUserId())) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Not_Permitted);

        // [4] Read the action in system mode: it must be active and assigned to the agent through an active assignment
        AIWorkflowAction__c action = getAssignedAction(workflowActionId, agentId);

        if (action == null) throw new AIWorkflowActionDispatcherException(Label.AI_Error_Action_Not_Permitted);

        // [5] Return the action
        return action;
    }

    // The user declined at the confirmation. Nothing ran; this is the evidence that it was offered and refused.
    public static void recordDeclinedAction(Id workflowActionId, Id agentId, Id messageId, Id recordId) {

        // [1] Record a Cancelled step on the reply the action was suggested on
        AIExecutionStepRecorder.recordWorkflowActionStep(messageId, getAssignedAction(workflowActionId, agentId), recordId, AIAssistApplicationConstants.EXECUTION_STEP_STATUS_CANCELLED, false, 0);
    }

    // Keeps only the inputs InputSchema__c declares as properties. The values come from the browser, which can send anything, so a key the action never asked for is not passed on. A blank or malformed schema declares nothing, so nothing is passed. Dropped names are logged (never their values, which may be personal data).
    @TestVisible
    private static Map<String, Object> filterDeclaredInputs(String inputSchema, Map<String, Object> submittedInputs, Id workflowActionId) {

        // [1] Nothing submitted, so nothing to keep
        Map<String, Object> declaredInputs = new Map<String, Object>();

        if (submittedInputs == null || submittedInputs.isEmpty()) return declaredInputs;

        // [2] Read the names the schema declares as properties
        Set<String> declaredNames = new Set<String>();

        if (String.isNotBlank(inputSchema)) {

            try {

                Object properties = ((Map<String, Object>) JSON.deserializeUntyped(inputSchema)).get('properties');

                if (properties instanceof Map<String, Object>) declaredNames.addAll(((Map<String, Object>) properties).keySet());

            } catch (Exception ex) {
                declaredNames.clear(); // Nothing is declared, so nothing is passed.
            }
        }

        // [3] Keep the declared inputs and note the rest
        List<String> droppedNames = new List<String>();

        for (String submittedName : submittedInputs.keySet()) {

            if (declaredNames.contains(submittedName)) {
                declaredInputs.put(submittedName, submittedInputs.get(submittedName));
            } else {
                droppedNames.add(submittedName);
            }
        }

        // [4] Log the names that were dropped
        if (!droppedNames.isEmpty()) {

            droppedNames.sort();
            AIPlatformLogManager.logCustomMessage('Inputs not declared by the action were dropped.', String.join(droppedNames, ', ').abbreviate(1000), 'AIWorkflowActionDispatcher', 'filterDeclaredInputs', workflowActionId);
        }

        // [5] Return the declared inputs
        return declaredInputs;
    }

    // Returns the agent with the fields the chat needs, or null when there is no such agent. It must see the agent whoever is asking.
    @TestVisible
    private static AIAgent__c getAgent(Id agentId) {

        // [1] No agent Id, no agent
        if (agentId == null) return null;

        // [2] Read the agent
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, AIAgentPersona__c, IsActive__c, AccessMode__c, AIModelConfiguration__c, MaxMessagesPerConversation__c, MaxTokensPerConversation__c, MaxToolCallingIterations__c, SingleActiveConversationPerRecord__c, TokenTrackingMethod__c FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];

        // [3] Return it, or null when there is none
        return agents.isEmpty() ? null : agents[0];
    }

    // One action the agent may offer: active, and linked to the agent through an active assignment. Null when it is neither.
    @TestVisible
    private static AIWorkflowAction__c getAssignedAction(Id actionId, Id agentId) {

        // [1] Both Ids are needed
        if (actionId == null || agentId == null) return null;

        // [2] Read the action if it is active and actively assigned to the agent
        List<AIWorkflowAction__c> actions = [SELECT Id, DeveloperName__c, ActionName__c, ActionType__c, ExecutionType__c, ApexClassName__c, FlowAPIName__c, TargetObject__c, RequiresConfirmation__c, InputSchema__c FROM AIWorkflowAction__c WHERE Id = :actionId AND IsActive__c = TRUE AND Id IN (SELECT AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE) WITH SYSTEM_MODE LIMIT 1];

        // [3] Return it, or null when there is none
        return actions.isEmpty() ? null : actions[0];
    }
}
