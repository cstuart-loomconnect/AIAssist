/*
Class Name: AIPromptTemplatesEditorService

=================================================================
=================================================================

Description: Reads, checks, previews and saves the prompt templates that the AI Prompt Templates tab edits.

Step 1: Read the list of templates, one template with every field the editor changes, and the agents that use it
Step 2: Check a template, and show what the model would receive from it
Step 3: Save a template, and work out what a save would change for the publish dialog
Step 4: Archive a template by moving its agents, bring one back, and make one the default
Step 5: Keep the saved test messages and the Better and Worse marks on their replies
Step 6: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptTemplatesEditorService {

    public class AIPromptTemplatesEditorServiceException extends Exception {}

    private static final Pattern DEVELOPER_NAME_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]*$');

    // Every template for the list, by name, with the number of active agents that answer with each.
    public static List<AIPromptTemplatesDataStructure.TemplateRow> getTemplateRows() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the templates
        List<AIPromptTemplate__c> templates = [SELECT Id, Name, DeveloperName__c, IsActive__c, IsDefault__c, Version__c FROM AIPromptTemplate__c WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS];

        // [3] Count the active agents each template answers for, working out which template each agent really uses
        Set<Id> activeTemplateIds = new Set<Id>();
        Id defaultTemplateId;

        for (AIPromptTemplate__c template : templates) {

            if (template.IsActive__c != true) continue;

            activeTemplateIds.add(template.Id);
            if (template.IsDefault__c == true) defaultTemplateId = template.Id;
        }

        Map<Id, Integer> agentCountByTemplateId = new Map<Id, Integer>();

        for (AIAgent__c agent : [SELECT AIPromptTemplate__c FROM AIAgent__c WHERE IsActive__c = TRUE WITH SYSTEM_MODE LIMIT 2000]) {

            Id usedTemplateId = activeTemplateIds.contains(agent.AIPromptTemplate__c) ? agent.AIPromptTemplate__c : defaultTemplateId;

            if (usedTemplateId == null) continue;

            agentCountByTemplateId.put(usedTemplateId, (agentCountByTemplateId.containsKey(usedTemplateId) ? agentCountByTemplateId.get(usedTemplateId) : 0) + 1);
        }

        // [4] Build one row per template
        List<AIPromptTemplatesDataStructure.TemplateRow> rows = new List<AIPromptTemplatesDataStructure.TemplateRow>();

        for (AIPromptTemplate__c template : templates) {

            AIPromptTemplatesDataStructure.TemplateRow row = new AIPromptTemplatesDataStructure.TemplateRow();
            row.templateId = template.Id;
            row.templateName = template.Name;
            row.developerName = template.DeveloperName__c;
            row.isActive = template.IsActive__c == true;
            row.isDefault = template.IsDefault__c == true;
            row.version = template.Version__c;
            row.agentCount = agentCountByTemplateId.containsKey(template.Id) ? agentCountByTemplateId.get(template.Id) : 0;
            rows.add(row);
        }

        return rows;
    }

    // One template with every field the editor changes.
    public static AIPromptTemplatesDataStructure.TemplateDetail getTemplateDetail(Id templateId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read it and build the detail
        return buildDetail(findTemplate(templateId));
    }

    // The merge fields the Insert bar offers.
    public static List<AIPromptTemplatesDataStructure.MergeFieldOption> getMergeFieldOptions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Hand over the list
        return AIPromptMergeFieldService.getMergeFieldOptions();
    }

    // The active agents that have a model, which the Try it tab can run a message as.
    public static List<AIPromptTemplatesDataStructure.AgentOption> getAgentOptions() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Build one option per agent
        List<AIPromptTemplatesDataStructure.AgentOption> options = new List<AIPromptTemplatesDataStructure.AgentOption>();

        for (AIAgent__c agent : [SELECT Id, Name, ObjectApiNames__c FROM AIAgent__c WHERE IsActive__c = TRUE AND AIModelConfiguration__c != NULL WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS]) {

            AIPromptTemplatesDataStructure.AgentOption option = new AIPromptTemplatesDataStructure.AgentOption();
            option.agentId = agent.Id;
            option.agentName = agent.Name;
            option.objectApiName = getFirstObjectApiName(agent);
            options.add(option);
        }

        return options;
    }

    // Checks a template and shows what the model would receive from it. The sections are left out while there are problems.
    public static AIPromptTemplatesDataStructure.PreviewResult getPreview(AIPromptTemplatesDataStructure.TemplateDetail detail, Id agentId, Id recordId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Check the template, and stop at the problems
        AIPromptTemplatesDataStructure.PreviewResult result = new AIPromptTemplatesDataStructure.PreviewResult();
        result.problems = getProblems(detail);

        if (!result.problems.isEmpty()) return result;

        // [3] Work out the values for the merge fields from the agent and the record
        AIAgent__c agent = findAgent(agentId);
        Map<String, String> valueByToken = AIPromptMergeFieldService.buildValues(agent, getFirstObjectApiName(agent), recordId, true);

        // [4] Split the template into the sections the model receives
        List<String> filledTexts = new List<String>();

        for (AIPromptTemplateService.PromptSection promptSection : AIPromptTemplateService.getPromptSections(agent == null ? null : agent.AIAgentPersona__c, buildTemplateFromDetail(detail))) {

            AIPromptTemplatesDataStructure.PreviewSection previewSection = new AIPromptTemplatesDataStructure.PreviewSection();
            previewSection.heading = promptSection.heading;

            // [5] The persona is shown as written, and the template's wording has its merge fields filled
            if (promptSection.heading == AIAssistApplicationConstants.PROMPT_SECTION_PERSONA) previewSection.segments = AIPromptMergeFieldService.buildSegments(promptSection.text, new Map<String, String>());
            else previewSection.segments = AIPromptMergeFieldService.buildSegments(promptSection.text, valueByToken);

            result.sections.add(previewSection);
            filledTexts.add(AIAssistApplicationConstants.PROMPT_SECTION_HEADING_PREFIX + promptSection.heading + '\n' + AIPromptMergeFieldService.getFilledText(promptSection.text, valueByToken));
        }

        // [6] Estimate the tokens the template adds to every message
        result.estimatedTokens = AIConversationMessageService.estimateTokenCount(String.join(filledTexts, '\n')).intValue();

        return result;
    }

    // What a save would do, for the publish dialog: the version it makes, the sections that change, the agents it reaches and how the saved test messages did.
    public static AIPromptTemplatesDataStructure.PublishImpact getPublishImpact(AIPromptTemplatesDataStructure.TemplateDetail detail) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] A template that is not saved yet reaches nobody
        AIPromptTemplatesDataStructure.PublishImpact impact = new AIPromptTemplatesDataStructure.PublishImpact();
        impact.isNew = detail == null || detail.templateId == null;
        impact.testMessageCount = 0;
        impact.testPassedCount = 0;

        if (impact.isNew) return impact;

        // [3] Compare the edited wording with the saved wording
        AIPromptTemplate__c savedTemplate = findTemplate(detail.templateId);
        impact.currentVersion = savedTemplate.Version__c;
        impact.changedSections = getChangedSections(savedTemplate, detail);
        impact.nextVersion = impact.changedSections.isEmpty() ? savedTemplate.Version__c : (savedTemplate.Version__c == null ? 1 : savedTemplate.Version__c) + 1;

        // [4] List the agents the change reaches
        impact.agentUses = getAgentUsesOfTemplate(savedTemplate);

        // [5] Count the saved test messages and how many passed on their last run
        for (AIPromptTestMessage__c testMessage : [SELECT LastRunStatus__c, EditedVerdict__c FROM AIPromptTestMessage__c WHERE AIPromptTemplate__c = :savedTemplate.Id WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.PROMPT_TEST_MESSAGES_MAX_PER_TEMPLATE]) {

            impact.testMessageCount++;
            if (testMessage.LastRunStatus__c == AIAssistApplicationConstants.PROMPT_TEST_STATUS_PASSED && testMessage.EditedVerdict__c != AIAssistApplicationConstants.PROMPT_VERDICT_WORSE) impact.testPassedCount++;
        }

        return impact;
    }

    // Saves a template: creates it active when it is new, and otherwise changes the wording the agents already use. Nothing is saved while there are problems; they come back instead.
    public static AIPromptTemplatesDataStructure.SaveResult saveTemplate(AIPromptTemplatesDataStructure.TemplateDetail detail) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Stop at the problems
        AIPromptTemplatesDataStructure.SaveResult result = new AIPromptTemplatesDataStructure.SaveResult();
        result.problems = getProblems(detail);

        if (!result.problems.isEmpty()) return result;

        // [3] Copy the edited fields onto a new template, or onto the saved one
        AIPromptTemplate__c template = detail.templateId == null ? new AIPromptTemplate__c(IsActive__c = true, IsDefault__c = false) : findTemplate(detail.templateId);
        template.Name = detail.templateName.trim();
        template.DeveloperName__c = detail.developerName.trim();
        template.MaxResponseLength__c = detail.maxResponseLength == null ? null : detail.maxResponseLength.setScale(0);
        template.AISystemContext__c = getTextOrNull(detail.systemContext);
        template.AITone__c = getTextOrNull(detail.tone);
        template.AIPrompt__c = getTextOrNull(detail.prompt);
        template.AIExclusionRules__c = getTextOrNull(detail.exclusionRules);

        // [4] Save it, which raises the version when the wording changed
        Database.upsert(template, AccessLevel.SYSTEM_MODE);

        // [5] Hand back the saved template as the editor should now show it
        result.isSaved = true;
        result.detail = buildDetail(findTemplate(template.Id));

        return result;
    }

    // The agents that answer with a template: the ones that have it, and, when it is the default, the ones that have none of their own.
    public static List<AIPromptTemplatesDataStructure.AgentUse> getAgentUses(Id templateId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the template and list its agents
        return getAgentUsesOfTemplate(findTemplate(templateId));
    }

    // What the archive dialog needs: whether the template is the default, the agents that have it, and the templates they can move to.
    public static AIPromptTemplatesDataStructure.ArchiveOptions getArchiveOptions(Id templateId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the template, and the agents that have it set on them
        AIPromptTemplate__c template = findTemplate(templateId);
        AIPromptTemplatesDataStructure.ArchiveOptions options = new AIPromptTemplatesDataStructure.ArchiveOptions();
        options.isDefault = template.IsDefault__c == true;

        for (AIPromptTemplatesDataStructure.AgentUse agentUse : getAgentUsesOfTemplate(template)) {

            if (agentUse.usesFallback != true) options.agentUses.add(agentUse);
        }

        // [3] Offer the other active templates, and name the default they would fall back to
        for (AIPromptTemplate__c otherTemplate : [SELECT Id, Name, IsDefault__c FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND Id != :template.Id WITH SYSTEM_MODE ORDER BY Name LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS]) {

            AIPromptTemplatesDataStructure.TemplateOption option = new AIPromptTemplatesDataStructure.TemplateOption();
            option.templateId = otherTemplate.Id;
            option.label = otherTemplate.Name;
            option.isDefault = otherTemplate.IsDefault__c == true;
            options.templateOptions.add(option);

            if (option.isDefault) options.defaultName = otherTemplate.Name;
        }

        return options;
    }

    // Archives a template. Each agent that has it is moved first, to the template chosen for it or to the default when none was, so no agent is left on a template that is switched off. The default template cannot be archived.
    public static void archiveTemplate(Id templateId, List<AIPromptTemplatesDataStructure.ArchiveMove> moves) {

        // [1] Refuse a user who may not use the tab, and the default template
        AIAssistSettingsEditorService.requireManager();

        AIPromptTemplate__c template = findTemplate(templateId);

        if (template.IsDefault__c == true) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Default_Cannot_Archive);

        // [2] Note where each agent was sent, and check that place is another active template
        Map<Id, Id> newTemplateIdByAgentId = new Map<Id, Id>();
        Set<Id> activeTemplateIds = new Map<Id, AIPromptTemplate__c>([SELECT Id FROM AIPromptTemplate__c WHERE IsActive__c = TRUE AND Id != :templateId WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS]).keySet();

        for (AIPromptTemplatesDataStructure.ArchiveMove move : moves == null ? new List<AIPromptTemplatesDataStructure.ArchiveMove>() : moves) {

            if (move.newTemplateId != null && !activeTemplateIds.contains(move.newTemplateId)) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Move_Target_Invalid);

            newTemplateIdByAgentId.put(move.agentId, move.newTemplateId);
        }

        // [3] Move every agent that has the template, including inactive ones, so none keeps a reference to an archived template
        List<AIAgent__c> agentsToMove = [SELECT Id FROM AIAgent__c WHERE AIPromptTemplate__c = :templateId WITH SYSTEM_MODE LIMIT 2000];

        for (AIAgent__c agent : agentsToMove) {

            agent.AIPromptTemplate__c = newTemplateIdByAgentId.get(agent.Id);
        }

        Database.update(agentsToMove, AccessLevel.SYSTEM_MODE);

        // [4] Switch the template off
        template.IsActive__c = false;
        Database.update(template, AccessLevel.SYSTEM_MODE);
    }

    // Brings an archived template back.
    public static void activateTemplate(Id templateId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Refuse a template with no instructions, which the object would refuse too
        AIPromptTemplate__c template = findTemplate(templateId);

        if (String.isBlank(template.AIPrompt__c)) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Instructions_Required);

        // [3] Switch it on
        template.IsActive__c = true;
        Database.update(template, AccessLevel.SYSTEM_MODE);
    }

    // Makes a template the default, and takes that away from the one that was.
    public static void setDefaultTemplate(Id templateId) {

        // [1] Refuse a user who may not use the tab, and a template that is switched off
        AIAssistSettingsEditorService.requireManager();

        AIPromptTemplate__c template = findTemplate(templateId);

        if (template.IsActive__c != true) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Default_Must_Be_Active);

        // [2] Move the default in one save: untick the old one and tick the new one
        List<AIPromptTemplate__c> templatesToSave = [SELECT Id, IsDefault__c FROM AIPromptTemplate__c WHERE IsDefault__c = TRUE AND Id != :templateId WITH SYSTEM_MODE LIMIT :AIAssistApplicationConstants.PROMPT_TEMPLATE_LIST_MAX_RESULTS];

        for (AIPromptTemplate__c oldDefault : templatesToSave) {

            oldDefault.IsDefault__c = false;
        }

        template.IsDefault__c = true;
        templatesToSave.add(template);
        Database.update(templatesToSave, AccessLevel.SYSTEM_MODE);
    }

    // The saved test messages of a template, oldest first.
    public static List<AIPromptTemplatesDataStructure.TestMessage> getTestMessages(Id templateId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read them and build one entry each
        List<AIPromptTemplatesDataStructure.TestMessage> testMessages = new List<AIPromptTemplatesDataStructure.TestMessage>();

        for (AIPromptTestMessage__c testMessage : [SELECT Id, MessageBody__c, LastRunOn__c, LastRunStatus__c, LastSavedReply__c, LastEditedReply__c, SavedVerdict__c, EditedVerdict__c FROM AIPromptTestMessage__c WHERE AIPromptTemplate__c = :templateId WITH SYSTEM_MODE ORDER BY CreatedDate, Id LIMIT :AIAssistApplicationConstants.PROMPT_TEST_MESSAGES_MAX_PER_TEMPLATE]) {

            testMessages.add(buildTestMessage(testMessage));
        }

        return testMessages;
    }

    // Saves a message against a template so it can be run again after each change.
    public static AIPromptTemplatesDataStructure.TestMessage saveTestMessage(Id templateId, String messageBody) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Check the message and the template
        if (templateId == null) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Save_First);
        if (String.isBlank(messageBody)) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Message_Required);
        if (messageBody.length() > AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Message_Too_Long);

        findTemplate(templateId);

        // [3] Refuse more than the template may hold
        Integer savedCount = [SELECT COUNT() FROM AIPromptTestMessage__c WHERE AIPromptTemplate__c = :templateId WITH SYSTEM_MODE];

        if (savedCount >= AIAssistApplicationConstants.PROMPT_TEST_MESSAGES_MAX_PER_TEMPLATE) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Too_Many_Messages);

        // [4] Save it
        AIPromptTestMessage__c testMessage = new AIPromptTestMessage__c(AIPromptTemplate__c = templateId, MessageBody__c = messageBody.trim());
        Database.insert(testMessage, AccessLevel.SYSTEM_MODE);

        return buildTestMessage(testMessage);
    }

    // Deletes a saved test message.
    public static void deleteTestMessage(Id testMessageId) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Delete it
        delete findTestMessage(testMessageId);
    }

    // Marks the reply of the saved or the edited wording as Better or Worse.
    public static AIPromptTemplatesDataStructure.TestMessage setVerdict(Id testMessageId, String side, String verdict) {

        // [1] Refuse a user who may not use the tab, and a mark that is not Better or Worse
        AIAssistSettingsEditorService.requireManager();

        Boolean isMarkValid = verdict == AIAssistApplicationConstants.PROMPT_VERDICT_BETTER || verdict == AIAssistApplicationConstants.PROMPT_VERDICT_WORSE;
        Boolean isSideValid = side == AIAssistApplicationConstants.PROMPT_VERDICT_SIDE_SAVED || side == AIAssistApplicationConstants.PROMPT_VERDICT_SIDE_EDITED;

        if (!isMarkValid || !isSideValid) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Verdict);

        // [2] Save the mark on the side it was given to
        AIPromptTestMessage__c testMessage = findTestMessage(testMessageId);

        if (side == AIAssistApplicationConstants.PROMPT_VERDICT_SIDE_SAVED) testMessage.SavedVerdict__c = verdict;
        else testMessage.EditedVerdict__c = verdict;

        Database.update(testMessage, AccessLevel.SYSTEM_MODE);

        return buildTestMessage(testMessage);
    }

    // The unsaved template the editor holds, as a record that is never saved. The preview and Try it read their wording from it.
    public static AIPromptTemplate__c buildTemplateFromDetail(AIPromptTemplatesDataStructure.TemplateDetail detail) {

        // [1] Copy the wording
        AIPromptTemplate__c template = new AIPromptTemplate__c();

        if (detail == null) return template;

        template.Name = detail.templateName;
        template.DeveloperName__c = detail.developerName;
        template.MaxResponseLength__c = detail.maxResponseLength;
        template.AISystemContext__c = detail.systemContext;
        template.AITone__c = detail.tone;
        template.AIPrompt__c = detail.prompt;
        template.AIExclusionRules__c = detail.exclusionRules;
        template.Version__c = detail.version;

        return template;
    }

    // The first object an agent works on, or blank when it works on any.
    public static String getFirstObjectApiName(AIAgent__c agent) {

        // [1] A general agent has no object
        if (agent == null || String.isBlank(agent.ObjectApiNames__c)) return null;

        // [2] Take the first name in the list
        return agent.ObjectApiNames__c.split(',')[0].trim();
    }

    // The agent with the fields the preview and Try it need, or null when none was picked or it is gone.
    public static AIAgent__c findAgent(Id agentId) {

        // [1] Nothing to find without an Id
        if (agentId == null) return null;

        // [2] Query the agent
        List<AIAgent__c> agents = [SELECT Id, Name, DeveloperName__c, AIAgentPersona__c, ObjectApiNames__c, AIModelConfiguration__c, TokenTrackingMethod__c, MaxToolCallingIterations__c FROM AIAgent__c WHERE Id = :agentId WITH SYSTEM_MODE LIMIT 1];

        return agents.isEmpty() ? null : agents[0];
    }

    // The saved test message with that Id, or the refusal that it is gone.
    public static AIPromptTestMessage__c findTestMessage(Id testMessageId) {

        // [1] Query it
        List<AIPromptTestMessage__c> testMessages = [SELECT Id, AIPromptTemplate__c, MessageBody__c, LastRunOn__c, LastRunStatus__c, LastSavedReply__c, LastEditedReply__c, SavedVerdict__c, EditedVerdict__c FROM AIPromptTestMessage__c WHERE Id = :testMessageId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (testMessages.isEmpty()) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Not_Found);

        return testMessages[0];
    }

    // Builds the entry the Try it tab shows for a saved test message.
    public static AIPromptTemplatesDataStructure.TestMessage buildTestMessage(AIPromptTestMessage__c testMessage) {

        // [1] Fill the entry
        AIPromptTemplatesDataStructure.TestMessage entry = new AIPromptTemplatesDataStructure.TestMessage();
        entry.testMessageId = testMessage.Id;
        entry.messageBody = testMessage.MessageBody__c;
        entry.lastRunOn = testMessage.LastRunOn__c;
        entry.lastRunStatus = testMessage.LastRunStatus__c;
        entry.lastSavedReply = testMessage.LastSavedReply__c;
        entry.lastEditedReply = testMessage.LastEditedReply__c;
        entry.savedVerdict = testMessage.SavedVerdict__c;
        entry.editedVerdict = testMessage.EditedVerdict__c;

        return entry;
    }

    // Everything wrong with a template, one entry per problem, in the order the editor shows its fields.
    @TestVisible
    private static List<AIPromptTemplatesDataStructure.FieldProblem> getProblems(AIPromptTemplatesDataStructure.TemplateDetail detail) {

        // [1] Start with none
        List<AIPromptTemplatesDataStructure.FieldProblem> problems = new List<AIPromptTemplatesDataStructure.FieldProblem>();

        if (detail == null) return problems;

        // [2] Check the name and the API name
        if (String.isBlank(detail.templateName)) problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_NAME, Label.AI_Prompts_Error_Name_Required));

        if (String.isBlank(detail.developerName)) {

            problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_DEVELOPER_NAME, Label.AI_Prompts_Error_Api_Name_Required));

        } else if (!DEVELOPER_NAME_PATTERN.matcher(detail.developerName.trim()).matches()) {

            problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_DEVELOPER_NAME, Label.AI_Prompts_Error_Api_Name_Format));

        } else if (isDeveloperNameTaken(detail.developerName.trim(), detail.templateId)) {

            problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_DEVELOPER_NAME, Label.AI_Prompts_Error_Api_Name_Taken));
        }

        // [3] Check the response length
        if (detail.maxResponseLength != null && detail.maxResponseLength <= 0) problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_MAX_RESPONSE_LENGTH, Label.AI_Prompts_Error_Max_Length));

        // [4] Check the merge fields and the instructions of each section, in the order the editor shows them
        addMergeFieldProblem(problems, AIAssistApplicationConstants.PROMPT_FIELD_SYSTEM_CONTEXT, detail.systemContext);
        addMergeFieldProblem(problems, AIAssistApplicationConstants.PROMPT_FIELD_TONE, detail.tone);

        if (String.isBlank(detail.prompt)) problems.add(buildProblem(AIAssistApplicationConstants.PROMPT_FIELD_PROMPT, Label.AI_Prompts_Error_Instructions_Required));
        else addMergeFieldProblem(problems, AIAssistApplicationConstants.PROMPT_FIELD_PROMPT, detail.prompt);

        addMergeFieldProblem(problems, AIAssistApplicationConstants.PROMPT_FIELD_EXCLUSION_RULES, detail.exclusionRules);

        return problems;
    }

    // Adds a problem naming the merge fields in a section that are not on the list.
    private static void addMergeFieldProblem(List<AIPromptTemplatesDataStructure.FieldProblem> problems, String fieldName, String text) {

        // [1] Find the merge fields that are not known
        List<String> unknownTokens = AIPromptMergeFieldService.getUnknownTokens(text);

        if (unknownTokens.isEmpty()) return;

        // [2] Name them in one problem
        problems.add(buildProblem(fieldName, String.format(Label.AI_Prompts_Error_Unknown_Merge_Field, new List<String>{String.join(unknownTokens, ', ')})));
    }

    // Whether another template already has this API name.
    private static Boolean isDeveloperNameTaken(String developerName, Id templateId) {

        // [1] Look for another template with the name
        return ![SELECT Id FROM AIPromptTemplate__c WHERE DeveloperName__c = :developerName AND Id != :templateId WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    // The headings of the sections whose wording the edit changes.
    private static List<String> getChangedSections(AIPromptTemplate__c savedTemplate, AIPromptTemplatesDataStructure.TemplateDetail detail) {

        // [1] Compare each section with the saved one, treating blank and empty as the same
        List<String> changedSections = new List<String>();

        if (getTextOrNull(savedTemplate.AISystemContext__c) != getTextOrNull(detail.systemContext)) changedSections.add(AIAssistApplicationConstants.PROMPT_SECTION_CONTEXT);
        if (getTextOrNull(savedTemplate.AITone__c) != getTextOrNull(detail.tone)) changedSections.add(AIAssistApplicationConstants.PROMPT_SECTION_TONE);
        if (getTextOrNull(savedTemplate.AIPrompt__c) != getTextOrNull(detail.prompt)) changedSections.add(AIAssistApplicationConstants.PROMPT_SECTION_INSTRUCTIONS);
        if (getTextOrNull(savedTemplate.AIExclusionRules__c) != getTextOrNull(detail.exclusionRules)) changedSections.add(AIAssistApplicationConstants.PROMPT_SECTION_NEVER);
        if (savedTemplate.MaxResponseLength__c != detail.maxResponseLength) changedSections.add(AIAssistApplicationConstants.PROMPT_SECTION_RESPONSE_LENGTH);

        return changedSections;
    }

    // The agents that answer with a template, with how many users and open conversations each has.
    private static List<AIPromptTemplatesDataStructure.AgentUse> getAgentUsesOfTemplate(AIPromptTemplate__c template) {

        // [1] Pick the agents that have the template, and, for the default, the active agents with no usable template of their own
        List<AIPromptTemplatesDataStructure.AgentUse> agentUses = new List<AIPromptTemplatesDataStructure.AgentUse>();
        Map<Id, AIPromptTemplatesDataStructure.AgentUse> agentUseByAgentId = new Map<Id, AIPromptTemplatesDataStructure.AgentUse>();
        Boolean isActiveDefault = template.IsDefault__c == true && template.IsActive__c == true;

        for (AIAgent__c agent : [SELECT Id, Name, IsActive__c, AIPromptTemplate__c, AIPromptTemplate__r.IsActive__c FROM AIAgent__c WITH SYSTEM_MODE ORDER BY Name LIMIT 2000]) {

            Boolean hasTemplate = agent.AIPromptTemplate__c == template.Id;
            Boolean usesFallback = isActiveDefault && agent.IsActive__c == true && (agent.AIPromptTemplate__c == null || agent.AIPromptTemplate__r.IsActive__c != true);

            if (!hasTemplate && !usesFallback) continue;

            AIPromptTemplatesDataStructure.AgentUse agentUse = new AIPromptTemplatesDataStructure.AgentUse();
            agentUse.agentId = agent.Id;
            agentUse.agentName = agent.Name;
            agentUse.isActive = agent.IsActive__c == true;
            agentUse.usesFallback = !hasTemplate;
            agentUse.userCount = 0;
            agentUse.openConversationCount = 0;
            agentUses.add(agentUse);
            agentUseByAgentId.put(agent.Id, agentUse);
        }

        if (agentUses.isEmpty()) return agentUses;

        // [2] Count the users who have had a conversation with each agent
        for (AggregateResult userCountRow : [SELECT AIAgent__c agentId, COUNT_DISTINCT(OwnerId) userCount FROM AIConversation__c WHERE AIAgent__c IN :agentUseByAgentId.keySet() WITH SYSTEM_MODE GROUP BY AIAgent__c]) {

            agentUseByAgentId.get((Id) userCountRow.get('agentId')).userCount = (Integer) userCountRow.get('userCount');
        }

        // [3] Count the open conversations of each agent
        for (AggregateResult openCountRow : [SELECT AIAgent__c agentId, COUNT(Id) openCount FROM AIConversation__c WHERE AIAgent__c IN :agentUseByAgentId.keySet() AND Status__c = :AIAssistApplicationConstants.CONVERSATION_STATUS_ACTIVE WITH SYSTEM_MODE GROUP BY AIAgent__c]) {

            agentUseByAgentId.get((Id) openCountRow.get('agentId')).openConversationCount = (Integer) openCountRow.get('openCount');
        }

        return agentUses;
    }

    // The template with that Id, or the refusal that it is gone.
    private static AIPromptTemplate__c findTemplate(Id templateId) {

        // [1] Query it
        List<AIPromptTemplate__c> templates = [SELECT Id, Name, DeveloperName__c, IsActive__c, IsDefault__c, Version__c, MaxResponseLength__c, AISystemContext__c, AITone__c, AIPrompt__c, AIExclusionRules__c, LastModifiedDate, LastModifiedBy.Name FROM AIPromptTemplate__c WHERE Id = :templateId WITH SYSTEM_MODE LIMIT 1];

        // [2] Refuse one that is not there
        if (templates.isEmpty()) throw new AIPromptTemplatesEditorServiceException(Label.AI_Prompts_Error_Not_Found);

        return templates[0];
    }

    // Builds the detail the editor shows for a template, with the number of active agents that answer with it.
    private static AIPromptTemplatesDataStructure.TemplateDetail buildDetail(AIPromptTemplate__c template) {

        // [1] Copy the fields
        AIPromptTemplatesDataStructure.TemplateDetail detail = new AIPromptTemplatesDataStructure.TemplateDetail();
        detail.templateId = template.Id;
        detail.templateName = template.Name;
        detail.developerName = template.DeveloperName__c;
        detail.maxResponseLength = template.MaxResponseLength__c;
        detail.systemContext = template.AISystemContext__c;
        detail.tone = template.AITone__c;
        detail.prompt = template.AIPrompt__c;
        detail.exclusionRules = template.AIExclusionRules__c;
        detail.isActive = template.IsActive__c == true;
        detail.isDefault = template.IsDefault__c == true;
        detail.version = template.Version__c;
        detail.lastModifiedDate = template.LastModifiedDate;
        detail.lastModifiedByName = template.LastModifiedBy.Name;

        // [2] Count the active agents that answer with it
        Integer activeAgentCount = 0;

        for (AIPromptTemplatesDataStructure.AgentUse agentUse : getAgentUsesOfTemplate(template)) {

            if (agentUse.isActive == true) activeAgentCount++;
        }

        detail.agentCount = activeAgentCount;

        return detail;
    }

    // Builds one problem.
    private static AIPromptTemplatesDataStructure.FieldProblem buildProblem(String fieldName, String message) {

        // [1] Fill the problem
        AIPromptTemplatesDataStructure.FieldProblem problem = new AIPromptTemplatesDataStructure.FieldProblem();
        problem.fieldName = fieldName;
        problem.message = message;

        return problem;
    }

    // The text without spaces at the ends, or null when nothing is left.
    private static String getTextOrNull(String text) {

        // [1] Blank text is nothing
        return String.isBlank(text) ? null : text.trim();
    }
}
