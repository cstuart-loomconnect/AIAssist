/*
Class Name: AIAgentWizardDataStructure

=================================================================
=================================================================

Description: The shapes the AI Agent Wizard tab (aiAgentWizard) sends to and receives from Apex.

Step 1: AgentDraft is the whole agent as the wizard holds it, and AssignmentView is one line of its access list
Step 2: CopyOption and the option classes fill the choices each step offers
Step 3: WizardPage carries all of those to the tab in one call
Step 4: Finding and DraftCheck carry what the checks found, and UserCheck, TryResult and SaveResult carry the access check, the trial run and the save
Step 5: AgentRow is one line of the list of agents the tab opens on

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardDataStructure {

    // One line of the access list: a person or a permission set that may use the agent.
    public class AssignmentView {

        @AuraEnabled public String assigneeType; // An AIAgentAssignment__c.AssigneeType__c value: User or Permission Set.
        @AuraEnabled public Id userId; // Set when the assignee type is User.
        @AuraEnabled public String permissionSetName; // The API name, set when the assignee type is Permission Set.
        @AuraEnabled public String label; // What the list shows: the user's name or the permission set's label.
        @AuraEnabled public Integer userCount; // Users the line covers: 1 for a user, the holders for a permission set.
        @AuraEnabled public Boolean isActive;
    }

    // The whole agent as the wizard holds it. The wizard sends it back to be checked, tried and saved.
    public class AgentDraft {

        // Basics
        @AuraEnabled public Id agentId; // Blank for an agent that is not saved yet.
        @AuraEnabled public String agentName;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String persona;
        @AuraEnabled public String greeting;
        @AuraEnabled public List<String> objectApiNames = new List<String>();
        @AuraEnabled public Id promptTemplateId; // Blank uses the default template.

        // Model
        @AuraEnabled public Id modelConfigurationId;

        // Data sources and workflow actions. Every id here is saved as an active link.
        @AuraEnabled public List<Id> dataSourceIds = new List<Id>();
        @AuraEnabled public List<Id> workflowActionIds = new List<Id>();

        // Conversations
        @AuraEnabled public String conversationLoadTrigger; // An AIAgent__c.ConversationLoadTrigger__c value.
        @AuraEnabled public Boolean allowConversationResume;
        @AuraEnabled public Boolean singleActiveConversationPerRecord;
        @AuraEnabled public String conversationVisibility; // Private or Global.
        @AuraEnabled public Decimal idleTimeoutMinutes;
        @AuraEnabled public Decimal conversationRetentionDays;
        @AuraEnabled public String retentionTrigger; // An AIAgent__c.RetentionTrigger__c value.

        // Limits
        @AuraEnabled public Decimal maxMessagesPerConversation;
        @AuraEnabled public Decimal maxTokensPerConversation;
        @AuraEnabled public Decimal maxToolCallingIterations;
        @AuraEnabled public String tokenTrackingMethod; // An AIAgent__c.TokenTrackingMethod__c value.

        // Access
        @AuraEnabled public String accessMode; // An AIAgent__c.AccessMode__c value.
        @AuraEnabled public List<AssignmentView> assignments = new List<AssignmentView>();

        // What is saved, for an agent that is being changed. The wizard never changes these.
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Integer userCount; // Users who can use the saved agent now.
    }

    // An agent that can be copied.
    public class CopyOption {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public List<String> objectApiNames = new List<String>();
    }

    // An object the agent can appear on.
    public class ObjectOption {

        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
    }

    // A prompt template the Basics step offers.
    public class PromptTemplateOption {

        @AuraEnabled public Id templateId;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal version;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Integer agentCount; // Active agents that answer with the template.
    }

    // A model configuration the Model step offers.
    public class ModelOption {

        @AuraEnabled public Id modelId;
        @AuraEnabled public String name;
        @AuraEnabled public String provider;
        @AuraEnabled public String modelIdentifier;
        @AuraEnabled public Decimal maxOutputTokens;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public Boolean isActive; // Only active models are offered, unless the agent being changed already uses an inactive one.
        @AuraEnabled public Integer agentCount; // Active agents that use the model.
    }

    // A data source the Data sources step offers.
    public class DataSourceOption {

        @AuraEnabled public Id dataSourceId;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String sourceType; // SOQL or Apex.
        @AuraEnabled public String bindingType; // Bound or Unbound.
        @AuraEnabled public String targetObject; // The object a bound data source reads from the open record, or the object an unbound one reads.
        @AuraEnabled public Decimal maxRows;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isPiiProtected; // The object has an active PII registry.
        @AuraEnabled public Integer agentCount;
    }

    // A workflow action the Workflow actions step offers.
    public class WorkflowActionOption {

        @AuraEnabled public Id actionId;
        @AuraEnabled public String name;
        @AuraEnabled public String developerName;
        @AuraEnabled public String description;
        @AuraEnabled public String actionType; // Apex, Flow or Screen Flow.
        @AuraEnabled public String targetObject;
        @AuraEnabled public String flowApiName;
        @AuraEnabled public Boolean isWrite; // True when the action creates or changes records.
        @AuraEnabled public Boolean requiresConfirmation; // The user is asked before it runs.
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean hasActiveFlowVersion; // True for an Apex action, and for a flow with an active version.
        @AuraEnabled public Decimal activeFlowVersion; // Blank when there is none.
        @AuraEnabled public Integer agentCount;
    }

    // The usage policy that applies to most users, so the Limits step can say whether the limits fit it.
    public class PolicyInfo {

        @AuraEnabled public String policyName;
        @AuraEnabled public Decimal maxTokensPer24Hours; // Blank when the policy sets no limit.
    }

    // Everything the tab needs when it opens.
    public class WizardPage {

        @AuraEnabled public List<ObjectOption> objects = new List<ObjectOption>(); // Labels for every object named by a copy option, the draft, a data source or a workflow action.
        @AuraEnabled public List<CopyOption> copyOptions = new List<CopyOption>();
        @AuraEnabled public List<PromptTemplateOption> promptTemplates = new List<PromptTemplateOption>();
        @AuraEnabled public List<ModelOption> models = new List<ModelOption>();
        @AuraEnabled public List<DataSourceOption> dataSources = new List<DataSourceOption>();
        @AuraEnabled public List<WorkflowActionOption> workflowActions = new List<WorkflowActionOption>();
        @AuraEnabled public Integer assistUserCount; // Users who hold the AI Assist User permission set.
        @AuraEnabled public Decimal orgToolCallingCap; // AIAssistSettings__c.MaxToolCallingIterationsCap__c.
        @AuraEnabled public Boolean isWorkflowActionsEnabled; // AIAssistUISettings__c.IsWorkflowActionsEnabled__c.
        @AuraEnabled public PolicyInfo policy;
        @AuraEnabled public AgentDraft draft; // The agent being changed, or blank when a new one is being made.
    }

    // One thing the checks found. A blocker stops the agent being activated, a warning does not.
    public class Finding {

        @AuraEnabled public String severity; // Blocker or Warning.
        @AuraEnabled public Integer step; // The step that fixes it: 1 Basics, 2 Model, 3 Data sources, 4 Workflow actions, 5 Conversations, 6 Limits, 7 Access.
        @AuraEnabled public String code; // A short stable name, such as NoModel, so the tab can tie a finding to a field.
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String itemId; // The data source, action or template the finding is about, when there is one.
    }

    // What checking a draft found.
    public class DraftCheck {

        @AuraEnabled public List<Finding> findings = new List<Finding>();
        @AuraEnabled public Integer accessUserCount; // Users who would see the agent.
        @AuraEnabled public Boolean isDeveloperNameTaken;
        @AuraEnabled public Boolean canActivate; // True when there is no blocker.
    }

    // Whether one user would have the agent.
    public class UserCheck {

        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Boolean hasAccess;
        @AuraEnabled public String reason; // Why, in a sentence the admin can read.
    }

    // A user or permission set the Access step can add.
    public class AssigneeOption {

        @AuraEnabled public String assigneeType;
        @AuraEnabled public Id userId;
        @AuraEnabled public String permissionSetName;
        @AuraEnabled public String label;
        @AuraEnabled public Integer userCount;
    }

    // What one trial message got back. The provider's own error text never reaches the tab.
    public class TryResult {

        @AuraEnabled public Boolean isSuccessful;
        @AuraEnabled public String replyText;
        @AuraEnabled public Decimal latencyMilliseconds;
        @AuraEnabled public Decimal totalTokens;
        @AuraEnabled public String errorMessage;
    }

    // What a save did.
    public class SaveResult {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String modelName;
        @AuraEnabled public List<String> objectApiNames = new List<String>();
        @AuraEnabled public Integer dataSourceCount;
        @AuraEnabled public Integer workflowActionCount;
        @AuraEnabled public Integer assignmentCount;
        @AuraEnabled public Integer userCount;
        @AuraEnabled public Boolean isCreated; // True when the agent is new.
    }

    // One line of the list of agents the tab opens on.
    public class AgentRow {

        @AuraEnabled public Id agentId;
        @AuraEnabled public String name;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public List<String> objectApiNames = new List<String>();
        @AuraEnabled public List<String> objectLabels = new List<String>(); // The labels of the objects, in the same order.
        @AuraEnabled public String modelName; // Blank when the agent has no model.
        @AuraEnabled public Integer userCount; // Users who can use the agent now.
        @AuraEnabled public Boolean isAllUsers; // True when the agent is open to every AI Assist user.
        @AuraEnabled public Datetime lastModifiedDate;
        @AuraEnabled public Integer blockerCount; // Findings that stop the agent being activated.
        @AuraEnabled public Integer warningCount;
        @AuraEnabled public String topFindingTitle; // The title of the worst finding, a blocker before a warning. Blank when there is none.
        @AuraEnabled public String topFindingSeverity; // Blocker or Warning. Blank when there is none.
    }
}
