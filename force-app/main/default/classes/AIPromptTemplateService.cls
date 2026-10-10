/*
Class Name: AIPromptTemplateService

=================================================================
=================================================================

Description: Works out which of an Agent's Prompt Templates answers a message.

Step 1: Load the Agent's active Prompt Templates
Step 2: Use the template a slash command asked for, if it is still one of them
Step 3: Otherwise use the Agent's default template (its only template counts as the default)
Step 4: Offer the other described templates to the model, so it can switch when the request fits one

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateService {

    // The template to start the turn with, and the others the model may switch to. Always returned, never null.
    public class PromptTemplateChoice {

        public AIPromptTemplate__c promptTemplate;
        public List<AIPromptTemplate__c> routingTemplates = new List<AIPromptTemplate__c>();
    }

    // The template a message starts with and the ones the model may switch to. A template asked for by a slash command always wins and leaves the model nothing to choose from. Otherwise the default is used, and every other template that has a Developer Name and a Description is offered to the model, because the model can only choose from what is described to it.
    public static PromptTemplateChoice getPromptTemplateChoice(Id agentId, Id requestedPromptTemplateId) {

        // [1] Start with no template and nothing to choose from
        PromptTemplateChoice choice = new PromptTemplateChoice();

        // [2] Nothing to find without an agent
        if (agentId == null) return choice;

        // [3] Load the agent's active templates
        List<AIPromptTemplate__c> activeTemplates = getActiveTemplates(agentId);

        // [4] Use the template that was asked for when it is still active on this agent
        for (AIPromptTemplate__c activeTemplate : activeTemplates) {

            if (requestedPromptTemplateId != null && activeTemplate.Id == requestedPromptTemplateId) {

                choice.promptTemplate = activeTemplate;
                return choice;
            }
        }

        // [5] Otherwise start with the default, which may be nothing when several templates are active and none is the default
        choice.promptTemplate = findDefaultTemplate(activeTemplates);

        // [6] Offer the model every other template it can tell apart and understand
        for (AIPromptTemplate__c activeTemplate : activeTemplates) {

            if (choice.promptTemplate != null && activeTemplate.Id == choice.promptTemplate.Id) continue;
            if (String.isBlank(activeTemplate.DeveloperName__c) || String.isBlank(activeTemplate.Description__c)) continue;

            choice.routingTemplates.add(activeTemplate);
        }

        return choice;
    }

    // The active template of the agent with that Developer Name, or null. A slash command names its template this way.
    public static AIPromptTemplate__c findActiveTemplate(Id agentId, String developerName) {

        // [1] Nothing to find without an agent and a name
        if (agentId == null || String.isBlank(developerName)) return null;

        // [2] Query the template, ignoring the user's access
        List<AIPromptTemplate__c> templates = [SELECT Id, Name, DeveloperName__c, Description__c, IsDefault__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c, MaxResponseLength__c, Version__c FROM AIPromptTemplate__c WHERE AIAgent__c = :agentId AND DeveloperName__c = :developerName AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 1];

        return templates.isEmpty() ? null : templates[0];
    }

    // Gets the agent's active templates, ignoring the user's access. Capped, so an agent with hundreds of templates cannot bloat every request.
    @TestVisible
    private static List<AIPromptTemplate__c> getActiveTemplates(Id agentId) {

        // [1] Query the active templates, the default first and then by name so the order is stable
        return [SELECT Id, Name, DeveloperName__c, Description__c, IsDefault__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c, MaxResponseLength__c, Version__c FROM AIPromptTemplate__c WHERE AIAgent__c = :agentId AND IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY IsDefault__c DESC, Name, Id LIMIT :AIAssistApplicationConstants.MAX_TOOLS_PER_KIND];
    }

    // The template ticked as the default, else the only active template, else null.
    @TestVisible
    private static AIPromptTemplate__c findDefaultTemplate(List<AIPromptTemplate__c> activeTemplates) {

        // [1] Use the one ticked as the default
        for (AIPromptTemplate__c activeTemplate : activeTemplates) {

            if (activeTemplate.IsDefault__c == true) return activeTemplate;
        }

        // [2] An agent with a single template needs no default ticked, which is how every agent worked before it could have several
        return activeTemplates.size() == 1 ? activeTemplates[0] : null;
    }
}
