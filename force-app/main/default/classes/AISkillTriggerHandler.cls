/*
Class Name: AISkillTriggerHandler

=================================================================
=================================================================

Description: Keeps AI Skills safe to offer to an agent: the When To Use It text is the right length, an active skill has tools that match its instructions, and the API name the model picks it by does not change under an agent.

Step 1: Refuse a When To Use It text shorter than 40 or longer than 400 characters
Step 2: Refuse a change of API name while an agent has the skill
Step 3: Refuse to activate a skill with no tools, an @ name in its instructions that is not one of its tools, or bound data sources on more than one object

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AISkillTriggerHandler {

    public class AISkillTriggerHandlerException extends Exception {}

    private static final Integer DESCRIPTION_MIN_LENGTH = 40;
    private static final Integer DESCRIPTION_MAX_LENGTH = 400;
    private static final Pattern TOOL_MENTION_PATTERN = Pattern.compile('@([A-Za-z][A-Za-z0-9_]*)');

    @TestVisible
    private static Boolean isTestCustomExceptionThrown = false;

    // Runs before a skill is inserted or updated. oldSkillsById is null on insert.
    public static void handleBeforeSave(List<AISkill__c> newSkills, Map<Id, AISkill__c> oldSkillsById) {

        try {

            // [1] Nothing to check - no skills
            if (newSkills == null || newSkills.isEmpty()) return;

            // [2] Throw the test exception when a test asks for it
            if (isTestCustomExceptionThrown) throw new AISkillTriggerHandlerException('Test exception for AISkillTriggerHandler.handleBeforeSave');

            // [3] Check the length of the When To Use It text, and sort out the skills being renamed and the skills being activated or having their instructions changed while active
            Set<Id> renamedSkillIds = new Set<Id>();
            List<AISkill__c> skillsToCheckForActivation = new List<AISkill__c>();

            for (AISkill__c newSkill : newSkills) {

                Integer descriptionLength = newSkill.Description__c == null ? 0 : newSkill.Description__c.trim().length();

                if (descriptionLength < DESCRIPTION_MIN_LENGTH || descriptionLength > DESCRIPTION_MAX_LENGTH) newSkill.Description__c.addError(Label.AI_Error_Skill_Description_Length);

                AISkill__c oldSkill = oldSkillsById == null || newSkill.Id == null ? null : oldSkillsById.get(newSkill.Id);

                if (oldSkill != null && newSkill.DeveloperName__c != oldSkill.DeveloperName__c) renamedSkillIds.add(newSkill.Id);

                Boolean isBecomingActive = newSkill.IsActive__c == true && (oldSkill == null || oldSkill.IsActive__c != true || newSkill.Instructions__c != oldSkill.Instructions__c);

                if (isBecomingActive) skillsToCheckForActivation.add(newSkill);
            }

            // [4] Refuse a new API name for a skill an agent already has, because the model picks the skill by that name
            if (!renamedSkillIds.isEmpty()) {

                Map<Id, AISkill__c> newSkillsById = new Map<Id, AISkill__c>(newSkills);

                for (AIAgentSkill__c agentSkill : [SELECT AISkill__c FROM AIAgentSkill__c WHERE AISkill__c IN :renamedSkillIds WITH SYSTEM_MODE]) {

                    newSkillsById.get(agentSkill.AISkill__c).DeveloperName__c.addError(Label.AI_Error_Skill_Developer_Name_Locked);
                }
            }

            // [5] Stop when no skill is being activated
            if (skillsToCheckForActivation.isEmpty()) return;

            // [6] Load the tools of the skills being activated
            Set<Id> skillIds = new Set<Id>();

            for (AISkill__c skill : skillsToCheckForActivation) {

                if (skill.Id != null) skillIds.add(skill.Id);
            }

            Map<Id, List<AISkillTool__c>> toolsBySkillId = new Map<Id, List<AISkillTool__c>>();

            for (AISkillTool__c skillTool : [SELECT AISkill__c, AIDataSource__r.DeveloperName__c, AIDataSource__r.BindingType__c, AIDataSource__r.TargetObject__c, AIWorkflowAction__r.DeveloperName__c FROM AISkillTool__c WHERE AISkill__c IN :skillIds WITH SYSTEM_MODE]) {

                if (!toolsBySkillId.containsKey(skillTool.AISkill__c)) toolsBySkillId.put(skillTool.AISkill__c, new List<AISkillTool__c>());
                toolsBySkillId.get(skillTool.AISkill__c).add(skillTool);
            }

            // [7] Refuse each skill with no tools, an @ name that is not one of its tools, or bound data sources on more than one object
            for (AISkill__c skill : skillsToCheckForActivation) {

                List<AISkillTool__c> skillTools = skill.Id == null ? null : toolsBySkillId.get(skill.Id);

                if (skillTools == null || skillTools.isEmpty()) {

                    skill.IsActive__c.addError(Label.AI_Error_Skill_No_Tools);
                    continue;
                }

                Set<String> toolNames = new Set<String>();
                Set<String> boundObjectNames = new Set<String>();

                for (AISkillTool__c skillTool : skillTools) {

                    if (skillTool.AIDataSource__r != null) toolNames.add(skillTool.AIDataSource__r.DeveloperName__c.toLowerCase());
                    if (skillTool.AIWorkflowAction__r != null) toolNames.add(skillTool.AIWorkflowAction__r.DeveloperName__c.toLowerCase());
                    if (skillTool.AIDataSource__r != null && skillTool.AIDataSource__r.BindingType__c == 'Bound' && String.isNotBlank(skillTool.AIDataSource__r.TargetObject__c)) boundObjectNames.add(skillTool.AIDataSource__r.TargetObject__c.toLowerCase());
                }

                List<String> unknownToolNames = new List<String>();
                Matcher mentionMatcher = TOOL_MENTION_PATTERN.matcher(skill.Instructions__c == null ? '' : skill.Instructions__c);

                while (mentionMatcher.find()) {

                    String mentionedName = mentionMatcher.group(1);

                    if (!toolNames.contains(mentionedName.toLowerCase()) && !unknownToolNames.contains(mentionedName)) unknownToolNames.add(mentionedName);
                }

                if (!unknownToolNames.isEmpty()) skill.Instructions__c.addError(String.format(Label.AI_Error_Skill_Unknown_Tool, new List<String>{ String.join(unknownToolNames, ', ') }));

                if (boundObjectNames.size() > 1) skill.IsActive__c.addError(Label.AI_Error_Skill_Mixed_Objects);
            }

        } catch (Exception ex) {
            AIPlatformLogManager.logException(ex, 'AISkillTriggerHandler', 'handleBeforeSave');
        }
    }
}
