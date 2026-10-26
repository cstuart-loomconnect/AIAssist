/*
Class Name: AIAgentWizardSaveService

=================================================================
=================================================================

Description: Saves the whole draft of the AI Agent Wizard in one call, and switches an agent on or off from the list.

Step 1: Check the draft and refuse what cannot be saved, or activated when that was asked for
Step 2: Save the agent, then replace its skill, data source and workflow action links, then its access list
Step 3: Switch the agent on only after everything else is saved, and report what was saved
Step 4: Switch an agent on or off from the list of agents, refusing to switch it on while a blocker is left

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAgentWizardSaveService {

    public class AIAgentWizardSaveServiceException extends Exception {}

    // Blockers that stop even a draft being saved, because the object would refuse the save.
    private static final Set<String> SAVE_BLOCKER_CODES = new Set<String>{
        AIAssistApplicationConstants.WIZARD_CODE_NAME_REQUIRED,
        AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_REQUIRED,
        AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_FORMAT,
        AIAssistApplicationConstants.WIZARD_CODE_DEVELOPER_NAME_TAKEN,
        AIAssistApplicationConstants.WIZARD_CODE_CONVERSATION_LIMITS_MUST_BE_POSITIVE
    };

    // Saves the agent, its links and its access list. The agent is switched on only when asked and only after the links are saved, and a blocker refuses that. Without it the agent is saved switched off.
    public static AIAgentWizardDataStructure.SaveResult saveAgent(AIAgentWizardDataStructure.AgentDraft draft, Boolean shouldActivate) {

        // [1] Refuse a user who may not use the tab, a missing draft and an id that belongs to nothing
        AIAssistSettingsEditorService.requireManager();
        if (draft == null) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Draft_Required);

        AIAgent__c savedAgent = null;

        if (draft.agentId != null) {

            List<AIAgent__c> savedAgents = [SELECT Id, IsActive__c FROM AIAgent__c WHERE Id = :draft.agentId WITH SYSTEM_MODE LIMIT 1];
            if (savedAgents.isEmpty()) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Not_Found);

            savedAgent = savedAgents[0];
        }

        // [2] Refuse what the object would refuse, then refuse activation when any blocker is left
        AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(draft);

        for (AIAgentWizardDataStructure.Finding finding : check.findings) {

            if (finding.severity == AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER && SAVE_BLOCKER_CODES.contains(finding.code)) throw new AIAgentWizardSaveServiceException(finding.message);
        }

        Boolean isActivating = shouldActivate == true;
        if (isActivating && !check.canActivate) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Cannot_Activate);

        // [3] Refuse links and assignments that point at nothing
        List<Id> dataSourceIds = getDistinctIds(draft.dataSourceIds);
        List<Id> workflowActionIds = getDistinctIds(draft.workflowActionIds);
        Integer dataSourceCount = [SELECT COUNT() FROM AIDataSource__c WHERE Id IN :dataSourceIds WITH SYSTEM_MODE];
        Integer workflowActionCount = [SELECT COUNT() FROM AIWorkflowAction__c WHERE Id IN :workflowActionIds WITH SYSTEM_MODE];
        List<Id> skillIds = getDistinctIds(draft.skillIds);
        Integer skillCount = [SELECT COUNT() FROM AISkill__c WHERE Id IN :skillIds WITH SYSTEM_MODE];
        if (dataSourceCount != dataSourceIds.size() || workflowActionCount != workflowActionIds.size() || skillCount != skillIds.size()) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Item_Missing);

        for (AIAgentWizardDataStructure.AssignmentView assignment : draft.assignments) {

            Boolean isUser = assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER && assignment.userId != null;
            Boolean isPermissionSet = assignment.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET && String.isNotBlank(assignment.permissionSetName);
            if (!isUser && !isPermissionSet) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Assignee);
        }

        // [4] Build the agent. A live agent stays live while it is saved, a new or switched off one starts off.
        AIAgent__c agent = savedAgent == null ? new AIAgent__c() : new AIAgent__c(Id = savedAgent.Id);
        agent.Name = draft.agentName.trim();
        agent.DeveloperName__c = draft.developerName.trim();
        agent.Description__c = getTextOrNull(draft.description);
        agent.AIAgentPersona__c = getTextOrNull(draft.persona);
        agent.GreetingMessage__c = getTextOrNull(draft.greeting);
        agent.ObjectApiNames__c = String.join(getDistinctNames(draft.objectApiNames), ',');
        agent.AIPromptTemplate__c = draft.promptTemplateId;
        agent.AIModelConfiguration__c = draft.modelConfigurationId;
        agent.ConversationLoadTrigger__c = getTextOrNull(draft.conversationLoadTrigger);
        agent.AllowConversationResume__c = draft.allowConversationResume == true;
        agent.SingleActiveConversationPerRecord__c = draft.singleActiveConversationPerRecord == true;
        agent.ConversationVisibility__c = getTextOrNull(draft.conversationVisibility);
        agent.IdleTimeoutMinutes__c = draft.idleTimeoutMinutes;
        agent.ConversationRetentionDays__c = draft.conversationRetentionDays;
        agent.RetentionTrigger__c = getTextOrNull(draft.retentionTrigger);
        agent.MaxMessagesPerConversation__c = draft.maxMessagesPerConversation;
        agent.MaxTokensPerConversation__c = draft.maxTokensPerConversation;
        agent.MaxToolCallingIterations__c = draft.maxToolCallingIterations;
        agent.TokenTrackingMethod__c = getTextOrNull(draft.tokenTrackingMethod);
        agent.AccessMode__c = getTextOrNull(draft.accessMode);
        agent.IsActive__c = savedAgent != null && savedAgent.IsActive__c == true && isActivating;

        // [5] Refuse a choice the pick lists do not offer
        AIAssistSettingsEditorService.validateChoice(agent, 'ConversationLoadTrigger__c', AIAgent__c.ConversationLoadTrigger__c);
        AIAssistSettingsEditorService.validateChoice(agent, 'ConversationVisibility__c', AIAgent__c.ConversationVisibility__c);
        AIAssistSettingsEditorService.validateChoice(agent, 'RetentionTrigger__c', AIAgent__c.RetentionTrigger__c);
        AIAssistSettingsEditorService.validateChoice(agent, 'TokenTrackingMethod__c', AIAgent__c.TokenTrackingMethod__c);
        AIAssistSettingsEditorService.validateChoice(agent, 'AccessMode__c', AIAgent__c.AccessMode__c);

        // [6] Save the agent first, because the links belong to it
        Database.upsert(agent, AccessLevel.SYSTEM_MODE);

        // [7] Replace the links and the access list
        saveDataSourceLinks(agent.Id, dataSourceIds);
        saveWorkflowActionLinks(agent.Id, workflowActionIds);
        saveSkillLinks(agent.Id, skillIds);
        saveAssignments(agent.Id, draft.assignments);

        // [8] Switch the agent on last, once everything it needs is saved
        if (isActivating && agent.IsActive__c != true) Database.update(new AIAgent__c(Id = agent.Id, IsActive__c = true), AccessLevel.SYSTEM_MODE);

        // [9] Report what was saved
        AIAgentWizardDataStructure.SaveResult result = new AIAgentWizardDataStructure.SaveResult();
        result.agentId = agent.Id;
        result.agentName = agent.Name;
        result.isActive = isActivating;
        result.modelName = getModelName(agent.AIModelConfiguration__c);
        result.objectApiNames = getDistinctNames(draft.objectApiNames);
        result.dataSourceCount = dataSourceIds.size();
        result.workflowActionCount = workflowActionIds.size();
        result.skillCount = skillIds.size();
        result.assignmentCount = draft.assignments.size();
        result.userCount = check.accessUserCount;
        result.isCreated = savedAgent == null;

        return result;
    }

    // Switches an agent on or off from the list, and gives back its new line of the list. Switching on runs the same blocker check as saveAgent and refuses with the text of the first blocker.
    public static AIAgentWizardDataStructure.AgentRow setAgentActive(Id agentId, Boolean isActive) {

        // [1] Refuse a user who may not use the tab, and an agent that is gone
        AIAssistSettingsEditorService.requireManager();
        Integer agentCount = [SELECT COUNT() FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];
        if (agentCount == 0) throw new AIAgentWizardSaveServiceException(Label.AI_Wizard_Error_Not_Found);

        // [2] Refuse to switch on an agent that has a blocker
        Boolean isActivating = isActive == true;

        if (isActivating) {

            AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardCheckService.checkDraft(AIAgentWizardEditorService.getAgentDraft(agentId));

            for (AIAgentWizardDataStructure.Finding finding : check.findings) {

                if (finding.severity == AIAssistApplicationConstants.WIZARD_SEVERITY_BLOCKER) throw new AIAgentWizardSaveServiceException(finding.message);
            }
        }

        // [3] Switch it on or off, and read its line again
        Database.update(new AIAgent__c(Id = agentId, IsActive__c = isActivating), AccessLevel.SYSTEM_MODE);

        return AIAgentWizardEditorService.getAgentRow(agentId);
    }

    // Makes the active data source links of the agent match the draft: keeps those that stay, switches on any that were off, adds new ones and removes active ones that were taken out.
    private static void saveDataSourceLinks(Id agentId, List<Id> dataSourceIds) {

        // [1] Read the links the agent has now, whether they are on or off
        Set<Id> wantedIds = new Set<Id>(dataSourceIds);
        Set<Id> linkedIds = new Set<Id>();
        List<AIAgentDataSource__c> linksToDelete = new List<AIAgentDataSource__c>();
        List<AIAgentDataSource__c> linksToSwitchOn = new List<AIAgentDataSource__c>();

        for (AIAgentDataSource__c link : [SELECT Id, AIDataSource__c, IsActive__c FROM AIAgentDataSource__c WHERE AIAgent__c = :agentId WITH SYSTEM_MODE LIMIT 2000]) {

            linkedIds.add(link.AIDataSource__c);

            if (!wantedIds.contains(link.AIDataSource__c) && link.IsActive__c == true) linksToDelete.add(link);
            else if (wantedIds.contains(link.AIDataSource__c) && link.IsActive__c != true) linksToSwitchOn.add(new AIAgentDataSource__c(Id = link.Id, IsActive__c = true));
        }

        // [2] Add a link for each data source that has none
        List<AIAgentDataSource__c> linksToInsert = new List<AIAgentDataSource__c>();

        for (Id dataSourceId : dataSourceIds) {

            if (!linkedIds.contains(dataSourceId)) linksToInsert.add(new AIAgentDataSource__c(AIAgent__c = agentId, AIDataSource__c = dataSourceId, IsActive__c = true));
        }

        // [3] Save the changes
        Database.delete(linksToDelete, AccessLevel.SYSTEM_MODE);
        Database.update(linksToSwitchOn, AccessLevel.SYSTEM_MODE);
        Database.insert(linksToInsert, AccessLevel.SYSTEM_MODE);
    }

    // Makes the active skill links of the agent match the draft, the same way as the data source links.
    private static void saveSkillLinks(Id agentId, List<Id> skillIds) {

        // [1] Read the links the agent has now, whether they are on or off
        Set<Id> wantedIds = new Set<Id>(skillIds);
        Set<Id> linkedIds = new Set<Id>();
        List<AIAgentSkill__c> linksToDelete = new List<AIAgentSkill__c>();
        List<AIAgentSkill__c> linksToSwitchOn = new List<AIAgentSkill__c>();

        for (AIAgentSkill__c link : [SELECT Id, AISkill__c, IsActive__c FROM AIAgentSkill__c WHERE AIAgent__c = :agentId WITH SYSTEM_MODE LIMIT 2000]) {

            linkedIds.add(link.AISkill__c);

            if (!wantedIds.contains(link.AISkill__c) && link.IsActive__c == true) linksToDelete.add(link);
            else if (wantedIds.contains(link.AISkill__c) && link.IsActive__c != true) linksToSwitchOn.add(new AIAgentSkill__c(Id = link.Id, IsActive__c = true));
        }

        // [2] Add a link for each skill that has none
        List<AIAgentSkill__c> linksToInsert = new List<AIAgentSkill__c>();

        for (Id skillId : skillIds) {

            if (!linkedIds.contains(skillId)) linksToInsert.add(new AIAgentSkill__c(AIAgent__c = agentId, AISkill__c = skillId, IsActive__c = true));
        }

        // [3] Save the changes
        Database.delete(linksToDelete, AccessLevel.SYSTEM_MODE);
        Database.update(linksToSwitchOn, AccessLevel.SYSTEM_MODE);
        Database.insert(linksToInsert, AccessLevel.SYSTEM_MODE);
    }

    // Makes the active workflow action links of the agent match the draft, the same way as the data source links.
    private static void saveWorkflowActionLinks(Id agentId, List<Id> workflowActionIds) {

        // [1] Read the links the agent has now, whether they are on or off
        Set<Id> wantedIds = new Set<Id>(workflowActionIds);
        Set<Id> linkedIds = new Set<Id>();
        List<AIAgentWorkflowAction__c> linksToDelete = new List<AIAgentWorkflowAction__c>();
        List<AIAgentWorkflowAction__c> linksToSwitchOn = new List<AIAgentWorkflowAction__c>();

        for (AIAgentWorkflowAction__c link : [SELECT Id, AIWorkflowAction__c, IsActive__c FROM AIAgentWorkflowAction__c WHERE AIAgent__c = :agentId WITH SYSTEM_MODE LIMIT 2000]) {

            linkedIds.add(link.AIWorkflowAction__c);

            if (!wantedIds.contains(link.AIWorkflowAction__c) && link.IsActive__c == true) linksToDelete.add(link);
            else if (wantedIds.contains(link.AIWorkflowAction__c) && link.IsActive__c != true) linksToSwitchOn.add(new AIAgentWorkflowAction__c(Id = link.Id, IsActive__c = true));
        }

        // [2] Add a link for each workflow action that has none
        List<AIAgentWorkflowAction__c> linksToInsert = new List<AIAgentWorkflowAction__c>();

        for (Id workflowActionId : workflowActionIds) {

            if (!linkedIds.contains(workflowActionId)) linksToInsert.add(new AIAgentWorkflowAction__c(AIAgent__c = agentId, AIWorkflowAction__c = workflowActionId, IsActive__c = true));
        }

        // [3] Save the changes
        Database.delete(linksToDelete, AccessLevel.SYSTEM_MODE);
        Database.update(linksToSwitchOn, AccessLevel.SYSTEM_MODE);
        Database.insert(linksToInsert, AccessLevel.SYSTEM_MODE);
    }

    // Makes the access list of the agent match the draft: keeps matching lines, changes their switch, adds new lines and removes lines that were taken out.
    private static void saveAssignments(Id agentId, List<AIAgentWizardDataStructure.AssignmentView> views) {

        // [1] Key each line of the draft by who it names
        Map<String, AIAgentWizardDataStructure.AssignmentView> viewByKey = new Map<String, AIAgentWizardDataStructure.AssignmentView>();

        for (AIAgentWizardDataStructure.AssignmentView view : views) viewByKey.put(getAssignmentKey(view.assigneeType, view.userId, view.permissionSetName), view);

        // [2] Compare with the lines saved now
        Set<String> savedKeys = new Set<String>();
        List<AIAgentAssignment__c> assignmentsToDelete = new List<AIAgentAssignment__c>();
        List<AIAgentAssignment__c> assignmentsToUpdate = new List<AIAgentAssignment__c>();

        for (AIAgentAssignment__c assignment : [SELECT Id, AssigneeType__c, User__c, PermissionSetName__c, IsActive__c FROM AIAgentAssignment__c WHERE AIAgent__c = :agentId WITH SYSTEM_MODE LIMIT 2000]) {

            String key = getAssignmentKey(assignment.AssigneeType__c, assignment.User__c, assignment.PermissionSetName__c);
            savedKeys.add(key);

            if (!viewByKey.containsKey(key)) {

                assignmentsToDelete.add(assignment);

            } else if ((viewByKey.get(key).isActive != false) != (assignment.IsActive__c == true)) {

                assignmentsToUpdate.add(new AIAgentAssignment__c(Id = assignment.Id, IsActive__c = viewByKey.get(key).isActive != false));
            }
        }

        // [3] Add a line for each one that is new
        List<AIAgentAssignment__c> assignmentsToInsert = new List<AIAgentAssignment__c>();

        for (String key : viewByKey.keySet()) {

            if (savedKeys.contains(key)) continue;

            AIAgentWizardDataStructure.AssignmentView view = viewByKey.get(key);
            AIAgentAssignment__c assignment = new AIAgentAssignment__c(AIAgent__c = agentId, AssigneeType__c = view.assigneeType, IsActive__c = view.isActive != false);

            if (view.assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) assignment.User__c = view.userId;
            else assignment.PermissionSetName__c = view.permissionSetName;

            assignmentsToInsert.add(assignment);
        }

        // [4] Save the changes
        Database.delete(assignmentsToDelete, AccessLevel.SYSTEM_MODE);
        Database.update(assignmentsToUpdate, AccessLevel.SYSTEM_MODE);
        Database.insert(assignmentsToInsert, AccessLevel.SYSTEM_MODE);
    }

    // The name of the model, or blank when there is none.
    private static String getModelName(Id modelId) {

        // [1] Read it
        List<AIModelConfiguration__c> models = [SELECT Name FROM AIModelConfiguration__c WHERE Id = :modelId WITH SYSTEM_MODE LIMIT 1];

        return models.isEmpty() ? null : models[0].Name;
    }

    // A key that is the same for the same user or permission set.
    private static String getAssignmentKey(String assigneeType, Id userId, String permissionSetName) {

        // [1] Join the type and the one who is named
        return assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER ? assigneeType + '|' + String.valueOf(userId).left(15) : assigneeType + '|' + permissionSetName;
    }

    // The ids with repeats and blanks left out, in the order given.
    private static List<Id> getDistinctIds(List<Id> ids) {

        // [1] Keep the first of each
        List<Id> distinctIds = new List<Id>();
        Set<Id> seenIds = new Set<Id>();

        for (Id itemId : ids) {

            if (itemId != null && seenIds.add(itemId)) distinctIds.add(itemId);
        }

        return distinctIds;
    }

    // The names trimmed, with repeats and blanks left out, in the order given.
    private static List<String> getDistinctNames(List<String> names) {

        // [1] Keep the first of each
        List<String> distinctNames = new List<String>();

        for (String name : names) {

            if (String.isNotBlank(name) && !distinctNames.contains(name.trim())) distinctNames.add(name.trim());
        }

        return distinctNames;
    }

    // Trims a text, and gives null when nothing is left.
    private static String getTextOrNull(String text) {

        // [1] Blank text is nothing
        if (String.isBlank(text)) return null;

        return text.trim();
    }
}
