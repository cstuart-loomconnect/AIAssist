/*
Class Name: AIPromptMergeFieldService

=================================================================
=================================================================

Description: Fills the merge fields in a prompt template's wording, such as {!Agent.Name} and {!Record.Name}.

Step 1: List the merge fields an administrator may write
Step 2: Work out the value of each one for an agent, a user and a record
Step 3: Replace each merge field in a template's wording with its value, or split the text so the preview can colour the values
Step 4: Find the merge fields a text uses that are not on the list

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPromptMergeFieldService {

    // The merge fields an administrator may write, in the order the Insert bar shows them.
    public static List<AIPromptTemplatesDataStructure.MergeFieldOption> getMergeFieldOptions() {

        // [1] Build one option per merge field
        List<AIPromptTemplatesDataStructure.MergeFieldOption> options = new List<AIPromptTemplatesDataStructure.MergeFieldOption>();

        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME, 'The name of the agent answering.'));
        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_USER_FIRST_NAME, 'The first name of the user chatting.'));
        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL, 'The kind of record the user has open, such as Opportunity.'));
        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME, 'The name of the record the user has open.'));
        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_TODAY, 'Today\'s date, in the user\'s format.'));
        options.add(buildOption(AIAssistApplicationConstants.PROMPT_MERGE_ORG_NAME, 'The name of your organisation.'));

        return options;
    }

    // The value of each merge field for this agent, the running user and the record. isPreview fills a value that is not known with a placeholder in square brackets, so the preview still reads well; a live turn leaves it blank.
    public static Map<String, String> buildValues(AIAgent__c agent, String objectApiName, Id recordId, Boolean isPreview) {

        // [1] Work out the object and record values
        String objectLabel = getObjectLabel(objectApiName);
        String recordName = getRecordName(objectApiName, recordId);

        // [2] Fill the values, using a placeholder for what is not known when previewing
        Map<String, String> valueByToken = new Map<String, String>();

        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME, agent == null ? (isPreview ? AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_AGENT_NAME : '') : agent.Name);
        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_USER_FIRST_NAME, String.isBlank(UserInfo.getFirstName()) ? '' : UserInfo.getFirstName());
        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL, String.isBlank(objectLabel) ? (isPreview ? AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_OBJECT_LABEL : '') : objectLabel);
        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME, String.isBlank(recordName) ? (isPreview ? AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_RECORD_NAME : '') : recordName);
        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_TODAY, Date.today().format());
        valueByToken.put(AIAssistApplicationConstants.PROMPT_MERGE_ORG_NAME, UserInfo.getOrganizationName());

        return valueByToken;
    }

    // The text with each known merge field replaced by its value. A merge field that is not known is left as it was written.
    public static String getFilledText(String text, Map<String, String> valueByToken) {

        // [1] Nothing to fill
        if (String.isBlank(text)) return text;

        // [2] Join the pieces back together
        String filledText = '';

        for (AIPromptTemplatesDataStructure.PreviewSegment segment : buildSegments(text, valueByToken)) {

            filledText += segment.text;
        }

        return filledText;
    }

    // Splits the text into pieces, marking the ones that are a filled-in merge field so the preview can colour them.
    public static List<AIPromptTemplatesDataStructure.PreviewSegment> buildSegments(String text, Map<String, String> valueByToken) {

        // [1] Start with no pieces
        List<AIPromptTemplatesDataStructure.PreviewSegment> segments = new List<AIPromptTemplatesDataStructure.PreviewSegment>();

        if (String.isBlank(text)) return segments;

        // [2] Walk through each merge field shape in the text
        Matcher mergeFieldMatcher = Pattern.compile(AIAssistApplicationConstants.PROMPT_MERGE_PATTERN).matcher(text);
        Integer cursor = 0;

        while (mergeFieldMatcher.find()) {

            // [3] Keep the plain text before it
            addSegment(segments, text.substring(cursor, mergeFieldMatcher.start()), false);

            // [4] Fill it when it is known, else keep it as written
            String token = mergeFieldMatcher.group();

            if (valueByToken.containsKey(token)) addSegment(segments, valueByToken.get(token), true);
            else addSegment(segments, token, false);

            cursor = mergeFieldMatcher.end();
        }

        // [5] Keep the plain text after the last one
        addSegment(segments, text.substring(cursor), false);

        return segments;
    }

    // A copy of the template with the merge fields filled in each piece of its wording. The copy keeps the Id and version, so the reply still records which template and version produced it.
    public static AIPromptTemplate__c buildFilledTemplate(AIPromptTemplate__c promptTemplate, Map<String, String> valueByToken) {

        // [1] Nothing to fill
        if (promptTemplate == null) return null;

        // [2] Copy the template and fill its wording
        AIPromptTemplate__c filledTemplate = promptTemplate.clone(true, false, false, false);

        filledTemplate.AISystemContext__c = getFilledText(promptTemplate.AISystemContext__c, valueByToken);
        filledTemplate.AITone__c = getFilledText(promptTemplate.AITone__c, valueByToken);
        filledTemplate.AIPrompt__c = getFilledText(promptTemplate.AIPrompt__c, valueByToken);
        filledTemplate.AIExclusionRules__c = getFilledText(promptTemplate.AIExclusionRules__c, valueByToken);

        return filledTemplate;
    }

    // The merge fields in the text that are not on the list, each once, in the order they appear.
    public static List<String> getUnknownTokens(String text) {

        // [1] Start with none
        List<String> unknownTokens = new List<String>();

        if (String.isBlank(text)) return unknownTokens;

        // [2] Collect the known merge fields
        Set<String> knownTokens = new Set<String>();

        for (AIPromptTemplatesDataStructure.MergeFieldOption option : getMergeFieldOptions()) {

            knownTokens.add(option.token);
        }

        // [3] Keep each merge field shape that is not known, once
        Matcher mergeFieldMatcher = Pattern.compile(AIAssistApplicationConstants.PROMPT_MERGE_PATTERN).matcher(text);

        while (mergeFieldMatcher.find()) {

            String token = mergeFieldMatcher.group();

            if (!knownTokens.contains(token) && !unknownTokens.contains(token)) unknownTokens.add(token);
        }

        return unknownTokens;
    }

    // The label of an object, or blank when there is no such object.
    private static String getObjectLabel(String objectApiName) {

        // [1] Nothing to look up
        if (String.isBlank(objectApiName)) return '';

        // [2] Describe the object, which fails for a name that is not an object
        try {

            return Schema.describeSObjects(new List<String>{objectApiName.trim()})[0].getLabel();

        } catch (Exception ex) {
            return '';
        }
    }

    // The name of a record, read as the running user, or blank when there is no record or the user cannot read it.
    private static String getRecordName(String objectApiName, Id recordId) {

        // [1] Nothing to look up
        if (String.isBlank(objectApiName) || recordId == null) return '';

        try {

            // [2] Describe the object, which also makes sure the name is a real object
            Schema.DescribeSObjectResult objectDescribe = Schema.describeSObjects(new List<String>{objectApiName.trim()})[0];
            String nameFieldApiName;

            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {

                if (field.getDescribe().isNameField()) nameFieldApiName = field.getDescribe().getName();
            }

            if (nameFieldApiName == null) return '';

            // [3] Read the name as the user, so a record they cannot see gives nothing
            String soql = 'SELECT ' + nameFieldApiName + ' FROM ' + objectDescribe.getName() + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.queryWithBinds(soql, new Map<String, Object>{'recordId' => recordId}, AccessLevel.USER_MODE);

            return records.isEmpty() ? '' : String.valueOf(records[0].get(nameFieldApiName));

        } catch (Exception ex) {
            return '';
        }
    }

    // Adds a piece of text when it is not empty.
    private static void addSegment(List<AIPromptTemplatesDataStructure.PreviewSegment> segments, String text, Boolean isValue) {

        // [1] An empty piece adds nothing
        if (String.isEmpty(text)) return;

        // [2] Add it
        AIPromptTemplatesDataStructure.PreviewSegment segment = new AIPromptTemplatesDataStructure.PreviewSegment();
        segment.text = text;
        segment.isValue = isValue;
        segments.add(segment);
    }

    // Builds one Insert bar option.
    private static AIPromptTemplatesDataStructure.MergeFieldOption buildOption(String token, String description) {

        // [1] Fill the option
        AIPromptTemplatesDataStructure.MergeFieldOption option = new AIPromptTemplatesDataStructure.MergeFieldOption();
        option.token = token;
        option.description = description;

        return option;
    }
}
