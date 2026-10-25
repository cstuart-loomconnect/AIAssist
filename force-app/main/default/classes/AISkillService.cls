/*
Class Name: AISkillService

=================================================================
=================================================================

Description: Loads the AI Skills an agent may use for a turn, each with its active data sources and workflow actions, and says whether a data source or workflow action reaches an agent through one of its skills.

Step 1: Load the agent's active skills that fit the record the conversation is open on
Step 2: Load the active tools of those skills, in their order
Step 3: Answer whether a data source or workflow action is given to an agent through an active skill

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISkillService {

    // One skill with the tools it brings when the model picks it.
    public class SkillBundle {

        public AISkill__c skill;
        public List<AIDataSource__c> dataSources = new List<AIDataSource__c>();
        public List<AIWorkflowAction__c> workflowActions = new List<AIWorkflowAction__c>();
    }

    // Gets the agent's active skills that fit the record the conversation is open on. A bound skill is only offered on a record of its object; an unbound skill is offered anywhere. Ignores the user's access, because the agent is what was granted the skill.
    public static List<SkillBundle> getAssignedSkills(Id agentId, String relatedObjectApiName) {

        // [1] Nothing is assigned without an agent
        List<SkillBundle> skillBundles = new List<SkillBundle>();

        if (agentId == null) return skillBundles;

        // [2] Query the active skills given to the agent, capped so an agent with many skills cannot bloat every request
        List<AISkill__c> skills = [SELECT Id, Name, DeveloperName__c, Description__c, Instructions__c, OutputType__c, BoundObjectApiName__c FROM AISkill__c WHERE IsActive__c = TRUE AND Id IN (SELECT AISkill__c FROM AIAgentSkill__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE) WITH SYSTEM_MODE ORDER BY DeveloperName__c LIMIT :AIAssistApplicationConstants.MAX_SKILLS_PER_AGENT];

        // [3] Keep the skills that fit the open record
        return getSkillBundles(skills, relatedObjectApiName);
    }

    // Gets one skill as a bundle with its active tools, whether or not it is active or given to an agent. Used by the skill test on the AI Tools tab. Returns null when the skill does not exist.
    public static SkillBundle getSkillBundle(Id skillId) {

        // [1] Nothing to find without an Id
        if (skillId == null) return null;

        // [2] Query the skill
        List<AISkill__c> skills = [SELECT Id, Name, DeveloperName__c, Description__c, Instructions__c, OutputType__c, BoundObjectApiName__c FROM AISkill__c WHERE Id = :skillId WITH SYSTEM_MODE LIMIT 1];

        // [3] Load its tools, keeping it whatever record is open
        List<SkillBundle> skillBundles = getSkillBundles(skills, null);

        return skillBundles.isEmpty() ? null : skillBundles[0];
    }

    // Whether the data source reaches the agent through one of its active skills. The dispatcher asks this when the data source is not linked to the agent directly.
    public static Boolean isDataSourceGrantedThroughSkill(Id dataSourceId, Id agentId) {

        // [1] Nothing is granted without both Ids
        if (dataSourceId == null || agentId == null) return false;

        // [2] Look for an active skill holding the data source that the agent has
        return ![SELECT Id FROM AISkillTool__c WHERE AIDataSource__c = :dataSourceId AND AISkill__r.IsActive__c = TRUE AND AISkill__c IN (SELECT AISkill__c FROM AIAgentSkill__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE) WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    // Whether the workflow action reaches the agent through one of its active skills. The dispatcher asks this when the action is not linked to the agent directly.
    public static Boolean isWorkflowActionGrantedThroughSkill(Id workflowActionId, Id agentId) {

        // [1] Nothing is granted without both Ids
        if (workflowActionId == null || agentId == null) return false;

        // [2] Look for an active skill holding the action that the agent has
        return ![SELECT Id FROM AISkillTool__c WHERE AIWorkflowAction__c = :workflowActionId AND AISkill__r.IsActive__c = TRUE AND AISkill__c IN (SELECT AISkill__c FROM AIAgentSkill__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE) WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    // Builds a bundle for each skill that fits the open record, with its active data sources and workflow actions in order. A blank relatedObjectApiName with a bound skill drops the skill, except when called for one skill by Id.
    private static List<SkillBundle> getSkillBundles(List<AISkill__c> skills, String relatedObjectApiName) {

        // [1] Keep the skills that fit the open record. A bound skill needs a record of its own object.
        Map<Id, SkillBundle> skillBundleBySkillId = new Map<Id, SkillBundle>();
        Boolean isForOneSkill = skills.size() == 1 && relatedObjectApiName == null;

        for (AISkill__c skill : skills) {

            Boolean fitsOpenRecord = isForOneSkill || String.isBlank(skill.BoundObjectApiName__c) || (String.isNotBlank(relatedObjectApiName) && skill.BoundObjectApiName__c.equalsIgnoreCase(relatedObjectApiName));

            if (!fitsOpenRecord) continue;

            SkillBundle skillBundle = new SkillBundle();
            skillBundle.skill = skill;
            skillBundleBySkillId.put(skill.Id, skillBundle);
        }

        if (skillBundleBySkillId.isEmpty()) return new List<SkillBundle>();

        // [2] Add each active tool to its skill in order. Inactive data sources and actions are left out, so the model is never offered a tool that would be refused.
        Set<Id> skillIds = skillBundleBySkillId.keySet();

        for (AISkillTool__c skillTool : [SELECT AISkill__c, AIDataSource__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.Description__c, AIDataSource__r.OutputDescription__c, AIDataSource__r.InputSchema__c, AIDataSource__r.MaxRows__c, AIDataSource__r.TargetObject__c, AIDataSource__r.IsActive__c, AIWorkflowAction__c, AIWorkflowAction__r.DeveloperName__c, AIWorkflowAction__r.Description__c, AIWorkflowAction__r.OutputDescription__c, AIWorkflowAction__r.InputSchema__c, AIWorkflowAction__r.IsActive__c FROM AISkillTool__c WHERE AISkill__c IN :skillIds WITH SYSTEM_MODE ORDER BY StepOrder__c ASC NULLS LAST, Name ASC]) {

            SkillBundle skillBundle = skillBundleBySkillId.get(skillTool.AISkill__c);

            if (skillTool.AIDataSource__c != null && skillTool.AIDataSource__r.IsActive__c == true) skillBundle.dataSources.add(skillTool.AIDataSource__r);
            if (skillTool.AIWorkflowAction__c != null && skillTool.AIWorkflowAction__r.IsActive__c == true) skillBundle.workflowActions.add(skillTool.AIWorkflowAction__r);
        }

        // [3] Return the bundles in skill order
        return skillBundleBySkillId.values();
    }
}
