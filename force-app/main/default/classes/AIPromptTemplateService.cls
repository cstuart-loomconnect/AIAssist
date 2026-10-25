/*
Class Name: AIPromptTemplateService

=================================================================
=================================================================

Description: Works out which prompt template answers a message and splits a template into the sections the model receives.

Step 1: Use the template a slash command asked for, if it is still active
Step 2: Otherwise use the template on the agent, if it is active
Step 3: Otherwise use the default (fallback) template, which may be nothing
Step 4: Split a template into its sections, in the order the model receives them

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplateService {

    // The template to answer the turn with. Always returned, never null. routingTemplates is always empty now that templates are shared between agents, so the model has nothing to switch to.
    public class PromptTemplateChoice {

        public AIPromptTemplate__c promptTemplate;
        public List<AIPromptTemplate__c> routingTemplates = new List<AIPromptTemplate__c>();
    }

    // One section of the system prompt: a heading and the text under it.
    public class PromptSection {

        public String heading;
        public String text;
    }

    // The template a message answers with. A template asked for by a slash command wins, then the agent's own template, then the default. A template that is inactive is passed over, so archiving a template never leaves an agent with a retired prompt.
    public static PromptTemplateChoice getPromptTemplateChoice(Id agentId, Id requestedPromptTemplateId) {

        // [1] Start with no template
        PromptTemplateChoice choice = new PromptTemplateChoice();

        // [2] Nothing to find without an agent
        if (agentId == null) return choice;

        // [3] Load every active template that could answer: the one asked for, the agent's own and the default
        Id agentTemplateId = getAgentTemplateId(agentId);
        List<AIPromptTemplate__c> candidates = getCandidateTemplates(requestedPromptTemplateId, agentTemplateId);

        // [4] Take the first of them in the order: asked for, the agent's own, the default
        choice.promptTemplate = findTemplateById(candidates, requestedPromptTemplateId);
        if (choice.promptTemplate == null) choice.promptTemplate = findTemplateById(candidates, agentTemplateId);
        if (choice.promptTemplate == null) choice.promptTemplate = findDefaultTemplate(candidates);

        return choice;
    }

    // The active template with that Developer Name, or null. A slash command names its template this way.
    public static AIPromptTemplate__c findActiveTemplate(String developerName) {

        // [1] Nothing to find without a name
        if (String.isBlank(developerName)) return null;

        // [2] Query the template, ignoring the user's access
        List<AIPromptTemplate__c> templates = [SELECT Id, Name, DeveloperName__c, Description__c, IsDefault__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c, MaxResponseLength__c, Version__c FROM AIPromptTemplate__c WHERE DeveloperName__c = :developerName AND IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 1];

        return templates.isEmpty() ? null : templates[0];
    }

    // The sections of the system prompt in the order the model receives them: the agent's persona, then the template's Context, Tone, Instructions, Never and Response length. A section with no text is left out. The AI Prompt Templates tab shows these same sections, so what an administrator previews is what the model gets.
    public static List<PromptSection> getPromptSections(String persona, AIPromptTemplate__c promptTemplate) {

        // [1] Start with no sections
        List<PromptSection> sections = new List<PromptSection>();

        // [2] Add the agent's persona
        addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_PERSONA, persona);

        // [3] Nothing more to add without a template
        if (promptTemplate == null) return sections;

        // [4] Add the template's wording
        addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_CONTEXT, promptTemplate.AISystemContext__c);
        addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_TONE, promptTemplate.AITone__c);
        addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_INSTRUCTIONS, promptTemplate.AIPrompt__c);
        addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_NEVER, promptTemplate.AIExclusionRules__c);

        // [5] Add the length limit as a sentence, when there is one
        if (promptTemplate.MaxResponseLength__c != null && promptTemplate.MaxResponseLength__c > 0) {

            addSection(sections, AIAssistApplicationConstants.PROMPT_SECTION_RESPONSE_LENGTH, String.format(AIAssistApplicationConstants.PROMPT_SECTION_RESPONSE_LENGTH_TEXT, new List<String>{String.valueOf(promptTemplate.MaxResponseLength__c.intValue())}));
        }

        return sections;
    }

    // Gets the template on the agent, which may be nothing.
    private static Id getAgentTemplateId(Id agentId) {

        // [1] Query the agent, ignoring the user's access
        List<AIAgent__c> agents = [SELECT AIPromptTemplate__c FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];

        return agents.isEmpty() ? null : agents[0].AIPromptTemplate__c;
    }

    // Gets the active templates among the one asked for, the agent's own and the default, ignoring the user's access.
    @TestVisible
    private static List<AIPromptTemplate__c> getCandidateTemplates(Id requestedPromptTemplateId, Id agentTemplateId) {

        // [1] Collect the Ids to look for
        Set<Id> wantedIds = new Set<Id>();

        if (requestedPromptTemplateId != null) wantedIds.add(requestedPromptTemplateId);
        if (agentTemplateId != null) wantedIds.add(agentTemplateId);

        // [2] Query the active templates that are wanted or are the default
        return [SELECT Id, Name, DeveloperName__c, Description__c, IsDefault__c, AISystemContext__c, AIPrompt__c, AITone__c, AIExclusionRules__c, MaxResponseLength__c, Version__c FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND (Id IN :wantedIds OR IsDefault__c = TRUE) WITH SYSTEM_MODE];
    }

    // The template with that Id, or null.
    private static AIPromptTemplate__c findTemplateById(List<AIPromptTemplate__c> templates, Id templateId) {

        // [1] Nothing to find without an Id
        if (templateId == null) return null;

        // [2] Look through the templates
        for (AIPromptTemplate__c template : templates) {

            if (template.Id == templateId) return template;
        }

        return null;
    }

    // The template ticked as the default, or null.
    private static AIPromptTemplate__c findDefaultTemplate(List<AIPromptTemplate__c> templates) {

        // [1] Look for the one ticked as the default
        for (AIPromptTemplate__c template : templates) {

            if (template.IsDefault__c == true) return template;
        }

        return null;
    }

    // Adds a section when it has text.
    private static void addSection(List<PromptSection> sections, String heading, String text) {

        // [1] A section with no text is left out
        if (String.isBlank(text)) return;

        // [2] Add it
        PromptSection section = new PromptSection();
        section.heading = heading;
        section.text = text;
        sections.add(section);
    }
}
