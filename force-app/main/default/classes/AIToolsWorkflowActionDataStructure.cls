/*
Class Name: AIToolsWorkflowActionDataStructure

=================================================================
=================================================================

Description: The shapes the Workflow Actions panel of the AI Tools tab sends to and receives from Apex.

Step 1: ActionRow is one line of the list, with how it last tested
Step 2: ActionDetail is the whole action the wizard edits and saves
Step 3: FlowOption, FlowVariableOption and ApexClassOption are what the wizard lets the administrator choose from
Step 4: TestRequest and TestResult are what the Test step sends and gets back

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsWorkflowActionDataStructure {

    // One workflow action in the list.
    public class ActionRow {

        @AuraEnabled public Id actionId;
        @AuraEnabled public String actionName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String actionType; // Apex, Flow or Screen Flow.
        @AuraEnabled public String executionType; // Read Only or Write.
        @AuraEnabled public Boolean requiresConfirmation;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Integer agentCount = 0; // Active agents that have the action through an active assignment.
        @AuraEnabled public String lastTestStatus; // Passed or Failed, blank when never tested.
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public String attention; // Flow inactive or Flow changed, blank when the action needs no attention.
        @AuraEnabled public Boolean isActive;
    }

    // The whole action, as the wizard edits it.
    public class ActionDetail {

        @AuraEnabled public Id actionId; // Blank for a new action.
        @AuraEnabled public String actionName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String outputDescription;
        @AuraEnabled public String actionType;
        @AuraEnabled public String executionType;
        @AuraEnabled public String apexClassName;
        @AuraEnabled public String flowApiName;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Boolean requiresConfirmation;
        @AuraEnabled public String confirmationMessage;
        @AuraEnabled public String inputSchema; // JSON Schema text, see AIAssistApplicationConstants.WORKFLOW_SCHEMA_SOURCE_KEY.
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String lastTestStatus;
        @AuraEnabled public Datetime lastTestedOn;
        @AuraEnabled public Integer agentCount = 0;
    }

    // An active flow the administrator can pick.
    public class FlowOption {

        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public Integer versionNumber;
        @AuraEnabled public Integer inputCount = 0;
        @AuraEnabled public Datetime lastModified;
    }

    // One variable of a flow.
    public class FlowVariableOption {

        @AuraEnabled public String name;
        @AuraEnabled public String dataType; // Text, Number, Boolean, Date, DateTime, Record, Record collection or Other.
        @AuraEnabled public String objectType;
        @AuraEnabled public Boolean isInput;
        @AuraEnabled public Boolean isOutput;
        @AuraEnabled public Boolean isSupported; // True when an agent, the page or the server can fill it with a plain value.
    }

    // An Apex class that implements IAIWorkflowActionExecutor.
    public class ApexClassOption {

        @AuraEnabled public String className;
        @AuraEnabled public String inputSchema; // From describeInputs, blank when the class does not describe its inputs.
        @AuraEnabled public String inputNames; // The input names, comma separated, for the list.
        @AuraEnabled public String callouts; // What the class says it does that cannot be rolled back, blank when it says nothing.
    }

    // What the Test step sends: the record, the values for the inputs the agent fills, and whether to undo the test.
    public class TestRequest {

        @AuraEnabled public Id recordId;
        @AuraEnabled public Map<String, Object> inputValues = new Map<String, Object>();
        @AuraEnabled public Boolean shouldRollBack = true;
    }

    // One output of a test.
    public class OutputRow {

        @AuraEnabled public String name;
        @AuraEnabled public String value;
    }

    // How a test ended.
    public class TestResult {

        @AuraEnabled public String status; // Passed or Failed.
        @AuraEnabled public String message; // Why it failed, blank when it passed.
        @AuraEnabled public Long elapsedMilliseconds;
        @AuraEnabled public Integer recordsChanged = 0;
        @AuraEnabled public Boolean isRolledBack = false;
        @AuraEnabled public List<OutputRow> outputs = new List<OutputRow>();
        @AuraEnabled public List<String> warnings = new List<String>(); // Things that happened and could not be undone.
    }
}
