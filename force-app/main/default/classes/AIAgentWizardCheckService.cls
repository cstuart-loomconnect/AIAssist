/*
Class Name: AIAgentWizardCheckService

=================================================================
=================================================================

Description: Checks a draft of the AI Agent Wizard, says who would see the agent, and finds the users and permission sets the Access step can add.

Step 1: Check the whole draft and list every blocker and warning, with the step that fixes each
Step 2: Count the users who would see the agent
Step 3: Explain whether one user would have the agent
Step 4: Search the users and permission sets the Access step can add
Step 5: Check many saved agents at once for the list of agents, with a handful of queries instead of a set for each agent

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardCheckService {

    public class AIAgentWizardCheckServiceException extends Exception {}

    // What the check of many agents reads once and then compares every agent with.
    private class ListContext {

        public Map<Id, AIModelConfiguration__c> modelById = new Map<Id, AIModelConfiguration__c>();
        public Map<Id, AIDataSource__c> dataSourceById = new Map<Id, AIDataSource__c>();
        public Map<Id, AIWorkflowAction__c> actionById = new Map<Id, AIWorkflowAction__c>();
        public Map<String, Integer> activeVersionByFlowName = new Map<String, Integer>();
        public Set<Id> activeTemplateIds = new Set<Id>();
        public Boolean hasDefaultTemplate = false;
        public AIAgentWizardDataStructure.PolicyInfo policy;
    }

    // The permission sets that make a user an AI Assist user.
    private static final Set<String> ASSIST_PERMISSION_SETS = new Set<String>{
        AIAssistApplicationConstants.PERMISSION_SET_USER,
        AIAssistApplicationConstants.PERMISSION_SET_ADMIN_USER,
        AIAssistApplicationConstants.PERMISSION_SET_SUPER_USER
    };

    // Checks the whole draft. A blocker stops the agent being activated, a warning does not.
    public static AIAgentWizardDataStructure.DraftCheck checkDraft(AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] Refuse a user who may not use the tab, and a missing draft
        AIAssistSettingsEditorService.requireManager();
        if (draft == null) throw new AIAgentWizardCheckServiceException(Label.AI_Wizard_Error_Draft_Required);

        // [2] Run each group of checks
        AIAgentWizardDataStructure.DraftCheck check = new AIAgentWizardDataStructure.DraftCheck();
        check.isDeveloperNameTaken = false;
        addBasicsFindings(check, draft);
        addModelFindings(check, draft);
        addSkillFindings(check, draft, getSkills(new Set<Id>(draft.skillIds)));
        addDataSourceFindings(check, draft, getDataSources(new Set<Id>(draft.dataSourceIds)));
        List<AIWorkflowAction__c> actions = getActions(new Set<Id>(draft.workflowActionIds));
        addActionFindings(check, draft, actions, getActiveFlowVersions(getFlowNames(actions)));
        AIAgentWizardDataStructure.PolicyInfo policy = getPolicyInfo();
        addLimitFindings(check, draft, policy);
        addAccessFindings(check, draft, policy);

        // [3] Count who would see the agent, and say whether it can be activated
        check.accessUserCount = getAccessUserCount(draft);
        setCanActivate(check);

        return check;
    }

    // Checks many saved agents at once, for the list of agents. The check of each is the same as checkDraft, except that the name checks (required, format and taken) are left out, because the agents are already saved. The result is keyed by agent id.
    public static Map<Id, AIAgentWizardDataStructure.DraftCheck> checkAgents(List<AIAgentWizardDataStructure.AgentDraft> drafts) {

        // [1] Refuse a user who may not use the tab, and stop when there is nothing to check
        AIAssistSettingsEditorService.requireManager();
        Map<Id, AIAgentWizardDataStructure.DraftCheck> checkByAgentId = new Map<Id, AIAgentWizardDataStructure.DraftCheck>();
        if (drafts == null || drafts.isEmpty()) return checkByAgentId;

        // [2] Read what every agent is compared with, and count the users of every agent
        ListContext context = getListContext(drafts);
        Map<Id, Integer> userCountByAgentId = getAccessUserCounts(drafts);

        // [3] Run the checks on each agent
        for (AIAgentWizardDataStructure.AgentDraft draft : drafts) {

            AIAgentWizardDataStructure.DraftCheck check = new AIAgentWizardDataStructure.DraftCheck();
            check.isDeveloperNameTaken = false;
            addListBasicsFindings(check, draft, context);
            addListModelFindings(check, draft, context);
            addDataSourceFindings(check, draft, getContextDataSources(draft, context));
            addActionFindings(check, draft, getContextActions(draft, context), context.activeVersionByFlowName);
            addLimitFindings(check, draft, context.policy);
            addAccessFindings(check, draft, context.policy);
            check.accessUserCount = userCountByAgentId.get(draft.agentId);
            setCanActivate(check);
            checkByAgentId.put(draft.agentId, check);
        }

        return checkByAgentId;
    }

    // How many active users would see each agent, with one read of the users and of the permission set holders for all of them. The result is keyed by agent id.
    public static Map<Id, Integer> getAccessUserCounts(List<AIAgentWizardDataStructure.AgentDraft> drafts) {

        // [1] Collect the users and permission sets of every agent that is for assigned users, and count every AI Assist user once for the agents open to all
        Map<Id, Integer> userCountByAgentId = new Map<Id, Integer>();
        Map<Id, Set<Id>> userIdsByAgentId = new Map<Id, Set<Id>>();
        Map<Id, Set<String>> namesByAgentId = new Map<Id, Set<String>>();
        Set<Id> allUserIds = new Set<Id>();
        Set<String> allNames = new Set<String>();
        Integer assistUserCount = null;

        for (AIAgentWizardDataStructure.AgentDraft draft : drafts) {

            if (draft.accessMode == AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS) {

                if (assistUserCount == null) assistUserCount = getAssistUserCount();

                userCountByAgentId.put(draft.agentId, assistUserCount);
                continue;
            }

            Set<Id> userIds = new Set<Id>();
            Set<String> permissionSetNames = new Set<String>();

            for (AIAgentWizardDataStructure.AssignmentView assignment : draft.assignments) {

                if (assignment.isActive == false) continue;

                if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER && assignment.userId != null) userIds.add(assignment.userId);
                else if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET && String.isNotBlank(assignment.permissionSetName)) permissionSetNames.add(assignment.permissionSetName);
            }

            userIdsByAgentId.put(draft.agentId, userIds);
            namesByAgentId.put(draft.agentId, permissionSetNames);
            allUserIds.addAll(userIds);
            allNames.addAll(permissionSetNames);
        }

        // [2] Read the active users who are named, and the holders of the permission sets, once
        Set<Id> activeUserIds = new Set<Id>();

        for (User assignedUser : [SELECT Id FROM User WHERE Id IN :allUserIds AND IsActive = TRUE WITH SYSTEM_MODE LIMIT 2000]) activeUserIds.add(assignedUser.Id);

        Map<String, Set<Id>> holderIdsByName = getHolderIdsByName(allNames);

        // [3] Count each active user once for each agent, whether assigned by name or through a permission set
        for (Id agentId : userIdsByAgentId.keySet()) {

            Set<Id> countedUserIds = new Set<Id>();

            for (Id userId : userIdsByAgentId.get(agentId)) {

                if (activeUserIds.contains(userId)) countedUserIds.add(userId);
            }

            for (String permissionSetName : namesByAgentId.get(agentId)) {

                if (holderIdsByName.containsKey(permissionSetName)) countedUserIds.addAll(holderIdsByName.get(permissionSetName));
            }

            userCountByAgentId.put(agentId, countedUserIds.size());
        }

        return userCountByAgentId;
    }

    // How many active users would see the agent: every AI Assist user for an agent that is open to all, otherwise the users assigned by name and the holders of the assigned permission sets.
    public static Integer getAccessUserCount(AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] Count every AI Assist user for an agent that is open to all
        if (draft.accessMode == AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS) return getUserIdsHoldingAny(ASSIST_PERMISSION_SETS).size();

        // [2] Collect the users and permission sets of the active assignments
        Set<Id> userIds = new Set<Id>();
        Set<String> permissionSetNames = new Set<String>();

        for (AIAgentWizardDataStructure.AssignmentView assignment : draft.assignments) {

            if (assignment.isActive == false) continue;

            if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER && assignment.userId != null) userIds.add(assignment.userId);
            else if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET && String.isNotBlank(assignment.permissionSetName)) permissionSetNames.add(assignment.permissionSetName);
        }

        // [3] Count each active user once, whether assigned by name or through a permission set
        Set<Id> assignedUserIds = new Set<Id>();

        for (User assignedUser : [SELECT Id FROM User WHERE Id IN :userIds AND IsActive = TRUE WITH SYSTEM_MODE LIMIT 2000]) assignedUserIds.add(assignedUser.Id);

        assignedUserIds.addAll(getUserIdsHoldingAny(permissionSetNames));

        return assignedUserIds.size();
    }

    // How many active users hold an AI Assist permission set, for the Access step.
    public static Integer getAssistUserCount() {

        // [1] Count the distinct holders
        return getUserIdsHoldingAny(ASSIST_PERMISSION_SETS).size();
    }

    // The usage policy that applies to most users: the strictest active default policy, or null when there is none.
    public static AIAgentWizardDataStructure.PolicyInfo getPolicyInfo() {

        // [1] Read the active default policies
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c FROM AIUsagePolicy__c WHERE IsActive__c = TRUE AND IsDefault__c = TRUE WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        AIUsagePolicy__c strictest = AIUsagePolicyService.getStrictestPolicy(policies);
        if (strictest == null) return null;

        // [2] Report the strictest
        AIAgentWizardDataStructure.PolicyInfo info = new AIAgentWizardDataStructure.PolicyInfo();
        info.policyName = strictest.Name;
        info.maxTokensPer24Hours = strictest.MaxTokensPer24Hours__c;

        return info;
    }

    // The active version number of each flow that has one. A flow with none is missing from the map.
    public static Map<String, Integer> getActiveFlowVersions(Set<String> flowApiNames) {

        // [1] Read the active versions
        Map<String, Integer> activeVersionByFlowName = new Map<String, Integer>();

        if (flowApiNames.isEmpty()) return activeVersionByFlowName;

        for (FlowDefinitionView flow : [SELECT ApiName, VersionNumber FROM FlowDefinitionView WHERE ApiName IN :flowApiNames AND IsActive = TRUE WITH SYSTEM_MODE]) activeVersionByFlowName.put(flow.ApiName, flow.VersionNumber);

        return activeVersionByFlowName;
    }

    // Says whether one user would have the agent as the draft stands, and why.
    public static AIAgentWizardDataStructure.UserCheck checkUser(AIAgentWizardDataStructure.AgentDraft draft, Id userId) {

        // [1] Refuse a user who may not use the tab, a missing draft and a user who is gone
        AIAssistSettingsEditorService.requireManager();
        if (draft == null) throw new AIAgentWizardCheckServiceException(Label.AI_Wizard_Error_Draft_Required);

        List<User> users = [SELECT Id, Name, IsActive FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty()) throw new AIAgentWizardCheckServiceException(Label.AI_Wizard_Error_User_Not_Found);

        AIAgentWizardDataStructure.UserCheck check = new AIAgentWizardDataStructure.UserCheck();
        check.userId = users[0].Id;
        check.userName = users[0].Name;
        check.hasAccess = false;

        // [2] A user who is switched off has nothing
        if (!users[0].IsActive) {

            check.reason = Label.AI_Wizard_User_Reason_Inactive;

            return check;
        }

        // [3] A user needs an AI Assist permission set
        Set<String> heldNames = getHeldPermissionSetNames(userId);
        Set<String> heldAssistNames = new Set<String>(heldNames);
        heldAssistNames.retainAll(ASSIST_PERMISSION_SETS);

        if (heldAssistNames.isEmpty()) {

            check.reason = Label.AI_Wizard_User_Reason_No_Permission_Set;

            return check;
        }

        // [4] Find how the user is let in: the agent is open to all, the user is assigned by name, or they hold an assigned permission set
        String reason = null;

        if (draft.accessMode == AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS) reason = Label.AI_Wizard_User_Reason_All_Users;

        for (AIAgentWizardDataStructure.AssignmentView assignment : draft.assignments) {

            if (assignment.isActive == false || reason != null) continue;

            if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER && assignment.userId == userId) reason = Label.AI_Wizard_User_Reason_Assigned_User;
            else if (assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET && heldNames.contains(assignment.permissionSetName)) reason = String.format(Label.AI_Wizard_User_Reason_Assigned_Set, new List<String>{String.isBlank(assignment.label) ? assignment.permissionSetName : assignment.label});
        }

        if (reason == null) {

            check.reason = Label.AI_Wizard_User_Reason_Not_Assigned;

            return check;
        }

        // [5] A user also needs a usage policy to send
        if (AIUsagePolicyService.getAccessLevel(userId) == AIAssistApplicationConstants.ACCESS_LEVEL_NONE) {

            check.reason = Label.AI_Wizard_User_Reason_No_Policy;

            return check;
        }

        check.hasAccess = true;
        check.reason = reason;

        return check;
    }

    // The users and the permission sets or groups whose name matches the text, for the Add dialog. Blank until the text is long enough to narrow the search.
    public static List<AIAgentWizardDataStructure.AssigneeOption> searchAssignees(String searchText) {

        // [1] Refuse a user who may not use the tab, and wait for enough text to search with
        AIAssistSettingsEditorService.requireManager();
        List<AIAgentWizardDataStructure.AssigneeOption> options = new List<AIAgentWizardDataStructure.AssigneeOption>();
        String trimmedText = String.isBlank(searchText) ? '' : searchText.trim();
        if (trimmedText.length() < AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MIN_LENGTH) return options;

        // [2] Search active standard users by name or username
        String likeText = '%' + String.escapeSingleQuotes(trimmedText) + '%';
        String standardType = AIAssistApplicationConstants.USER_TYPE_STANDARD;
        Integer maxResults = AIAssistApplicationConstants.WIZARD_ASSIGNEE_SEARCH_MAX_RESULTS;

        for (User matchingUser : [SELECT Id, Name FROM User WHERE IsActive = TRUE AND UserType = :standardType AND (Name LIKE :likeText OR Username LIKE :likeText) WITH SYSTEM_MODE ORDER BY Name LIMIT :maxResults]) {

            AIAgentWizardDataStructure.AssigneeOption option = new AIAgentWizardDataStructure.AssigneeOption();
            option.assigneeType = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER;
            option.userId = matchingUser.Id;
            option.label = matchingUser.Name;
            option.userCount = 1;
            options.add(option);
        }

        // [3] Search permission sets and groups, which the policies tab already knows how to do
        for (AIPoliciesDataStructure.AssigneeOption permissionSet : AIPoliciesAssignmentService.findAssignees(null, AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, trimmedText)) {

            AIAgentWizardDataStructure.AssigneeOption option = new AIAgentWizardDataStructure.AssigneeOption();
            option.assigneeType = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET;
            option.permissionSetName = permissionSet.detail;
            option.label = permissionSet.name;
            option.userCount = permissionSet.usersCovered;
            options.add(option);
        }

        return options;
    }

    // Adds the blockers and warnings of the Basics step.
    private static void addBasicsFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] The name and the API name
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_BASICS;

        if (String.isBlank(draft.agentName)) addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_NAME_REQUIRED, Label.AI_Wizard_Finding_NameRequired_Title, Label.AI_Wizard_Finding_NameRequired_Message, null);

        if (String.isBlank(draft.developerName)) {

            addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_REQUIRED, Label.AI_Wizard_Finding_DeveloperNameRequired_Title, Label.AI_Wizard_Finding_DeveloperNameRequired_Message, null);

        } else if (!Pattern.matches(AIAssistApplicationConstants.WIZARD_DEVELOPER_NAME_PATTERN, draft.developerName.trim())) {

            addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_FORMAT, Label.AI_Wizard_Finding_DeveloperNameFormat_Title, Label.AI_Wizard_Finding_DeveloperNameFormat_Message, null);

        } else {

            String developerName = draft.developerName.trim();
            Id agentId = draft.agentId;
            Integer sameNameCount = [SELECT COUNT() FROM AIAgent__c WHERE DeveloperName__c = :developerName AND Id != :agentId WITH SYSTEM_MODE LIMIT 1];
            check.isDeveloperNameTaken = sameNameCount > 0;

            if (check.isDeveloperNameTaken) addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_TAKEN, Label.AI_Wizard_Finding_DeveloperNameTaken_Title, Label.AI_Wizard_Finding_DeveloperNameTaken_Message, null);
        }

        // [2] At least one object
        if (draft.objectApiNames == null || draft.objectApiNames.isEmpty()) addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_OBJECTS_REQUIRED, Label.AI_Wizard_Finding_ObjectsRequired_Title, Label.AI_Wizard_Finding_ObjectsRequired_Message, null);

        // [3] A prompt template, or an active default to fall back on
        Id promptTemplateId = draft.promptTemplateId;
        Integer usableTemplateCount = [SELECT COUNT() FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND (Id = :promptTemplateId OR IsDefault__c = TRUE) WITH SYSTEM_MODE LIMIT 1];

        if (usableTemplateCount == 0) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_NO_TEMPLATE, Label.AI_Wizard_Finding_NoTemplate_Title, Label.AI_Wizard_Finding_NoTemplate_Message, null);
    }

    // Adds the findings of the Model step.
    private static void addModelFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] A model must be chosen and still exist
        Id modelId = draft.modelConfigurationId;
        List<AIModelConfiguration__c> models = [SELECT Id, IsActive__c FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_MODEL;

        if (models.isEmpty()) {

            addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_NO_MODEL, Label.AI_Wizard_Finding_NoModel_Title, Label.AI_Wizard_Finding_NoModel_Message, null);

            return;
        }

        // [2] A model that is switched off cannot answer
        if (models[0].IsActive__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_MODEL_INACTIVE, Label.AI_Wizard_Finding_ModelInactive_Title, Label.AI_Wizard_Finding_ModelInactive_Message, null);
    }

    // Adds the warnings of the Skills step.
    private static void addSkillFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, List<AISkill__c> skills) {

        // [1] Warn when more skills are given than reach the model
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_SKILLS;
        Set<Id> skillIds = new Set<Id>(draft.skillIds == null ? new List<Id>() : draft.skillIds);
        Integer maxSkills = AIAssistApplicationConstants.MAX_SKILLS_PER_AGENT;

        if (skillIds.size() > maxSkills) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_TOO_MANY_SKILLS, Label.AI_Wizard_Finding_TooManySkills_Title, String.format(Label.AI_Wizard_Finding_TooManySkills_Message, new List<String>{String.valueOf(maxSkills), String.valueOf(skillIds.size())}), null);

        // [2] Warn about each one that is off, or needs a record of an object the agent does not appear on
        Set<String> lowerObjectNames = getLowerObjectNames(draft);

        for (AISkill__c skill : skills) {

            if (skill.IsActive__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE, Label.AI_Wizard_Finding_ItemInactive_Title, String.format(Label.AI_Wizard_Finding_ItemInactive_Message, new List<String>{skill.Name}), skill.Id);

            Boolean isOtherObject = String.isNotBlank(skill.BoundObjectApiName__c) && !lowerObjectNames.isEmpty() && !lowerObjectNames.contains(skill.BoundObjectApiName__c.toLowerCase());

            if (isOtherObject) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_OBJECT_NOT_ON_AGENT, Label.AI_Wizard_Finding_ObjectNotOnAgent_Title, String.format(Label.AI_Wizard_Finding_ObjectNotOnAgent_Message, new List<String>{skill.Name, skill.BoundObjectApiName__c}), skill.Id);
        }
    }

    // Adds the warnings of the Data sources step.
    private static void addDataSourceFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, List<AIDataSource__c> dataSources) {

        // [1] Warn when more data sources are linked than reach the model
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_DATA_SOURCES;
        Set<Id> dataSourceIds = new Set<Id>(draft.dataSourceIds);
        Integer maxTools = AIAssistApplicationConstants.MAX_TOOLS_PER_KIND;

        if (dataSourceIds.size() > maxTools) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_TOO_MANY_DATA_SOURCES, Label.AI_Wizard_Finding_TooManyDataSources_Title, String.format(Label.AI_Wizard_Finding_TooManyDataSources_Message, new List<String>{String.valueOf(maxTools), String.valueOf(dataSourceIds.size())}), null);

        // [2] Warn about each one that is off, or bound to an object the agent does not appear on
        Set<String> lowerObjectNames = getLowerObjectNames(draft);

        for (AIDataSource__c dataSource : dataSources) {

            if (dataSource.IsActive__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE, Label.AI_Wizard_Finding_ItemInactive_Title, String.format(Label.AI_Wizard_Finding_ItemInactive_Message, new List<String>{dataSource.SourceName__c}), dataSource.Id);

            Boolean isBound = dataSource.BindingType__c == AIAssistApplicationConstants.DATA_SOURCE_BINDING_BOUND;
            Boolean isOtherObject = String.isNotBlank(dataSource.TargetObject__c) && !lowerObjectNames.isEmpty() && !lowerObjectNames.contains(dataSource.TargetObject__c.toLowerCase());

            if (isBound && isOtherObject) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_OBJECT_NOT_ON_AGENT, Label.AI_Wizard_Finding_ObjectNotOnAgent_Title, String.format(Label.AI_Wizard_Finding_ObjectNotOnAgent_Message, new List<String>{dataSource.SourceName__c, dataSource.TargetObject__c}), dataSource.Id);
        }
    }

    // Adds the warnings of the Workflow actions step.
    private static void addActionFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, List<AIWorkflowAction__c> actions, Map<String, Integer> activeVersionByFlowName) {

        // [1] Nothing to check without actions
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_ACTIONS;
        Set<Id> actionIds = new Set<Id>(draft.workflowActionIds);
        if (actionIds.isEmpty()) return;

        // [2] Warn when actions are linked but the org has them switched off, or more are linked than reach the model
        if (AIAssistSettingsService.getUiSettings().IsWorkflowActionsEnabled__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_WORKFLOW_ACTIONS_DISABLED, Label.AI_Wizard_Finding_WorkflowActionsDisabled_Title, Label.AI_Wizard_Finding_WorkflowActionsDisabled_Message, null);

        Integer maxTools = AIAssistApplicationConstants.MAX_TOOLS_PER_KIND;

        if (actionIds.size() > maxTools) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_TOO_MANY_ACTIONS, Label.AI_Wizard_Finding_TooManyActions_Title, String.format(Label.AI_Wizard_Finding_TooManyActions_Message, new List<String>{String.valueOf(maxTools), String.valueOf(actionIds.size())}), null);

        // [3] Warn about each one that is off, runs a flow with no active version, or is for an object the agent does not appear on
        Set<String> lowerObjectNames = getLowerObjectNames(draft);

        for (AIWorkflowAction__c action : actions) {

            if (action.IsActive__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_ITEM_INACTIVE, Label.AI_Wizard_Finding_ItemInactive_Title, String.format(Label.AI_Wizard_Finding_ItemInactive_Message, new List<String>{action.ActionName__c}), action.Id);

            if (isFlowAction(action) && !activeVersionByFlowName.containsKey(action.FlowAPIName__c)) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_FLOW_NO_ACTIVE_VERSION, Label.AI_Wizard_Finding_FlowNoActiveVersion_Title, String.format(Label.AI_Wizard_Finding_FlowNoActiveVersion_Message, new List<String>{action.ActionName__c}), action.Id);

            Boolean isOtherObject = String.isNotBlank(action.TargetObject__c) && !lowerObjectNames.isEmpty() && !lowerObjectNames.contains(action.TargetObject__c.toLowerCase());

            if (isOtherObject) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_OBJECT_NOT_ON_AGENT, Label.AI_Wizard_Finding_ObjectNotOnAgent_Title, String.format(Label.AI_Wizard_Finding_ObjectNotOnAgent_Message, new List<String>{action.ActionName__c, action.TargetObject__c}), action.Id);
        }
    }

    // Adds the findings of the Conversations and Limits steps.
    private static void addLimitFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, AIAgentWizardDataStructure.PolicyInfo policy) {

        // [1] Global conversations are seen by everyone who can see the record
        if (draft.conversationVisibility == AIAssistApplicationConstants.AGENT_VISIBILITY_GLOBAL) addFinding(check, false, AIAssistApplicationConstants.WIZARD_STEP_CONVERSATIONS, AIAssistApplicationConstants.WIZARD_CODE_GLOBAL_VISIBILITY, Label.AI_Wizard_Finding_GlobalVisibility_Title, Label.AI_Wizard_Finding_GlobalVisibility_Message, null);

        // [2] Each limit must be 1 or more, or blank. The step is the one that holds the first limit that is wrong.
        Boolean isConversationLimitWrong = isBelowOne(draft.idleTimeoutMinutes) || isBelowOne(draft.conversationRetentionDays);
        Boolean isLimitWrong = isBelowOne(draft.maxMessagesPerConversation) || isBelowOne(draft.maxTokensPerConversation) || isBelowOne(draft.maxToolCallingIterations);

        if (isLimitWrong) addFinding(check, true, AIAssistApplicationConstants.WIZARD_STEP_LIMITS, AIAssistApplicationConstants.WIZARD_CODE_CONVERSATION_LIMITS_MUST_BE_POSITIVE, Label.AI_Wizard_Finding_ConversationLimitsMustBePositive_Title, Label.AI_Wizard_Finding_ConversationLimitsMustBePositive_Message, null);
        else if (isConversationLimitWrong) addFinding(check, true, AIAssistApplicationConstants.WIZARD_STEP_CONVERSATIONS, AIAssistApplicationConstants.WIZARD_CODE_CONVERSATION_LIMITS_MUST_BE_POSITIVE, Label.AI_Wizard_Finding_ConversationLimitsMustBePositive_Title, Label.AI_Wizard_Finding_ConversationLimitsMustBePositive_Message, null);

        // [3] Warn when the token limit is more than the policy that covers most users allows in a day
        if (policy != null && policy.maxTokensPer24Hours != null && draft.maxTokensPerConversation != null && draft.maxTokensPerConversation > policy.maxTokensPer24Hours) addFinding(check, false, AIAssistApplicationConstants.WIZARD_STEP_LIMITS, AIAssistApplicationConstants.WIZARD_CODE_TOKENS_OVER_POLICY, Label.AI_Wizard_Finding_TokensOverPolicy_Title, String.format(Label.AI_Wizard_Finding_TokensOverPolicy_Message, new List<String>{draft.maxTokensPerConversation.format(), policy.policyName, policy.maxTokensPer24Hours.format()}), null);

        // [4] Warn when the tool rounds are more than the org allows
        Decimal orgCap = AIAssistSettingsService.getSettings().MaxToolCallingIterationsCap__c;

        if (orgCap != null && draft.maxToolCallingIterations != null && draft.maxToolCallingIterations > orgCap) addFinding(check, false, AIAssistApplicationConstants.WIZARD_STEP_LIMITS, AIAssistApplicationConstants.WIZARD_CODE_TOOL_ROUNDS_OVER_CAP, Label.AI_Wizard_Finding_ToolRoundsOverCap_Title, String.format(Label.AI_Wizard_Finding_ToolRoundsOverCap_Message, new List<String>{draft.maxToolCallingIterations.format(), orgCap.format()}), null);
    }

    // Adds the warnings of the Access step.
    private static void addAccessFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, AIAgentWizardDataStructure.PolicyInfo policy) {

        // [1] An agent for assigned users only with nobody assigned
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_ACCESS;
        Boolean isAssignedOnly = draft.accessMode != AIAssistApplicationConstants.ACCESS_MODE_ALL_USERS;
        Boolean hasAssignment = false;

        for (AIAgentWizardDataStructure.AssignmentView assignment : draft.assignments) {

            if (assignment.isActive != false) hasAssignment = true;
        }

        if (isAssignedOnly && !hasAssignment) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_NO_ASSIGNMENTS, Label.AI_Wizard_Finding_NoAssignments_Title, Label.AI_Wizard_Finding_NoAssignments_Message, null);

        // [2] No default usage policy, so a user with none of their own can read but not send
        if (policy == null) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_NO_POLICY, Label.AI_Wizard_Finding_NoPolicy_Title, Label.AI_Wizard_Finding_NoPolicy_Message, null);
    }

    // Adds the blockers and warnings of the Basics step that can be read from a saved agent: the objects and the prompt template.
    private static void addListBasicsFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, ListContext context) {

        // [1] At least one object
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_BASICS;

        if (draft.objectApiNames == null || draft.objectApiNames.isEmpty()) addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_OBJECTS_REQUIRED, Label.AI_Wizard_Finding_ObjectsRequired_Title, Label.AI_Wizard_Finding_ObjectsRequired_Message, null);

        // [2] A prompt template, or an active default to fall back on
        Boolean isTemplateUsable = draft.promptTemplateId != null && context.activeTemplateIds.contains(draft.promptTemplateId);

        if (!isTemplateUsable && !context.hasDefaultTemplate) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_NO_TEMPLATE, Label.AI_Wizard_Finding_NoTemplate_Title, Label.AI_Wizard_Finding_NoTemplate_Message, null);
    }

    // Adds the findings of the Model step for a saved agent.
    private static void addListModelFindings(AIAgentWizardDataStructure.DraftCheck check, AIAgentWizardDataStructure.AgentDraft draft, ListContext context) {

        // [1] A model must be chosen and still exist
        Integer step = AIAssistApplicationConstants.WIZARD_STEP_MODEL;

        if (draft.modelConfigurationId == null || !context.modelById.containsKey(draft.modelConfigurationId)) {

            addFinding(check, true, step, AIAssistApplicationConstants.WIZARD_CODE_NO_MODEL, Label.AI_Wizard_Finding_NoModel_Title, Label.AI_Wizard_Finding_NoModel_Message, null);

            return;
        }

        // [2] A model that is switched off cannot answer
        if (context.modelById.get(draft.modelConfigurationId).IsActive__c != true) addFinding(check, false, step, AIAssistApplicationConstants.WIZARD_CODE_MODEL_INACTIVE, Label.AI_Wizard_Finding_ModelInactive_Title, Label.AI_Wizard_Finding_ModelInactive_Message, null);
    }

    // Reads what every agent is compared with: the models, data sources, actions and flows they use, the prompt templates that can answer, and the policy.
    private static ListContext getListContext(List<AIAgentWizardDataStructure.AgentDraft> drafts) {

        // [1] Collect the ids every agent names
        Set<Id> modelIds = new Set<Id>();
        Set<Id> templateIds = new Set<Id>();
        Set<Id> dataSourceIds = new Set<Id>();
        Set<Id> actionIds = new Set<Id>();

        for (AIAgentWizardDataStructure.AgentDraft draft : drafts) {

            if (draft.modelConfigurationId != null) modelIds.add(draft.modelConfigurationId);

            if (draft.promptTemplateId != null) templateIds.add(draft.promptTemplateId);

            dataSourceIds.addAll(draft.dataSourceIds);
            actionIds.addAll(draft.workflowActionIds);
        }

        // [2] Read each kind once
        ListContext context = new ListContext();
        context.modelById = new Map<Id, AIModelConfiguration__c>([SELECT Id, IsActive__c FROM AIModelConfiguration__c WHERE Id IN :modelIds WITH SYSTEM_MODE LIMIT 2000]);
        context.dataSourceById = new Map<Id, AIDataSource__c>(getDataSources(dataSourceIds));
        context.actionById = new Map<Id, AIWorkflowAction__c>(getActions(actionIds));
        context.activeVersionByFlowName = getActiveFlowVersions(getFlowNames(context.actionById.values()));

        for (AIPromptTemplate__c promptTemplate : [SELECT Id, IsDefault__c FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND (Id IN :templateIds OR IsDefault__c = TRUE) WITH SYSTEM_MODE LIMIT 2000]) {

            context.activeTemplateIds.add(promptTemplate.Id);

            if (promptTemplate.IsDefault__c == true) context.hasDefaultTemplate = true;
        }

        // [3] Read the policy that covers most users
        context.policy = getPolicyInfo();

        return context;
    }

    // The skills with these ids, in name order.
    private static List<AISkill__c> getSkills(Set<Id> skillIds) {

        // [1] Nothing to read without ids
        if (skillIds.isEmpty()) return new List<AISkill__c>();

        return [SELECT Id, Name, BoundObjectApiName__c, IsActive__c FROM AISkill__c WHERE Id IN :skillIds WITH SYSTEM_MODE ORDER BY Name LIMIT 2000];
    }

    // The data sources with these ids, in name order.
    private static List<AIDataSource__c> getDataSources(Set<Id> dataSourceIds) {

        // [1] Nothing to read without ids
        if (dataSourceIds.isEmpty()) return new List<AIDataSource__c>();

        return [SELECT Id, SourceName__c, BindingType__c, TargetObject__c, IsActive__c FROM AIDataSource__c WHERE Id IN :dataSourceIds WITH SYSTEM_MODE ORDER BY SourceName__c LIMIT 2000];
    }

    // The workflow actions with these ids, in name order.
    private static List<AIWorkflowAction__c> getActions(Set<Id> actionIds) {

        // [1] Nothing to read without ids
        if (actionIds.isEmpty()) return new List<AIWorkflowAction__c>();

        return [SELECT Id, ActionName__c, ActionType__c, FlowAPIName__c, TargetObject__c, IsActive__c FROM AIWorkflowAction__c WHERE Id IN :actionIds WITH SYSTEM_MODE ORDER BY ActionName__c LIMIT 2000];
    }

    // The API names of the flows the actions run.
    private static Set<String> getFlowNames(List<AIWorkflowAction__c> actions) {

        // [1] Keep the name of each flow action
        Set<String> flowNames = new Set<String>();

        for (AIWorkflowAction__c action : actions) {

            if (isFlowAction(action) && String.isNotBlank(action.FlowAPIName__c)) flowNames.add(action.FlowAPIName__c);
        }

        return flowNames;
    }

    // The data sources of the agent that were read for the list, in name order.
    private static List<AIDataSource__c> getContextDataSources(AIAgentWizardDataStructure.AgentDraft draft, ListContext context) {

        // [1] Pick the ones the agent links
        List<AIDataSource__c> dataSources = new List<AIDataSource__c>();

        for (Id dataSourceId : new Set<Id>(draft.dataSourceIds)) {

            if (context.dataSourceById.containsKey(dataSourceId)) dataSources.add(context.dataSourceById.get(dataSourceId));
        }

        return dataSources;
    }

    // The workflow actions of the agent that were read for the list.
    private static List<AIWorkflowAction__c> getContextActions(AIAgentWizardDataStructure.AgentDraft draft, ListContext context) {

        // [1] Pick the ones the agent links
        List<AIWorkflowAction__c> actions = new List<AIWorkflowAction__c>();

        for (Id actionId : new Set<Id>(draft.workflowActionIds)) {

            if (context.actionById.containsKey(actionId)) actions.add(context.actionById.get(actionId));
        }

        return actions;
    }

    // Says whether the check has no blocker.
    private static void setCanActivate(AIAgentWizardDataStructure.DraftCheck check) {

        // [1] Any blocker stops activation
        check.canActivate = true;

        for (AIAgentWizardDataStructure.Finding finding : check.findings) {

            if (finding.severity == AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER) check.canActivate = false;
        }
    }

    // Adds one finding to the check.
    private static void addFinding(AIAgentWizardDataStructure.DraftCheck check, Boolean isBlocker, Integer step, String code, String title, String message, Id itemId) {

        // [1] Build the finding
        AIAgentWizardDataStructure.Finding finding = new AIAgentWizardDataStructure.Finding();
        finding.severity = isBlocker ? AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER : AIAssistApplicationConstants.WIZARD_SEVERITY_WARNING;
        finding.step = step;
        finding.code = code;
        finding.title = title;
        finding.message = message;
        finding.itemId = itemId;
        check.findings.add(finding);
    }

    // The object names of the draft in lower case, for comparing with the objects data sources and actions are bound to.
    private static Set<String> getLowerObjectNames(AIAgentWizardDataStructure.AgentDraft draft) {

        // [1] Lower case each name
        Set<String> lowerNames = new Set<String>();

        if (draft.objectApiNames == null) return lowerNames;

        for (String objectName : draft.objectApiNames) lowerNames.add(objectName.toLowerCase());

        return lowerNames;
    }

    // True for a limit that was typed and is below 1.
    private static Boolean isBelowOne(Decimal limitValue) {

        // [1] Blank is allowed
        return limitValue != null && limitValue < 1;
    }

    // True for an action that runs a flow.
    private static Boolean isFlowAction(AIWorkflowAction__c action) {

        // [1] Both kinds of flow need an active version
        return action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW || action.ActionType__c == AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_SCREEN_FLOW;
    }

    // The ids of the active users who hold any of the permission sets or permission set groups, by API name. Only users assigned the set or the group by name are counted.
    private static Set<Id> getUserIdsHoldingAny(Set<String> names) {

        // [1] Join the holders of every name
        Set<Id> userIds = new Set<Id>();

        for (Set<Id> holderIds : getHolderIdsByName(names).values()) userIds.addAll(holderIds);

        return userIds;
    }

    // The ids of the active users who hold each permission set or permission set group, keyed by API name. A name nobody holds is missing from the map.
    private static Map<String, Set<Id>> getHolderIdsByName(Set<String> names) {

        // [1] Nothing to find without names
        Map<String, Set<Id>> holderIdsByName = new Map<String, Set<Id>>();
        if (names.isEmpty()) return holderIdsByName;

        // [2] Read the holders of the permission sets, then of the permission set groups
        for (PermissionSetAssignment holder : [SELECT AssigneeId, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN :names AND PermissionSet.Type != 'Group' AND Assignee.IsActive = TRUE WITH SYSTEM_MODE LIMIT 5000]) {

            if (!holderIdsByName.containsKey(holder.PermissionSet.Name)) holderIdsByName.put(holder.PermissionSet.Name, new Set<Id>());

            holderIdsByName.get(holder.PermissionSet.Name).add(holder.AssigneeId);
        }

        for (PermissionSetAssignment groupHolder : [SELECT AssigneeId, PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE PermissionSetGroup.DeveloperName IN :names AND Assignee.IsActive = TRUE WITH SYSTEM_MODE LIMIT 5000]) {

            if (!holderIdsByName.containsKey(groupHolder.PermissionSetGroup.DeveloperName)) holderIdsByName.put(groupHolder.PermissionSetGroup.DeveloperName, new Set<Id>());

            holderIdsByName.get(groupHolder.PermissionSetGroup.DeveloperName).add(groupHolder.AssigneeId);
        }

        return holderIdsByName;
    }

    // The API names of every permission set the user holds: assigned directly, the name of each group assigned to them, and the permission sets inside each group.
    private static Set<String> getHeldPermissionSetNames(Id userId) {

        // [1] Collect the names the user holds directly, and the groups they are assigned
        Set<String> heldNames = new Set<String>();
        Set<Id> heldGroupIds = new Set<Id>();

        for (PermissionSetAssignment heldAssignment : [SELECT PermissionSet.Name, PermissionSetGroupId, PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE AssigneeId = :userId WITH SYSTEM_MODE LIMIT 2000]) {

            heldNames.add(heldAssignment.PermissionSet.Name);

            if (heldAssignment.PermissionSetGroupId != null) {

                heldGroupIds.add(heldAssignment.PermissionSetGroupId);
                heldNames.add(heldAssignment.PermissionSetGroup.DeveloperName);
            }
        }

        // [2] Add the permission sets inside each group
        for (PermissionSetGroupComponent member : [SELECT PermissionSet.Name FROM PermissionSetGroupComponent WHERE PermissionSetGroupId IN :heldGroupIds WITH SYSTEM_MODE LIMIT 2000]) heldNames.add(member.PermissionSet.Name);

        return heldNames;
    }
}
