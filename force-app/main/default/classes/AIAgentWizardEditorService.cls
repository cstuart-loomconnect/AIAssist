/*
Class Name: AIAgentWizardEditorService

=================================================================
=================================================================

Description: Reads what the AI Agent Wizard tab offers: the page, the list of agents, a saved agent as a draft, a copy of it, the objects it can appear on and the model connection check.

Step 1: Read the agents to copy, prompt templates, models, data sources and workflow actions the steps offer
Step 2: Read a saved agent, with its links and access list, as a draft, or as a copy that is ready to save as a new agent
Step 3: Search the objects an agent can appear on
Step 4: Test the connection of a model
Step 5: Read every agent as one line of the list the tab opens on, with its model, users and worst finding

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardEditorService {

    public class AIAgentWizardEditorServiceException extends Exception {}

    // Object name endings that are never a record page an agent can appear on.
    private static final List<String> EXCLUDED_ENDINGS = new List<String>{'share', 'history', 'feed', 'changeevent', '__mdt', '__e', '__b', '__x', '__tag'};

    // Everything the tab needs when it opens, and the draft of the agent being changed when there is one.
    public static AIAgentWizardDataStructure.WizardPage getWizardPage(Id agentId) {

        // [1] Refuse a user who may not use the tab, and start the page with the agent being changed
        AIAssistSettingsEditorService.requireManager();
        AIAgentWizardDataStructure.WizardPage page = new AIAgentWizardDataStructure.WizardPage();
        if (agentId != null) page.draft = getAgentDraft(agentId);

        // [2] Read the choices each step offers
        page.copyOptions = getCopyOptions();
        page.promptTemplates = getPromptTemplateOptions(page.draft);
        page.models = getModelOptions(page.draft);
        page.dataSources = getDataSourceOptions();
        page.workflowActions = getWorkflowActionOptions();

        // [3] Read the settings the checks compare with
        page.assistUserCount = AIAgentWizardCheckService.getAssistUserCount();
        page.orgToolCallingCap = AIAssistSettingsService.getSettings().MaxToolCallingIterationsCap__c;
        page.isWorkflowActionsEnabled = AIAssistSettingsService.getUiSettings().IsWorkflowActionsEnabled__c == true;
        page.policy = AIAgentWizardCheckService.getPolicyInfo();

        // [4] Give a label to every object the page mentions
        page.objects = getObjectOptions(getMentionedObjectNames(page));

        return page;
    }

    // A saved agent as the wizard holds it: its settings, active links and access list.
    public static AIAgentWizardDataStructure.AgentDraft getAgentDraft(Id agentId) {

        // [1] Refuse a user who may not use the tab, and an agent that is gone
        AIAssistSettingsEditorService.requireManager();
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, Description__c, AIAgentPersona__c, GreetingMessage__c, ObjectApiNames__c, AIPromptTemplate__c, AIModelConfiguration__c, ConversationLoadTrigger__c, AllowConversationResume__c, SingleActiveConversationPerRecord__c, ConversationVisibility__c, IdleTimeoutMinutes__c, ConversationRetentionDays__c, RetentionTrigger__c, MaxMessagesPerConversation__c, MaxTokensPerConversation__c, MaxToolCallingIterations__c, TokenTrackingMethod__c, AccessMode__c, IsActive__c, LastModifiedDate FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];
        if (agents.isEmpty()) throw new AIAgentWizardEditorServiceException(Label.AI_Wizard_Error_Not_Found);

        // [2] Copy the settings
        AIAgent__c agent = agents[0];
        AIAgentWizardDataStructure.AgentDraft draft = new AIAgentWizardDataStructure.AgentDraft();
        draft.agentId = agent.Id;
        draft.agentName = agent.Name;
        draft.developerName = agent.DeveloperName__c;
        draft.description = agent.Description__c;
        draft.persona = agent.AIAgentPersona__c;
        draft.greeting = agent.GreetingMessage__c;
        draft.objectApiNames = getObjectNames(agent.ObjectApiNames__c);
        draft.promptTemplateId = agent.AIPromptTemplate__c;
        draft.modelConfigurationId = agent.AIModelConfiguration__c;
        draft.conversationLoadTrigger = agent.ConversationLoadTrigger__c;
        draft.allowConversationResume = agent.AllowConversationResume__c == true;
        draft.singleActiveConversationPerRecord = agent.SingleActiveConversationPerRecord__c == true;
        draft.conversationVisibility = agent.ConversationVisibility__c;
        draft.idleTimeoutMinutes = agent.IdleTimeoutMinutes__c;
        draft.conversationRetentionDays = agent.ConversationRetentionDays__c;
        draft.retentionTrigger = agent.RetentionTrigger__c;
        draft.maxMessagesPerConversation = agent.MaxMessagesPerConversation__c;
        draft.maxTokensPerConversation = agent.MaxTokensPerConversation__c;
        draft.maxToolCallingIterations = agent.MaxToolCallingIterations__c;
        draft.tokenTrackingMethod = agent.TokenTrackingMethod__c;
        draft.accessMode = agent.AccessMode__c;
        draft.isActive = agent.IsActive__c == true;
        draft.lastModifiedDate = agent.LastModifiedDate;

        // [3] Read the active links
        for (AIAgentDataSource__c link : [SELECT AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY AIDataSource__r.SourceName__c LIMIT 2000]) draft.dataSourceIds.add(link.AIDataSource__c);

        for (AIAgentWorkflowAction__c link : [SELECT AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY AIWorkflowAction__r.ActionName__c LIMIT 2000]) draft.workflowActionIds.add(link.AIWorkflowAction__c);

        // [4] Read the access list, and count who can use the agent now
        draft.assignments = getAssignmentViews(agentId);
        draft.userCount = AIAgentWizardCheckService.getAccessUserCount(draft);

        return draft;
    }

    // A saved agent as a draft for a new agent: no id, a copy name, no API name, and switched off.
    public static AIAgentWizardDataStructure.AgentDraft getCopyDraft(Id agentId) {

        // [1] Refuse a user who may not use the tab, and read the agent
        AIAssistSettingsEditorService.requireManager();
        AIAgentWizardDataStructure.AgentDraft draft = getAgentDraft(agentId);

        // [2] Make it a new agent that the admin must name
        draft.agentId = null;
        draft.agentName = AIAssistApplicationConstants.WIZARD_COPY_NAME_PREFIX + draft.agentName;
        draft.developerName = null;
        draft.isActive = false;
        draft.lastModifiedDate = null;
        draft.userCount = null;

        return draft;
    }

    // Every agent as one line of the list the tab opens on: active agents first, then by name.
    public static List<AIAgentWizardDataStructure.AgentRow> getAgentList() {

        // [1] Refuse a user who may not use the tab, and read the agents
        AIAssistSettingsEditorService.requireManager();
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, ObjectApiNames__c, AIPromptTemplate__c, AIModelConfiguration__c, AIModelConfiguration__r.Name, ConversationVisibility__c, IdleTimeoutMinutes__c, ConversationRetentionDays__c, MaxMessagesPerConversation__c, MaxTokensPerConversation__c, MaxToolCallingIterations__c, AccessMode__c, IsActive__c, LastModifiedDate FROM AIAgent__c WITH SYSTEM_MODE ORDER BY IsActive__c DESC, Name LIMIT :AIAssistApplicationConstants.WIZARD_LIST_MAX_RESULTS];

        // [2] Build one row for each
        return buildAgentRows(agents);
    }

    // One agent as a line of the list, read again after it was changed.
    public static AIAgentWizardDataStructure.AgentRow getAgentRow(Id agentId) {

        // [1] Refuse a user who may not use the tab, and an agent that is gone
        AIAssistSettingsEditorService.requireManager();
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, ObjectApiNames__c, AIPromptTemplate__c, AIModelConfiguration__c, AIModelConfiguration__r.Name, ConversationVisibility__c, IdleTimeoutMinutes__c, ConversationRetentionDays__c, MaxMessagesPerConversation__c, MaxTokensPerConversation__c, MaxToolCallingIterations__c, AccessMode__c, IsActive__c, LastModifiedDate FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];
        if (agents.isEmpty()) throw new AIAgentWizardEditorServiceException(Label.AI_Wizard_Error_Not_Found);

        // [2] Build the row
        return buildAgentRows(agents)[0];
    }

    // The objects whose label or API name contains the text, for the object picker. Blank until the text is long enough to narrow the search.
    public static List<AIAgentWizardDataStructure.ObjectOption> searchObjects(String searchText) {

        // [1] Refuse a user who may not use the tab, and wait for enough text to search with
        AIAssistSettingsEditorService.requireManager();
        List<AIAgentWizardDataStructure.ObjectOption> options = new List<AIAgentWizardDataStructure.ObjectOption>();
        String lowerSearch = String.isBlank(searchText) ? '' : searchText.trim().toLowerCase();
        if (lowerSearch.length() < AIAssistApplicationConstants.WIZARD_OBJECT_SEARCH_MIN_LENGTH) return options;

        // [2] Find the objects that match and can be queried
        Map<String, Schema.SObjectType> typesByName = Schema.getGlobalDescribe();
        Map<String, Schema.DescribeSObjectResult> describeByLabel = new Map<String, Schema.DescribeSObjectResult>();

        for (String typeName : typesByName.keySet()) {

            if (isExcludedName(typeName)) continue;

            Boolean isNameMatch = typeName.contains(lowerSearch);
            Boolean isLabelMatch = typesByName.get(typeName).getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getLabel().toLowerCase().contains(lowerSearch);
            if (!isNameMatch && !isLabelMatch) continue;

            Schema.DescribeSObjectResult describeResult = typesByName.get(typeName).getDescribe();
            if (!describeResult.isQueryable() || !describeResult.isAccessible() || describeResult.isCustomSetting()) continue;

            describeByLabel.put(describeResult.getLabel().toLowerCase() + '|' + typeName, describeResult);
        }

        // [3] Put them in label order and build an option for the first few
        List<String> sortedKeys = new List<String>(describeByLabel.keySet());
        sortedKeys.sort();

        for (String sortedKey : sortedKeys) {

            if (options.size() >= AIAssistApplicationConstants.WIZARD_OBJECT_SEARCH_MAX_RESULTS) break;

            options.add(buildObjectOption(describeByLabel.get(sortedKey).getName(), describeByLabel.get(sortedKey).getLabel()));
        }

        return options;
    }

    // Tests the connection of a saved model, for the Model step.
    public static AIModelsDataStructure.TestResult testModel(Id modelId) {

        // [1] Refuse a user who may not use the tab, and a model that is gone
        AIAssistSettingsEditorService.requireManager();
        List<AIModelConfiguration__c> models = [SELECT Id, Name, AIProvider__c, ModelIdentifier__c, NamedCredential__c, ApiPath__c, ApiVersionHeaderName__c, ApiVersionHeaderValue__c, EnvironmentId__c, MaximumOutputTokens__c, Temperature__c FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];
        if (models.isEmpty()) throw new AIAgentWizardEditorServiceException(Label.AI_Wizard_Error_Model_Not_Found);

        // [2] Run the test
        return AIModelsConnectionTestService.runTest(models[0]);
    }

    // Builds one row for each agent, with the same few queries however many agents there are.
    private static List<AIAgentWizardDataStructure.AgentRow> buildAgentRows(List<AIAgent__c> agents) {

        // [1] Build a light draft of each agent, which the checks read
        List<AIAgentWizardDataStructure.AgentDraft> drafts = new List<AIAgentWizardDataStructure.AgentDraft>();
        Map<Id, AIAgentWizardDataStructure.AgentDraft> draftByAgentId = new Map<Id, AIAgentWizardDataStructure.AgentDraft>();

        for (AIAgent__c agent : agents) {

            AIAgentWizardDataStructure.AgentDraft draft = new AIAgentWizardDataStructure.AgentDraft();
            draft.agentId = agent.Id;
            draft.agentName = agent.Name;
            draft.developerName = agent.DeveloperName__c;
            draft.objectApiNames = getObjectNames(agent.ObjectApiNames__c);
            draft.promptTemplateId = agent.AIPromptTemplate__c;
            draft.modelConfigurationId = agent.AIModelConfiguration__c;
            draft.conversationVisibility = agent.ConversationVisibility__c;
            draft.idleTimeoutMinutes = agent.IdleTimeoutMinutes__c;
            draft.conversationRetentionDays = agent.ConversationRetentionDays__c;
            draft.maxMessagesPerConversation = agent.MaxMessagesPerConversation__c;
            draft.maxTokensPerConversation = agent.MaxTokensPerConversation__c;
            draft.maxToolCallingIterations = agent.MaxToolCallingIterations__c;
            draft.accessMode = agent.AccessMode__c;
            draft.isActive = agent.IsActive__c == true;
            drafts.add(draft);
            draftByAgentId.put(agent.Id, draft);
        }

        // [2] Add the active links and the access list of every agent, one read for each kind
        Set<Id> agentIds = draftByAgentId.keySet();

        for (AIAgentDataSource__c link : [SELECT AIAgent__c, AIDataSource__c FROM AIAgentDataSource__c WHERE AIAgent__c IN :agentIds AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 50000]) draftByAgentId.get(link.AIAgent__c).dataSourceIds.add(link.AIDataSource__c);

        for (AIAgentWorkflowAction__c link : [SELECT AIAgent__c, AIWorkflowAction__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c IN :agentIds AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 50000]) draftByAgentId.get(link.AIAgent__c).workflowActionIds.add(link.AIWorkflowAction__c);

        for (AIAgentAssignment__c assignment : [SELECT AIAgent__c, AssigneeType__c, User__c, PermissionSetName__c, IsActive__c FROM AIAgentAssignment__c WHERE AIAgent__c IN :agentIds WITH SYSTEM_MODE LIMIT 50000]) {

            AIAgentWizardDataStructure.AssignmentView view = new AIAgentWizardDataStructure.AssignmentView();
            view.assigneeType = assignment.AssigneeType__c;
            view.userId = assignment.User__c;
            view.permissionSetName = assignment.PermissionSetName__c;
            view.isActive = assignment.IsActive__c == true;
            draftByAgentId.get(assignment.AIAgent__c).assignments.add(view);
        }

        // [3] Check every agent and count its users, and find the label of every object
        Map<Id, AIAgentWizardDataStructure.DraftCheck> checkByAgentId = AIAgentWizardCheckService.checkAgents(drafts);
        Set<String> objectNames = new Set<String>();

        for (AIAgentWizardDataStructure.AgentDraft draft : drafts) objectNames.addAll(draft.objectApiNames);

        Map<String, String> labelByLowerName = new Map<String, String>();

        for (AIAgentWizardDataStructure.ObjectOption option : getObjectOptions(objectNames)) labelByLowerName.put(option.apiName.toLowerCase(), option.label);

        // [4] Build one row for each agent
        List<AIAgentWizardDataStructure.AgentRow> rows = new List<AIAgentWizardDataStructure.AgentRow>();

        for (AIAgent__c agent : agents) {

            AIAgentWizardDataStructure.AgentDraft draft = draftByAgentId.get(agent.Id);
            AIAgentWizardDataStructure.DraftCheck check = checkByAgentId.get(agent.Id);

            AIAgentWizardDataStructure.AgentRow row = new AIAgentWizardDataStructure.AgentRow();
            row.agentId = agent.Id;
            row.name = agent.Name;
            row.isActive = agent.IsActive__c == true;
            row.objectApiNames = draft.objectApiNames;
            row.modelName = agent.AIModelConfiguration__r?.Name;
            row.userCount = check.accessUserCount;
            row.isAllUsers = agent.AccessMode__c == AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
            row.lastModifiedDate = agent.LastModifiedDate;
            row.blockerCount = 0;
            row.warningCount = 0;

            for (String objectName : draft.objectApiNames) row.objectLabels.add(labelByLowerName.get(objectName.toLowerCase()));

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                Boolean isBlocker = finding.severity == AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER;
                if (isBlocker) row.blockerCount++;
                else row.warningCount++;

                Boolean isWorse = row.topFindingSeverity == null || (isBlocker && row.topFindingSeverity != AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER);

                if (isWorse) {

                    row.topFindingTitle = finding.title;
                    row.topFindingSeverity = finding.severity;
                }
            }

            rows.add(row);
        }

        return rows;
    }

    // Every agent, so the Copy mode can offer them.
    private static List<AIAgentWizardDataStructure.CopyOption> getCopyOptions() {

        // [1] Build one option for each agent
        List<AIAgentWizardDataStructure.CopyOption> options = new List<AIAgentWizardDataStructure.CopyOption>();

        for (AIAgent__c agent : [SELECT Id, Name, IsActive__c, ObjectApiNames__c FROM AIAgent__c WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.WIZARD_LIST_MAX_RESULTS]) {

            AIAgentWizardDataStructure.CopyOption option = new AIAgentWizardDataStructure.CopyOption();
            option.agentId = agent.Id;
            option.name = agent.Name;
            option.isActive = agent.IsActive__c == true;
            option.objectApiNames = getObjectNames(agent.ObjectApiNames__c);
            options.add(option);
        }

        return options;
    }

    // The active prompt templates, and the one the agent being changed uses when it is switched off.
    private static List<AIAgentWizardDataStructure.PromptTemplateOption> getPromptTemplateOptions(AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] Read the descriptions, which the rows of the Prompt Templates tab do not carry
        Map<Id, String> descriptionById = new Map<Id, String>();

        for (AIPromptTemplate__c promptTemplate : [SELECT Id, Description__c FROM AIPromptTemplate__c WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS]) descriptionById.put(promptTemplate.Id, promptTemplate.Description__c);

        // [2] Build an option for each template that is active, or that the agent already uses
        List<AIAgentWizardDataStructure.PromptTemplateOption> options = new List<AIAgentWizardDataStructure.PromptTemplateOption>();

        for (AIPromptTemplatesDataStructure.TemplateRow row : AIPromptTemplatesEditorService.getTemplateRows()) {

            Boolean isUsedByAgent = draft != null && draft.promptTemplateId == row.templateId;
            if (!row.isActive && !isUsedByAgent) continue;

            AIAgentWizardDataStructure.PromptTemplateOption option = new AIAgentWizardDataStructure.PromptTemplateOption();
            option.templateId = row.templateId;
            option.name = row.templateName;
            option.developerName = row.developerName;
            option.description = descriptionById.get(row.templateId);
            option.version = row.version;
            option.isDefault = row.isDefault;
            option.agentCount = row.agentCount;
            options.add(option);
        }

        return options;
    }

    // The active models, and the one the agent being changed uses when it is switched off.
    private static List<AIAgentWizardDataStructure.ModelOption> getModelOptions(AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] Build an option for each model that is active, or that the agent already uses
        List<AIAgentWizardDataStructure.ModelOption> options = new List<AIAgentWizardDataStructure.ModelOption>();

        for (AIModelsDataStructure.ModelView view : AIModelsEditorService.getModelViews()) {

            Boolean isUsedByAgent = draft != null && draft.modelConfigurationId == view.modelId;
            if (!view.isActive && !isUsedByAgent) continue;

            AIAgentWizardDataStructure.ModelOption option = new AIAgentWizardDataStructure.ModelOption();
            option.modelId = view.modelId;
            option.name = view.modelName;
            option.provider = view.provider;
            option.modelIdentifier = view.modelIdentifier;
            option.maxOutputTokens = view.maxOutputTokens;
            option.temperature = view.temperature;
            option.isActive = view.isActive;
            option.agentCount = view.agentCount;
            options.add(option);
        }

        return options;
    }

    // Every data source, with how many active agents use it and whether its object has an active PII registry.
    private static List<AIAgentWizardDataStructure.DataSourceOption> getDataSourceOptions() {

        // [1] Count the active agents of each data source
        Map<Id, Integer> agentCountById = new Map<Id, Integer>();

        for (AggregateResult countRow : [SELECT AIDataSource__c itemId, COUNT(Id) agentCount FROM AIAgentDataSource__c WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE GROUP BY AIDataSource__c]) agentCountById.put((Id) countRow.get('itemId'), (Integer) countRow.get('agentCount'));

        // [2] Build one option for each data source
        Set<String> piiObjectNames = getPiiObjectNames();
        List<AIAgentWizardDataStructure.DataSourceOption> options = new List<AIAgentWizardDataStructure.DataSourceOption>();

        for (AIDataSource__c dataSource : [SELECT Id, SourceName__c, DeveloperName__c, Description__c, SourceType__c, BindingType__c, TargetObject__c, MaxRows__c, IsActive__c FROM AIDataSource__c WITH SYSTEM_MODE ORDER BY SourceName__c LIMIT :AIAssistApplicationConstants.WIZARD_LIST_MAX_RESULTS]) {

            AIAgentWizardDataStructure.DataSourceOption option = new AIAgentWizardDataStructure.DataSourceOption();
            option.dataSourceId = dataSource.Id;
            option.name = dataSource.SourceName__c;
            option.developerName = dataSource.DeveloperName__c;
            option.description = dataSource.Description__c;
            option.sourceType = dataSource.SourceType__c;
            option.bindingType = dataSource.BindingType__c;
            option.targetObject = dataSource.TargetObject__c;
            option.maxRows = dataSource.MaxRows__c;
            option.isActive = dataSource.IsActive__c == true;
            option.isPiiProtected = String.isNotBlank(dataSource.TargetObject__c) && piiObjectNames.contains(dataSource.TargetObject__c.toLowerCase());
            option.agentCount = agentCountById.containsKey(dataSource.Id) ? agentCountById.get(dataSource.Id) : 0;
            options.add(option);
        }

        return options;
    }

    // Every workflow action, with how many active agents use it and whether its flow has an active version.
    private static List<AIAgentWizardDataStructure.WorkflowActionOption> getWorkflowActionOptions() {

        // [1] Count the active agents of each action
        Map<Id, Integer> agentCountById = new Map<Id, Integer>();

        for (AggregateResult countRow : [SELECT AIWorkflowAction__c itemId, COUNT(Id) agentCount FROM AIAgentWorkflowAction__c WHERE IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE GROUP BY AIWorkflowAction__c]) agentCountById.put((Id) countRow.get('itemId'), (Integer) countRow.get('agentCount'));

        // [2] Read the actions and find the active version of each flow they run
        List<AIWorkflowAction__c> actions = [SELECT Id, ActionName__c, DeveloperName__c, Description__c, ActionType__c, TargetObject__c, FlowAPIName__c, ExecutionType__c, RequiresConfirmation__c, IsActive__c FROM AIWorkflowAction__c WITH SYSTEM_MODE ORDER BY ActionName__c LIMIT :AIAssistApplicationConstants.WIZARD_LIST_MAX_RESULTS];
        Set<String> flowNames = new Set<String>();

        for (AIWorkflowAction__c action : actions) {

            if (String.isNotBlank(action.FlowAPIName__c)) flowNames.add(action.FlowAPIName__c);
        }

        Map<String, Integer> activeVersionByFlowName = AIAgentWizardCheckService.getActiveFlowVersions(flowNames);

        // [3] Build one option for each action
        List<AIAgentWizardDataStructure.WorkflowActionOption> options = new List<AIAgentWizardDataStructure.WorkflowActionOption>();

        for (AIWorkflowAction__c action : actions) {

            Boolean isApex = action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX;
            Integer activeVersion = activeVersionByFlowName.get(action.FlowAPIName__c);

            AIAgentWizardDataStructure.WorkflowActionOption option = new AIAgentWizardDataStructure.WorkflowActionOption();
            option.actionId = action.Id;
            option.name = action.ActionName__c;
            option.developerName = action.DeveloperName__c;
            option.description = action.Description__c;
            option.actionType = action.ActionType__c;
            option.targetObject = action.TargetObject__c;
            option.flowApiName = action.FlowAPIName__c;
            option.isWrite = action.ExecutionType__c == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE;
            option.requiresConfirmation = action.RequiresConfirmation__c == true;
            option.isActive = action.IsActive__c == true;
            option.hasActiveFlowVersion = isApex || activeVersion != null;
            option.activeFlowVersion = activeVersion;
            option.agentCount = agentCountById.containsKey(action.Id) ? agentCountById.get(action.Id) : 0;
            options.add(option);
        }

        return options;
    }

    // The access list of a saved agent, with each person's name or permission set's label and how many users it covers.
    private static List<AIAgentWizardDataStructure.AssignmentView> getAssignmentViews(Id agentId) {

        // [1] Read the assignments
        List<AIAgentAssignment__c> assignments = [SELECT AssigneeType__c, User__c, User__r.Name, PermissionSetName__c, IsActive__c FROM AIAgentAssignment__c WHERE AIAgent__c = :agentId WITH SYSTEM_MODE ORDER BY CreatedDate, Id LIMIT 2000];
        Set<String> permissionSetNames = new Set<String>();

        for (AIAgentAssignment__c assignment : assignments) {

            if (String.isNotBlank(assignment.PermissionSetName__c)) permissionSetNames.add(assignment.PermissionSetName__c);
        }

        // [2] Find the label and the holders of each permission set
        Map<String, String> labelByName = AIPoliciesAssignmentService.getPermissionSetLabels(permissionSetNames);
        Map<String, Integer> userCountByName = AIPoliciesAssignmentService.getUsersCovered(permissionSetNames);

        // [3] Build one view for each assignment
        List<AIAgentWizardDataStructure.AssignmentView> views = new List<AIAgentWizardDataStructure.AssignmentView>();

        for (AIAgentAssignment__c assignment : assignments) {

            Boolean isUser = assignment.AssigneeType__c == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER;

            AIAgentWizardDataStructure.AssignmentView view = new AIAgentWizardDataStructure.AssignmentView();
            view.assigneeType = assignment.AssigneeType__c;
            view.userId = assignment.User__c;
            view.permissionSetName = assignment.PermissionSetName__c;
            view.label = isUser ? assignment.User__r.Name : labelByName.get(assignment.PermissionSetName__c);
            view.userCount = isUser ? 1 : userCountByName.get(assignment.PermissionSetName__c);
            view.isActive = assignment.IsActive__c == true;
            views.add(view);
        }

        return views;
    }

    // The objects of the active PII registries, in lower case.
    private static Set<String> getPiiObjectNames() {

        // [1] Read the active registries
        Set<String> names = new Set<String>();

        for (AIPIIRegistry__c registry : [SELECT ObjectAPIName__c FROM AIPIIRegistry__c WHERE IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 2000]) {

            if (String.isNotBlank(registry.ObjectAPIName__c)) names.add(registry.ObjectAPIName__c.toLowerCase());
        }

        return names;
    }

    // Every object the page mentions: the agents to copy, the draft, the data sources and the workflow actions.
    private static Set<String> getMentionedObjectNames(AIAgentWizardDataStructure.WizardPage page) {

        // [1] Collect the names from each list
        Set<String> names = new Set<String>();

        for (AIAgentWizardDataStructure.CopyOption copyOption : page.copyOptions) names.addAll(copyOption.objectApiNames);

        if (page.draft != null) names.addAll(page.draft.objectApiNames);

        for (AIAgentWizardDataStructure.DataSourceOption dataSource : page.dataSources) {

            if (String.isNotBlank(dataSource.targetObject)) names.add(dataSource.targetObject);
        }

        for (AIAgentWizardDataStructure.WorkflowActionOption action : page.workflowActions) {

            if (String.isNotBlank(action.targetObject)) names.add(action.targetObject);
        }

        return names;
    }

    // A label for each object name, in label order. A name the org does not have keeps the name as its label.
    private static List<AIAgentWizardDataStructure.ObjectOption> getObjectOptions(Set<String> names) {

        // [1] Look up each name once, ignoring case
        Map<String, Schema.SObjectType> typesByName = Schema.getGlobalDescribe();
        Map<String, AIAgentWizardDataStructure.ObjectOption> optionByLowerName = new Map<String, AIAgentWizardDataStructure.ObjectOption>();

        for (String name : names) {

            if (optionByLowerName.containsKey(name.toLowerCase())) continue;

            Schema.SObjectType objectType = typesByName.get(name.toLowerCase());
            optionByLowerName.put(name.toLowerCase(), objectType == null ? buildObjectOption(name, name) : buildObjectOption(objectType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getName(), objectType.getDescribe(Schema.SObjectDescribeOptions.DEFERRED).getLabel()));
        }

        // [2] Put them in label order
        List<String> sortedKeys = new List<String>();

        for (AIAgentWizardDataStructure.ObjectOption option : optionByLowerName.values()) sortedKeys.add(option.label.toLowerCase() + '|' + option.apiName.toLowerCase());

        sortedKeys.sort();
        List<AIAgentWizardDataStructure.ObjectOption> options = new List<AIAgentWizardDataStructure.ObjectOption>();

        for (String sortedKey : sortedKeys) options.add(optionByLowerName.get(sortedKey.substringAfter('|')));

        return options;
    }

    // Builds an object option.
    private static AIAgentWizardDataStructure.ObjectOption buildObjectOption(String apiName, String label) {

        // [1] Copy the values
        AIAgentWizardDataStructure.ObjectOption option = new AIAgentWizardDataStructure.ObjectOption();
        option.apiName = apiName;
        option.label = label;

        return option;
    }

    // The object names in a comma separated text, trimmed.
    private static List<String> getObjectNames(String text) {

        // [1] A general agent has none
        List<String> names = new List<String>();
        if (String.isBlank(text)) return names;

        // [2] Split the text and keep each name that is not blank
        for (String name : text.split(',')) {

            if (String.isNotBlank(name.trim())) names.add(name.trim());
        }

        return names;
    }

    // True for a type name that is never a record page an agent can appear on.
    private static Boolean isExcludedName(String lowerTypeName) {

        // [1] Look for each ending
        for (String ending : EXCLUDED_ENDINGS) {

            if (lowerTypeName.endsWith(ending)) return true;
        }

        return false;
    }
}
