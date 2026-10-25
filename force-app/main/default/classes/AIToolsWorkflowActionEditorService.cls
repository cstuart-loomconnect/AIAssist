/*
Class Name: AIToolsWorkflowActionEditorService

=================================================================
=================================================================

Description: Reads, checks and saves the Workflow Actions the Workflow Actions panel of the AI Tools tab edits, and lists the flows and Apex classes it can choose from.

Step 1: Read every action with its agent count and how its flow stands now
Step 2: List the active flows, a flow's variables, and the Apex classes that implement IAIWorkflowActionExecutor
Step 3: Check and save one action, creating it when it is new
Step 4: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsWorkflowActionEditorService {

    public class AIToolsWorkflowActionEditorServiceException extends Exception {}

    private static final String VARIABLE_TYPE_TEXT = 'Text';
    private static final String VARIABLE_TYPE_NUMBER = 'Number';
    private static final String VARIABLE_TYPE_BOOLEAN = 'Boolean';
    private static final String VARIABLE_TYPE_DATE = 'Date';
    private static final String VARIABLE_TYPE_DATE_TIME = 'DateTime';
    private static final String VARIABLE_TYPE_RECORD = 'Record';
    private static final String VARIABLE_TYPE_RECORD_COLLECTION = 'Record collection';
    private static final String VARIABLE_TYPE_OTHER = 'Other';
    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');
    private static final Pattern CLASS_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z][A-Za-z0-9_]*)?$');

    // Every workflow action, for the list. The ones that need attention are marked.
    public static List<AIToolsWorkflowActionDataStructure.ActionRow> getActions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the actions
        Integer maxResults = AIAssistApplicationConstants.WORKFLOW_LIST_MAX_RESULTS;
        List<AIWorkflowAction__c> actions = [SELECT Id, ActionName__c, DeveloperName__c, ActionType__c, ExecutionType__c, RequiresConfirmation__c, TargetObject__c, FlowAPIName__c, IsActive__c, LastTestStatus__c, LastTestedOn__c, TestedFlowVersion__c FROM AIWorkflowAction__c WITH SYSTEM_MODE ORDER BY ActionName__c LIMIT :maxResults];

        // [3] Look up how many agents use each action, and how each flow stands now
        Map<Id, Integer> agentCountByActionId = getAgentCounts(new Map<Id, AIWorkflowAction__c>(actions).keySet());
        Set<String> flowApiNames = new Set<String>();

        for (AIWorkflowAction__c action : actions) {

            if (String.isNotBlank(action.FlowAPIName__c)) flowApiNames.add(action.FlowAPIName__c);
        }

        Map<String, Integer> activeVersionByFlowName = getActiveVersions(flowApiNames);

        // [4] Build one row per action
        List<AIToolsWorkflowActionDataStructure.ActionRow> rows = new List<AIToolsWorkflowActionDataStructure.ActionRow>();

        for (AIWorkflowAction__c action : actions) {

            rows.add(buildRow(action, agentCountByActionId.get(action.Id), activeVersionByFlowName));
        }

        return rows;
    }

    // One action with everything the wizard edits.
    public static AIToolsWorkflowActionDataStructure.ActionDetail getAction(Id actionId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the action
        AIWorkflowAction__c action = findAction(actionId);

        // [3] Build the detail
        AIToolsWorkflowActionDataStructure.ActionDetail detail = new AIToolsWorkflowActionDataStructure.ActionDetail();
        detail.actionId = action.Id;
        detail.actionName = action.ActionName__c;
        detail.developerName = action.DeveloperName__c;
        detail.description = action.Description__c;
        detail.outputDescription = action.OutputDescription__c;
        detail.actionType = action.ActionType__c;
        detail.executionType = action.ExecutionType__c;
        detail.apexClassName = action.ApexClassName__c;
        detail.flowApiName = action.FlowAPIName__c;
        detail.targetObject = action.TargetObject__c;
        detail.requiresConfirmation = action.RequiresConfirmation__c == true;
        detail.confirmationMessage = action.ConfirmationMessage__c;
        detail.inputSchema = action.InputSchema__c;
        detail.isActive = action.IsActive__c == true;
        detail.lastTestStatus = action.LastTestStatus__c;
        detail.lastTestedOn = action.LastTestedOn__c;
        detail.agentCount = getAgentCounts(new Set<Id>{action.Id}).get(action.Id);

        return detail;
    }

    // The active flows of one kind, newest change first. A screen flow is a flow with screens; every other flow listed is autolaunched.
    public static List<AIToolsWorkflowActionDataStructure.FlowOption> getFlows(Boolean isScreenFlow) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the active flows of the right kind
        String processType = isScreenFlow == true ? AIAssistApplicationConstants.FLOW_PROCESS_TYPE_SCREEN : AIAssistApplicationConstants.FLOW_PROCESS_TYPE_AUTOLAUNCHED;
        Integer maxResults = AIAssistApplicationConstants.WORKFLOW_FLOW_LIST_MAX_RESULTS;
        List<FlowDefinitionView> flows = [SELECT ApiName, Label, VersionNumber, ActiveVersionId, LastModifiedDate FROM FlowDefinitionView WHERE IsActive = TRUE AND ProcessType = :processType WITH SYSTEM_MODE ORDER BY LastModifiedDate DESC LIMIT :maxResults];

        // [3] Count the input variables of each version
        Map<String, Integer> inputCountByVersionId = new Map<String, Integer>();
        Set<String> versionIds = new Set<String>();

        for (FlowDefinitionView flow : flows) versionIds.add(flow.ActiveVersionId);

        for (FlowVariableView variable : [SELECT FlowVersionViewId FROM FlowVariableView WHERE FlowVersionViewId IN :versionIds AND IsInput = TRUE WITH SYSTEM_MODE]) {

            Integer currentCount = inputCountByVersionId.get(variable.FlowVersionViewId);
            inputCountByVersionId.put(variable.FlowVersionViewId, currentCount == null ? 1 : currentCount + 1);
        }

        // [4] Build one option per flow
        List<AIToolsWorkflowActionDataStructure.FlowOption> options = new List<AIToolsWorkflowActionDataStructure.FlowOption>();

        for (FlowDefinitionView flow : flows) {

            AIToolsWorkflowActionDataStructure.FlowOption option = new AIToolsWorkflowActionDataStructure.FlowOption();
            option.apiName = flow.ApiName;
            option.label = flow.Label;
            option.versionNumber = flow.VersionNumber;
            option.inputCount = inputCountByVersionId.containsKey(flow.ActiveVersionId) ? inputCountByVersionId.get(flow.ActiveVersionId) : 0;
            option.lastModified = flow.LastModifiedDate;
            options.add(option);
        }

        return options;
    }

    // The variables of the active version of one flow, with whether each can be filled with a plain value.
    public static List<AIToolsWorkflowActionDataStructure.FlowVariableOption> getFlowVariables(String flowApiName) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Find the active version
        List<AIToolsWorkflowActionDataStructure.FlowVariableOption> options = new List<AIToolsWorkflowActionDataStructure.FlowVariableOption>();
        List<FlowDefinitionView> flows = [SELECT ActiveVersionId FROM FlowDefinitionView WHERE ApiName = :flowApiName AND IsActive = TRUE WITH SYSTEM_MODE LIMIT 1];

        if (flows.isEmpty()) return options;

        // [3] Build one option per input or output variable
        for (FlowVariableView variable : [SELECT ApiName, DataType, IsCollection, IsInput, IsOutput, ObjectType FROM FlowVariableView WHERE FlowVersionViewId = :flows[0].ActiveVersionId WITH SYSTEM_MODE ORDER BY ApiName]) {

            // FlowVariableView does not allow OR in a filter, so a variable that is neither an input nor an output is skipped here
            if (variable.IsInput != true && variable.IsOutput != true) continue;

            String dataType = getVariableType(variable.DataType, variable.IsCollection == true);

            AIToolsWorkflowActionDataStructure.FlowVariableOption option = new AIToolsWorkflowActionDataStructure.FlowVariableOption();
            option.name = variable.ApiName;
            option.dataType = dataType;
            option.objectType = variable.ObjectType;
            option.isInput = variable.IsInput == true;
            option.isOutput = variable.IsOutput == true;
            option.isSupported = dataType == VARIABLE_TYPE_TEXT || dataType == VARIABLE_TYPE_NUMBER || dataType == VARIABLE_TYPE_BOOLEAN || dataType == VARIABLE_TYPE_DATE || dataType == VARIABLE_TYPE_DATE_TIME;
            options.add(option);
        }

        return options;
    }

    // The Apex classes that implement IAIWorkflowActionExecutor, with what each says about its inputs.
    public static List<AIToolsWorkflowActionDataStructure.ApexClassOption> getApexClasses() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Find the classes that implement the interface
        String interfaceName = AIAssistApplicationConstants.INTERFACE_WORKFLOW_ACTION_EXECUTOR;
        List<AIToolsWorkflowActionDataStructure.ApexClassOption> options = new List<AIToolsWorkflowActionDataStructure.ApexClassOption>();

        for (ApexTypeImplementor implementor : [SELECT ClassName, ClassNamespacePrefix FROM ApexTypeImplementor WHERE InterfaceName = :interfaceName AND IsConcrete = TRUE WITH SYSTEM_MODE ORDER BY ClassName]) {

            String qualifiedName = String.isBlank(implementor.ClassNamespacePrefix) ? implementor.ClassName : implementor.ClassNamespacePrefix + '.' + implementor.ClassName;
            options.add(buildApexClassOption(qualifiedName));
        }

        return options;
    }

    // Describes one class. A class that also implements IAIWorkflowActionInputDescriber is asked for its inputs; a class that throws, or returns text that is not a schema, is listed as describing nothing.
    public static AIToolsWorkflowActionDataStructure.ApexClassOption buildApexClassOption(String className) {

        // [1] Start with a class that says nothing about itself
        AIToolsWorkflowActionDataStructure.ApexClassOption option = new AIToolsWorkflowActionDataStructure.ApexClassOption();
        option.className = className;
        Type apexType = Type.forName('', className);

        if (apexType == null || !IAIWorkflowActionInputDescriber.class.isAssignableFrom(apexType)) return option;

        try {

            // [2] Ask the class for its inputs
            String describedSchema = ((IAIWorkflowActionInputDescriber) apexType.newInstance()).describeInputs();
            Map<String, Object> schema = (Map<String, Object>) JSON.deserializeUntyped(describedSchema);
            option.inputSchema = describedSchema;

            // [3] Note the input names, in alphabetical order
            Object properties = schema.get('properties');
            if (properties instanceof Map<String, Object>) {

                List<String> inputNames = new List<String>(((Map<String, Object>) properties).keySet());
                inputNames.sort();
                option.inputNames = String.join(inputNames, ', ');
            }

            // [4] Note what the class says it does that cannot be rolled back
            Object callouts = schema.get(AIAssistApplicationConstants.WORKFLOW_SCHEMA_CALLOUTS_KEY);
            if (callouts instanceof List<Object>) option.callouts = String.join((List<Object>) callouts, ', ');
            else if (callouts != null) option.callouts = String.valueOf(callouts);

        } catch (Exception ex) {

            option.inputSchema = null;
            option.inputNames = null;
            option.callouts = null;
        }

        return option;
    }

    // Saves one action, creating it when actionId is blank, and returns it as a list row.
    public static AIToolsWorkflowActionDataStructure.ActionRow saveAction(AIToolsWorkflowActionDataStructure.ActionDetail detail) {

        // [1] Refuse a user who may not use the tab, and a save with nothing to save
        AIAssistSettingsEditorService.requireManager();
        if (detail == null) throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Not_Found);

        // [2] Check what the action is
        checkDetail(detail);

        // [3] Find the action, or start a new one
        AIWorkflowAction__c action = detail.actionId == null ? new AIWorkflowAction__c() : findAction(detail.actionId);
        Boolean isApex = detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
        Boolean isScreenFlow = detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW;

        // [4] Put the values on the action. Only the field that matches the type is filled, so the other is cleared
        action.ActionName__c = detail.actionName.trim();
        action.DeveloperName__c = detail.developerName.trim();
        action.Description__c = detail.description;
        action.OutputDescription__c = detail.outputDescription;
        action.ActionType__c = detail.actionType;
        action.ExecutionType__c = detail.executionType;
        action.ApexClassName__c = isApex ? detail.apexClassName.trim() : null;
        action.FlowAPIName__c = isApex ? null : detail.flowApiName.trim();
        action.TargetObject__c = String.isBlank(detail.targetObject) ? null : detail.targetObject.trim();
        action.RequiresConfirmation__c = isScreenFlow ? detail.requiresConfirmation == true : detail.requiresConfirmation == true || detail.executionType == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
        action.ConfirmationMessage__c = action.RequiresConfirmation__c ? detail.confirmationMessage : null;
        action.InputSchema__c = detail.inputSchema;
        action.IsActive__c = detail.isActive == true;

        // [5] Keep how it last tested, and which flow version that was
        action.LastTestStatus__c = String.isBlank(detail.lastTestStatus) ? null : detail.lastTestStatus;
        action.LastTestedOn__c = String.isBlank(detail.lastTestStatus) ? null : System.now();
        action.TestedFlowVersion__c = isApex || String.isBlank(detail.lastTestStatus) ? null : getActiveVersions(new Set<String>{action.FlowAPIName__c}).get(action.FlowAPIName__c);

        // [6] Save it, turning a refusal by the platform into a message the tab can show
        try {

            upsert action;

        } catch (DmlException ex) {

            Boolean isDuplicate = ex.getDmlType(0) == StatusCode.DUPLICATE_VALUE;
            throw new AIToolsWorkflowActionEditorServiceException(isDuplicate ? Label.AI_ToolsWa_Error_Duplicate : ex.getDmlMessage(0));
        }

        // [7] Read it back as a row
        AIWorkflowAction__c saved = findAction(action.Id);
        Map<Id, Integer> agentCountByActionId = getAgentCounts(new Set<Id>{saved.Id});

        return buildRow(saved, agentCountByActionId.get(saved.Id), getActiveVersions(new Set<String>{saved.FlowAPIName__c}));
    }

    // Checks the parts of an action that the object's own rules do not explain well, so the administrator reads a clear message.
    private static void checkDetail(AIToolsWorkflowActionDataStructure.ActionDetail detail) {

        // [1] A name, an API name and a description are needed
        if (String.isBlank(detail.actionName)) throw new AIToolsWorkflowActionEditorServiceException(String.format(Label.AI_ToolsWa_Error_Required, new List<String>{Schema.AIWorkflowAction__c.ActionName__c.getDescribe().getLabel()}));
        if (String.isBlank(detail.developerName) || !API_NAME_PATTERN.matcher(detail.developerName.trim()).matches()) throw new AIToolsWorkflowActionEditorServiceException(String.format(Label.AI_ToolsWa_Error_Required, new List<String>{Schema.AIWorkflowAction__c.DeveloperName__c.getDescribe().getLabel()}));
        if (String.isBlank(detail.description)) throw new AIToolsWorkflowActionEditorServiceException(String.format(Label.AI_ToolsWa_Error_Required, new List<String>{Schema.AIWorkflowAction__c.Description__c.getDescribe().getLabel()}));

        // [2] The type and whether it changes data must be ones the object lists
        Set<String> actionTypes = new Set<String>{AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW};
        Set<String> executionTypes = new Set<String>{AIAssistApplicationConstants.WORKFLOW_EXECUTION_READ_ONLY, AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE};
        if (!actionTypes.contains(detail.actionType) || !executionTypes.contains(detail.executionType)) throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Type_Invalid);

        // [3] An Apex class must exist and implement the interface, without running any of its code
        if (detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX) {

            Type apexType = String.isBlank(detail.apexClassName) || !CLASS_NAME_PATTERN.matcher(detail.apexClassName.trim()).matches() ? null : Type.forName('', detail.apexClassName.trim());
            if (apexType == null || !IAIWorkflowActionExecutor.class.isAssignableFrom(apexType)) throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Source_Invalid);

        } else {

            // [4] A flow must have a name; a flow that is no longer active can still be saved as it is, and the list flags it
            if (String.isBlank(detail.flowApiName) || !API_NAME_PATTERN.matcher(detail.flowApiName.trim()).matches()) throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Source_Invalid);
        }

        // [5] A confirmation needs a message
        Boolean isScreenFlow = detail.actionType == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW;
        Boolean needsConfirmation = detail.requiresConfirmation == true || (!isScreenFlow && detail.executionType == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE);
        if (needsConfirmation && String.isBlank(detail.confirmationMessage)) throw new AIToolsWorkflowActionEditorServiceException(String.format(Label.AI_ToolsWa_Error_Required, new List<String>{Schema.AIWorkflowAction__c.ConfirmationMessage__c.getDescribe().getLabel()}));

        // [6] The input schema must be a JSON object when there is one
        if (String.isNotBlank(detail.inputSchema)) {

            try {

                JSON.deserializeUntyped(detail.inputSchema);

            } catch (Exception ex) {

                throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Source_Invalid);
            }
        }
    }

    // Builds one list row, and works out whether the action needs attention because of its flow.
    private static AIToolsWorkflowActionDataStructure.ActionRow buildRow(AIWorkflowAction__c action, Integer agentCount, Map<String, Integer> activeVersionByFlowName) {

        // [1] Copy the action's details
        AIToolsWorkflowActionDataStructure.ActionRow row = new AIToolsWorkflowActionDataStructure.ActionRow();
        row.actionId = action.Id;
        row.actionName = action.ActionName__c;
        row.developerName = action.DeveloperName__c;
        row.actionType = action.ActionType__c;
        row.executionType = action.ExecutionType__c;
        row.requiresConfirmation = action.RequiresConfirmation__c == true;
        row.targetObject = action.TargetObject__c;
        row.agentCount = agentCount == null ? 0 : agentCount;
        row.lastTestStatus = action.LastTestStatus__c;
        row.lastTestedOn = action.LastTestedOn__c;
        row.isActive = action.IsActive__c == true;

        // [2] A flow with no active version cannot run. A flow whose active version is not the one that was tested has changed since
        if (String.isNotBlank(action.FlowAPIName__c)) {

            Integer activeVersion = activeVersionByFlowName.get(action.FlowAPIName__c);

            if (activeVersion == null) row.attention = AIAssistApplicationConstants.WORKFLOW_ATTENTION_FLOW_INACTIVE;
            else if (action.TestedFlowVersion__c != null && action.TestedFlowVersion__c.intValue() != activeVersion) row.attention = AIAssistApplicationConstants.WORKFLOW_ATTENTION_FLOW_CHANGED;
        }

        return row;
    }

    // Reads one action, or refuses when it is gone.
    private static AIWorkflowAction__c findAction(Id actionId) {

        // [1] Read it
        List<AIWorkflowAction__c> actions = actionId == null ? new List<AIWorkflowAction__c>() : [SELECT Id, ActionName__c, DeveloperName__c, Description__c, OutputDescription__c, ActionType__c, ExecutionType__c, ApexClassName__c, FlowAPIName__c, TargetObject__c, RequiresConfirmation__c, ConfirmationMessage__c, InputSchema__c, IsActive__c, LastTestStatus__c, LastTestedOn__c, TestedFlowVersion__c FROM AIWorkflowAction__c WHERE Id = :actionId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse when there is none
        if (actions.isEmpty()) throw new AIToolsWorkflowActionEditorServiceException(Label.AI_ToolsWa_Error_Not_Found);

        return actions[0];
    }

    // How many active agents have each action through an active assignment.
    private static Map<Id, Integer> getAgentCounts(Set<Id> actionIds) {

        // [1] Collect the distinct agents of each action
        Map<Id, Set<Id>> agentIdsByActionId = new Map<Id, Set<Id>>();

        for (AIAgentWorkflowAction__c assignment : [SELECT AIWorkflowAction__c, AIAgent__c FROM AIAgentWorkflowAction__c WHERE AIWorkflowAction__c IN :actionIds AND IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE]) {

            if (!agentIdsByActionId.containsKey(assignment.AIWorkflowAction__c)) agentIdsByActionId.put(assignment.AIWorkflowAction__c, new Set<Id>());

            agentIdsByActionId.get(assignment.AIWorkflowAction__c).add(assignment.AIAgent__c);
        }

        // [2] Count them
        Map<Id, Integer> agentCountByActionId = new Map<Id, Integer>();

        for (Id actionId : actionIds) {

            agentCountByActionId.put(actionId, agentIdsByActionId.containsKey(actionId) ? agentIdsByActionId.get(actionId).size() : 0);
        }

        return agentCountByActionId;
    }

    // The active version number of each flow that has one. A flow with none is missing from the map.
    private static Map<String, Integer> getActiveVersions(Set<String> flowApiNames) {

        // [1] Read the active versions
        Map<String, Integer> activeVersionByFlowName = new Map<String, Integer>();

        if (flowApiNames.isEmpty()) return activeVersionByFlowName;

        for (FlowDefinitionView flow : [SELECT ApiName, VersionNumber FROM FlowDefinitionView WHERE ApiName IN :flowApiNames AND IsActive = TRUE WITH SYSTEM_MODE]) {

            activeVersionByFlowName.put(flow.ApiName, flow.VersionNumber);
        }

        return activeVersionByFlowName;
    }

    // Turns a flow variable's data type into the plain name the tab shows.
    private static String getVariableType(String dataType, Boolean isCollection) {

        // [1] A record, or a collection of records
        if (dataType == 'SObject') return isCollection ? VARIABLE_TYPE_RECORD_COLLECTION : VARIABLE_TYPE_RECORD;

        // [2] A collection of anything else cannot be filled with a plain value
        if (isCollection) return VARIABLE_TYPE_OTHER;

        // [3] The plain types
        if (dataType == 'String' || dataType == 'Picklist') return VARIABLE_TYPE_TEXT;
        if (dataType == 'Number' || dataType == 'Currency') return VARIABLE_TYPE_NUMBER;
        if (dataType == 'Boolean') return VARIABLE_TYPE_BOOLEAN;
        if (dataType == 'Date') return VARIABLE_TYPE_DATE;
        if (dataType == 'DateTime') return VARIABLE_TYPE_DATE_TIME;

        return VARIABLE_TYPE_OTHER;
    }
}
