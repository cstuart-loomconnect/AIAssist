/*
Class Name: AIToolsSkillEditorService

=================================================================
=================================================================

Description: Reads, checks and saves the AI Skills the Skills panel of the AI Tools tab edits, and lists the existing data sources, workflow actions and agents it can choose from. A skill is only ever built from tools that already exist; nothing is created here but the skill and its links.

Step 1: Read every skill with its tools, the agents that have it, and whether it needs attention
Step 2: List the existing data sources and workflow actions to put in a skill, and the active agents to test it with
Step 3: Check and save one skill and its tools in order, then switch it on so the AI Skill trigger checks it whole
Step 4: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIToolsSkillEditorService {

    public class AIToolsSkillEditorServiceException extends Exception {}

    private static final Pattern API_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');

    // Every skill, for the list. The ones that need attention are marked.
    public static List<AIToolsSkillDataStructure.SkillRow> getSkills() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the skills
        Integer maxResults = AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS;
        List<AISkill__c> skills = [SELECT Id, Name, DeveloperName__c, Description__c, Instructions__c, OutputType__c, BoundObjectApiName__c, IsActive__c, LastTestStatus__c, LastTestedOn__c FROM AISkill__c WITH SYSTEM_MODE ORDER BY Name LIMIT :maxResults];

        // [3] Read the tools and the agents of every skill at once
        Set<Id> skillIds = new Map<Id, AISkill__c>(skills).keySet();
        Map<Id, List<AIToolsSkillDataStructure.SkillTool>> toolsBySkillId = getToolsBySkillId(skillIds);
        Map<Id, List<String>> agentNamesBySkillId = getAgentNamesBySkillId(skillIds);

        // [4] Build one row per skill
        List<AIToolsSkillDataStructure.SkillRow> rows = new List<AIToolsSkillDataStructure.SkillRow>();

        for (AISkill__c skill : skills) {

            rows.add(buildRow(skill, toolsBySkillId.get(skill.Id), agentNamesBySkillId.get(skill.Id)));
        }

        return rows;
    }

    // One skill with everything the wizard edits.
    public static AIToolsSkillDataStructure.SkillDetail getSkill(Id skillId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the skill, its tools and its agents
        AISkill__c skill = findSkill(skillId);
        List<AIToolsSkillDataStructure.SkillTool> tools = getToolsBySkillId(new Set<Id>{skill.Id}).get(skill.Id);
        List<String> agentNames = getAgentNamesBySkillId(new Set<Id>{skill.Id}).get(skill.Id);

        // [3] Build the detail
        AIToolsSkillDataStructure.SkillDetail detail = new AIToolsSkillDataStructure.SkillDetail();
        detail.skillId = skill.Id;
        detail.skillName = skill.Name;
        detail.developerName = skill.DeveloperName__c;
        detail.description = skill.Description__c;
        detail.instructions = skill.Instructions__c;
        detail.outputType = skill.OutputType__c;
        detail.boundObject = skill.BoundObjectApiName__c;
        detail.isActive = skill.IsActive__c == true;
        detail.lastTestStatus = skill.LastTestStatus__c;
        detail.lastTestedOn = skill.LastTestedOn__c;
        detail.tools = tools;
        detail.agentNames = agentNames;
        detail.agentCount = agentNames.size();

        return detail;
    }

    // The existing data sources and workflow actions an administrator can put in a skill, active ones first. Inactive ones are listed so a skill can be built before its tools are switched on.
    public static List<AIToolsSkillDataStructure.ToolOption> getToolOptions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Build one option per data source
        Integer maxResults = AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS;
        List<AIToolsSkillDataStructure.ToolOption> options = new List<AIToolsSkillDataStructure.ToolOption>();

        for (AIDataSource__c dataSource : [SELECT Id, SourceName__c, DeveloperName__c, Description__c, BindingType__c, TargetObject__c, IsActive__c FROM AIDataSource__c WITH SYSTEM_MODE ORDER BY IsActive__c DESC, SourceName__c LIMIT :maxResults]) {

            AIToolsSkillDataStructure.ToolOption option = new AIToolsSkillDataStructure.ToolOption();
            option.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
            option.recordId = dataSource.Id;
            option.name = String.isNotBlank(dataSource.SourceName__c) ? dataSource.SourceName__c : dataSource.DeveloperName__c;
            option.developerName = dataSource.DeveloperName__c;
            option.description = dataSource.Description__c;
            option.bindingType = dataSource.BindingType__c;
            option.targetObject = dataSource.TargetObject__c;
            option.isActive = dataSource.IsActive__c == true;
            options.add(option);
        }

        // [3] Build one option per workflow action
        for (AIWorkflowAction__c action : [SELECT Id, ActionName__c, DeveloperName__c, Description__c, TargetObject__c, ExecutionType__c, IsActive__c FROM AIWorkflowAction__c WITH SYSTEM_MODE ORDER BY IsActive__c DESC, ActionName__c LIMIT :maxResults]) {

            AIToolsSkillDataStructure.ToolOption option = new AIToolsSkillDataStructure.ToolOption();
            option.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_ACTION;
            option.recordId = action.Id;
            option.name = String.isNotBlank(action.ActionName__c) ? action.ActionName__c : action.DeveloperName__c;
            option.developerName = action.DeveloperName__c;
            option.description = action.Description__c;
            option.targetObject = action.TargetObject__c;
            option.executionType = action.ExecutionType__c;
            option.isActive = action.IsActive__c == true;
            options.add(option);
        }

        return options;
    }

    // The agents with a model configuration, active ones first, to test a skill with. The agent only lends its model, persona and prompt template; it does not need the skill.
    public static List<AIToolsSkillDataStructure.AgentOption> getTestAgents() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Build one option per agent that can answer
        Integer maxResults = AIAssistApplicationConstants.TOOLS_LIST_MAX_RESULTS;
        List<AIToolsSkillDataStructure.AgentOption> options = new List<AIToolsSkillDataStructure.AgentOption>();

        for (AIAgent__c agent : [SELECT Id, Name, AIModelConfiguration__r.Name FROM AIAgent__c WHERE AIModelConfiguration__c != NULL WITH SYSTEM_MODE ORDER BY IsActive__c DESC, Name LIMIT :maxResults]) {

            AIToolsSkillDataStructure.AgentOption option = new AIToolsSkillDataStructure.AgentOption();
            option.agentId = agent.Id;
            option.agentName = agent.Name;
            option.modelName = agent.AIModelConfiguration__r.Name;
            options.add(option);
        }

        return options;
    }

    // Saves one skill and its tools, creating it when skillId is blank, and returns it as a list row. The skill is saved switched off first and switched on last, so the AI Skill trigger checks it with its final tools and instructions; a refusal undoes the whole save.
    public static AIToolsSkillDataStructure.SkillRow saveSkill(AIToolsSkillDataStructure.SkillDetail detail) {

        // [1] Refuse a user who may not use the tab, and a save with nothing to save
        AIAssistSettingsEditorService.requireManager();
        if (detail == null) throw new AIToolsSkillEditorServiceException(Label.AI_ToolsSk_Error_Not_Found);

        // [2] A name and an API name are needed; the trigger checks the When To Use It text and the instructions
        if (String.isBlank(detail.skillName)) throw new AIToolsSkillEditorServiceException(String.format(Label.AI_ToolsSk_Error_Required, new List<String>{Schema.AISkill__c.Name.getDescribe().getLabel()}));
        if (String.isBlank(detail.developerName) || !API_NAME_PATTERN.matcher(detail.developerName.trim()).matches()) throw new AIToolsSkillEditorServiceException(String.format(Label.AI_ToolsSk_Error_Required, new List<String>{Schema.AISkill__c.DeveloperName__c.getDescribe().getLabel()}));

        // [3] Keep each tool once, in the order given, and refuse a skill with too many
        List<AIToolsSkillDataStructure.SkillTool> tools = new List<AIToolsSkillDataStructure.SkillTool>();
        Set<Id> toolRecordIds = new Set<Id>();

        for (AIToolsSkillDataStructure.SkillTool tool : detail.tools == null ? new List<AIToolsSkillDataStructure.SkillTool>() : detail.tools) {

            if (tool?.recordId == null || toolRecordIds.contains(tool.recordId)) continue;

            toolRecordIds.add(tool.recordId);
            tools.add(tool);
        }

        if (tools.size() > AIAssistApplicationConstants.SKILL_MAX_TOOLS) throw new AIToolsSkillEditorServiceException(String.format(Label.AI_ToolsSk_Error_Too_Many_Tools, new List<String>{String.valueOf(AIAssistApplicationConstants.SKILL_MAX_TOOLS)}));

        // [4] Check every tool still exists, and note whether any workflow action writes, because then the skill changes records
        Set<Id> existingDataSourceIds = new Map<Id, AIDataSource__c>([SELECT Id FROM AIDataSource__c WHERE Id IN :toolRecordIds WITH SYSTEM_MODE]).keySet();
        Map<Id, AIWorkflowAction__c> existingActionsById = new Map<Id, AIWorkflowAction__c>([SELECT Id, ExecutionType__c FROM AIWorkflowAction__c WHERE Id IN :toolRecordIds WITH SYSTEM_MODE]);
        Boolean hasWriteAction = false;

        for (AIToolsSkillDataStructure.SkillTool tool : tools) {

            Boolean isDataSource = tool.kind == AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;

            if (isDataSource ? !existingDataSourceIds.contains(tool.recordId) : !existingActionsById.containsKey(tool.recordId)) throw new AIToolsSkillEditorServiceException(Label.AI_ToolsSk_Error_Tool_Not_Found);
            if (!isDataSource && existingActionsById.get(tool.recordId).ExecutionType__c == AIAssistApplicationConstants.WORKFLOW_EXECUTION_WRITE) hasWriteAction = true;
        }

        // [5] Put the values on the skill, switched off for now. A skill with a write action always changes records; otherwise the chosen output is kept
        AISkill__c skill = detail.skillId == null ? new AISkill__c() : findSkill(detail.skillId);
        Set<String> outputTypes = new Set<String>{AIAssistApplicationConstants.SKILL_OUTPUT_CHAT_ANSWER, AIAssistApplicationConstants.SKILL_OUTPUT_REPORT};
        skill.Name = detail.skillName.trim();
        skill.DeveloperName__c = detail.developerName.trim();
        skill.Description__c = detail.description == null ? null : detail.description.trim();
        skill.Instructions__c = detail.instructions;
        skill.OutputType__c = hasWriteAction ? AIAssistApplicationConstants.SKILL_OUTPUT_RECORD_CHANGE : (outputTypes.contains(detail.outputType) ? detail.outputType : AIAssistApplicationConstants.SKILL_OUTPUT_CHAT_ANSWER);
        skill.IsActive__c = false;
        skill.LastTestStatus__c = String.isBlank(detail.lastTestStatus) ? null : detail.lastTestStatus;
        skill.LastTestedOn__c = String.isBlank(detail.lastTestStatus) ? null : (detail.lastTestedOn == null ? System.now() : detail.lastTestedOn);

        Savepoint beforeSave = Database.setSavepoint();

        try {

            // [6] Save the skill
            Database.upsert(skill, AccessLevel.SYSTEM_MODE);

            // [7] Remove the tools taken out, renumber the ones kept and add the new ones
            Map<Id, AISkillTool__c> existingToolByRecordId = new Map<Id, AISkillTool__c>();
            List<AISkillTool__c> toolsToDelete = new List<AISkillTool__c>();

            for (AISkillTool__c existingTool : [SELECT Id, AIDataSource__c, AIWorkflowAction__c FROM AISkillTool__c WHERE AISkill__c = :skill.Id WITH SYSTEM_MODE]) {

                Id existingRecordId = existingTool.AIDataSource__c != null ? existingTool.AIDataSource__c : existingTool.AIWorkflowAction__c;

                if (toolRecordIds.contains(existingRecordId)) existingToolByRecordId.put(existingRecordId, existingTool);
                else toolsToDelete.add(existingTool);
            }

            List<AISkillTool__c> toolsToSave = new List<AISkillTool__c>();

            for (Integer toolIndex = 0; toolIndex < tools.size(); toolIndex++) {

                AIToolsSkillDataStructure.SkillTool tool = tools[toolIndex];
                Boolean isDataSource = tool.kind == AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
                AISkillTool__c skillTool = existingToolByRecordId.containsKey(tool.recordId) ? existingToolByRecordId.get(tool.recordId) : new AISkillTool__c(AISkill__c = skill.Id, AIDataSource__c = isDataSource ? tool.recordId : null, AIWorkflowAction__c = isDataSource ? null : tool.recordId);
                skillTool.StepOrder__c = toolIndex + 1;
                skillTool.IsRequired__c = tool.isRequired != false;
                toolsToSave.add(skillTool);
            }

            if (!toolsToDelete.isEmpty()) Database.delete(toolsToDelete, AccessLevel.SYSTEM_MODE);
            if (!toolsToSave.isEmpty()) Database.upsert(toolsToSave, AccessLevel.SYSTEM_MODE);

            // [8] Switch the skill on last, so the trigger checks it with its final tools
            if (detail.isActive == true) Database.update(new AISkill__c(Id = skill.Id, IsActive__c = true), AccessLevel.SYSTEM_MODE);

        } catch (DmlException ex) {

            // [9] Undo the whole save, and turn the refusal into a message the tab can show
            Database.rollback(beforeSave);

            if (detail.skillId == null) skill.Id = null;

            Boolean isDuplicate = ex.getDmlType(0) == StatusCode.DUPLICATE_VALUE;
            throw new AIToolsSkillEditorServiceException(isDuplicate ? Label.AI_ToolsSk_Error_Duplicate : ex.getDmlMessage(0));
        }

        // [10] Read it back as a row
        AISkill__c saved = findSkill(skill.Id);

        return buildRow(saved, getToolsBySkillId(new Set<Id>{saved.Id}).get(saved.Id), getAgentNamesBySkillId(new Set<Id>{saved.Id}).get(saved.Id));
    }

    // Builds one list row, and works out whether the skill needs attention: no tools, a required tool switched off, or a last test that did not pass.
    private static AIToolsSkillDataStructure.SkillRow buildRow(AISkill__c skill, List<AIToolsSkillDataStructure.SkillTool> tools, List<String> agentNames) {

        // [1] Copy the skill's details
        AIToolsSkillDataStructure.SkillRow row = new AIToolsSkillDataStructure.SkillRow();
        row.skillId = skill.Id;
        row.skillName = skill.Name;
        row.developerName = skill.DeveloperName__c;
        row.description = skill.Description__c;
        row.outputType = skill.OutputType__c;
        row.boundObject = skill.BoundObjectApiName__c;
        row.agentCount = agentNames == null ? 0 : agentNames.size();
        row.lastTestStatus = skill.LastTestStatus__c;
        row.lastTestedOn = skill.LastTestedOn__c;
        row.isActive = skill.IsActive__c == true;

        // [2] Count the tools of each kind, and flag a required tool that is switched off
        for (AIToolsSkillDataStructure.SkillTool tool : tools == null ? new List<AIToolsSkillDataStructure.SkillTool>() : tools) {

            if (tool.kind == AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE) row.dataSourceCount++;
            else row.actionCount++;

            if (tool.isRequired == true && tool.isActive != true) row.attention = AIAssistApplicationConstants.SKILL_ATTENTION_TOOL_INACTIVE;
        }

        if (row.dataSourceCount + row.actionCount == 0) row.attention = AIAssistApplicationConstants.SKILL_ATTENTION_NO_TOOLS;

        return row;
    }

    // Reads one skill, or refuses when it is gone.
    private static AISkill__c findSkill(Id skillId) {

        // [1] Read it
        List<AISkill__c> skills = skillId == null ? new List<AISkill__c>() : [SELECT Id, Name, DeveloperName__c, Description__c, Instructions__c, OutputType__c, BoundObjectApiName__c, IsActive__c, LastTestStatus__c, LastTestedOn__c FROM AISkill__c WHERE Id = :skillId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse when there is none
        if (skills.isEmpty()) throw new AIToolsSkillEditorServiceException(Label.AI_ToolsSk_Error_Not_Found);

        return skills[0];
    }

    // The tools of each skill in order, as the tab shows them. Every skill asked for gets a list, empty when it has no tools.
    private static Map<Id, List<AIToolsSkillDataStructure.SkillTool>> getToolsBySkillId(Set<Id> skillIds) {

        // [1] Start with an empty list for each skill
        Map<Id, List<AIToolsSkillDataStructure.SkillTool>> toolsBySkillId = new Map<Id, List<AIToolsSkillDataStructure.SkillTool>>();

        for (Id skillId : skillIds) toolsBySkillId.put(skillId, new List<AIToolsSkillDataStructure.SkillTool>());

        // [2] Add each tool, as a data source or a workflow action
        for (AISkillTool__c skillTool : [SELECT AISkill__c, IsRequired__c, AIDataSource__c, AIDataSource__r.SourceName__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Description__c, AIDataSource__r.BindingType__c, AIDataSource__r.TargetObject__c, AIDataSource__r.IsActive__c, AIWorkflowAction__c, AIWorkflowAction__r.ActionName__c, AIWorkflowAction__r.DeveloperName__c, AIWorkflowAction__r.Description__c, AIWorkflowAction__r.TargetObject__c, AIWorkflowAction__r.ExecutionType__c, AIWorkflowAction__r.IsActive__c FROM AISkillTool__c WHERE AISkill__c IN :skillIds WITH SYSTEM_MODE ORDER BY StepOrder__c ASC NULLS LAST, Name ASC]) {

            AIToolsSkillDataStructure.SkillTool tool = new AIToolsSkillDataStructure.SkillTool();
            tool.isRequired = skillTool.IsRequired__c == true;

            if (skillTool.AIDataSource__c != null) {

                tool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_DATA_SOURCE;
                tool.recordId = skillTool.AIDataSource__c;
                tool.name = String.isNotBlank(skillTool.AIDataSource__r.SourceName__c) ? skillTool.AIDataSource__r.SourceName__c : skillTool.AIDataSource__r.DeveloperName__c;
                tool.developerName = skillTool.AIDataSource__r.DeveloperName__c;
                tool.description = skillTool.AIDataSource__r.Description__c;
                tool.bindingType = skillTool.AIDataSource__r.BindingType__c;
                tool.targetObject = skillTool.AIDataSource__r.TargetObject__c;
                tool.isActive = skillTool.AIDataSource__r.IsActive__c == true;

            } else {

                tool.kind = AIAssistApplicationConstants.SKILL_TOOL_KIND_ACTION;
                tool.recordId = skillTool.AIWorkflowAction__c;
                tool.name = String.isNotBlank(skillTool.AIWorkflowAction__r.ActionName__c) ? skillTool.AIWorkflowAction__r.ActionName__c : skillTool.AIWorkflowAction__r.DeveloperName__c;
                tool.developerName = skillTool.AIWorkflowAction__r.DeveloperName__c;
                tool.description = skillTool.AIWorkflowAction__r.Description__c;
                tool.targetObject = skillTool.AIWorkflowAction__r.TargetObject__c;
                tool.executionType = skillTool.AIWorkflowAction__r.ExecutionType__c;
                tool.isActive = skillTool.AIWorkflowAction__r.IsActive__c == true;
            }

            toolsBySkillId.get(skillTool.AISkill__c).add(tool);
        }

        return toolsBySkillId;
    }

    // The names of the active agents that have each skill through an active link. Every skill asked for gets a list, empty when no agent has it.
    private static Map<Id, List<String>> getAgentNamesBySkillId(Set<Id> skillIds) {

        // [1] Start with an empty list for each skill
        Map<Id, List<String>> agentNamesBySkillId = new Map<Id, List<String>>();

        for (Id skillId : skillIds) agentNamesBySkillId.put(skillId, new List<String>());

        // [2] Add the name of each agent that has the skill
        for (AIAgentSkill__c agentSkill : [SELECT AISkill__c, AIAgent__r.Name FROM AIAgentSkill__c WHERE AISkill__c IN :skillIds AND IsActive__c = TRUE AND AIAgent__r.IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY AIAgent__r.Name]) {

            agentNamesBySkillId.get(agentSkill.AISkill__c).add(agentSkill.AIAgent__r.Name);
        }

        return agentNamesBySkillId;
    }
}
