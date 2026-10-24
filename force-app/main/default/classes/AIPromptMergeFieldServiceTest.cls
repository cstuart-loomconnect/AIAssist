/*
Class Name: AIPromptMergeFieldServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPromptMergeFieldService: the merge fields, their values, and filling them into a template's wording.

=================================================================
=================================================================
Applicable Classes:

AIPromptMergeFieldService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptMergeFieldServiceTest {

    // testScenario1: The Insert bar options are requested -> the six merge fields come back in order, each with a description.
    // testScenario2: Values are built for an agent and an Account record -> the agent name, object label, record name, date and organisation are filled.
    // testScenario3: Values are built with no agent or record, as a preview and as a live turn -> the preview shows placeholders and the live turn leaves them blank.
    // testScenario4: Text with known, unknown and repeated merge fields is split and filled -> known ones are marked as values and unknown ones are left as written.
    // testScenario5: Unknown merge fields are looked for in text -> each unknown one is returned once, and known, blank and plain text give none.
    // testScenario6: A template is filled -> its four wordings are filled and its Id, version and response length are kept, and a null template gives null.
    // testScenario7: Values are built for an object that does not exist and for a record that does not exist -> the label and name are blank rather than an error.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Ask for the options
            List<AIPromptTemplatesDataStructure.MergeFieldOption> options;

            Test.startTest();
                options = AIPromptMergeFieldService.getMergeFieldOptions();
            Test.stopTest();

            // [2] Check the six merge fields
            Assert.areEqual(6, options.size(), 'There are six merge fields.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME, options[0].token, 'The agent name comes first.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_MERGE_ORG_NAME, options[5].token, 'The organisation name comes last.');
            Assert.isNotNull(options[3].description, 'Each option says what it is.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and an account
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];

            // [2] Build the values
            Map<String, String> valueByToken;

            Test.startTest();
                valueByToken = AIPromptMergeFieldService.buildValues(agent, 'Account', account.Id, false);
            Test.stopTest();

            // [3] Check each value
            Assert.areEqual(agent.Name, valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME), 'The agent name is filled.');
            Assert.areEqual(UserInfo.getFirstName(), valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_USER_FIRST_NAME), 'The first name is the running user\'s.');
            Assert.areEqual('Account', valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL), 'The object label is filled.');
            Assert.areEqual(account.Name, valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME), 'The record name is read.');
            Assert.areEqual(Date.today().format(), valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_TODAY), 'Today is the date in the user\'s format.');
            Assert.areEqual(UserInfo.getOrganizationName(), valueByToken.get(AIAssistApplicationConstants.PROMPT_MERGE_ORG_NAME), 'The organisation name is filled.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the values with nothing known, as a preview and as a live turn
            Map<String, String> previewValues;
            Map<String, String> liveValues;

            Test.startTest();
                previewValues = AIPromptMergeFieldService.buildValues(null, null, null, true);
                liveValues = AIPromptMergeFieldService.buildValues(null, null, null, false);
            Test.stopTest();

            // [2] Check the placeholders and the blanks
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_AGENT_NAME, previewValues.get(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME), 'The preview shows a placeholder for the agent.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_OBJECT_LABEL, previewValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL), 'The preview shows a placeholder for the object.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_PREVIEW_SAMPLE_RECORD_NAME, previewValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME), 'The preview shows a placeholder for the record.');
            Assert.areEqual('', liveValues.get(AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME), 'A live turn leaves the agent blank.');
            Assert.areEqual('', liveValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME), 'A live turn leaves the record blank.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build text with a known merge field twice and an unknown one
            Map<String, String> valueByToken = new Map<String, String>{AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME => 'Ava'};
            String text = 'You are {!Agent.Name}. Lender is {!Record.Lender__c}. Again {!Agent.Name}';

            // [2] Split and fill it, and fill blank text
            List<AIPromptTemplatesDataStructure.PreviewSegment> segments;
            String filledText;
            String blankText;

            Test.startTest();
                segments = AIPromptMergeFieldService.buildSegments(text, valueByToken);
                filledText = AIPromptMergeFieldService.getFilledText(text, valueByToken);
                blankText = AIPromptMergeFieldService.getFilledText(null, valueByToken);
            Test.stopTest();

            // [3] Check the pieces and the filled text
            Assert.areEqual(6, segments.size(), 'Six pieces: text, value, text, unknown, text, value.');
            Assert.isTrue(segments[1].isValue, 'The first merge field is marked as a value.');
            Assert.areEqual('Ava', segments[1].text, 'And shows its value.');
            Assert.isFalse(segments[3].isValue, 'The unknown merge field is not marked as a value.');
            Assert.areEqual('You are Ava. Lender is {!Record.Lender__c}. Again Ava', filledText, 'The unknown merge field is left as written.');
            Assert.isNull(blankText, 'Blank text stays blank.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Look for unknown merge fields in four texts
            List<String> unknownTokens;
            List<String> knownTokens;
            List<String> plainTokens;
            List<String> blankTokens;

            Test.startTest();
                unknownTokens = AIPromptMergeFieldService.getUnknownTokens('{!Record.Lender__c} and {!Record.Lender__c} and {!Org.Name} and {!Nope}');
                knownTokens = AIPromptMergeFieldService.getUnknownTokens('{!Today} {!Agent.Name}');
                plainTokens = AIPromptMergeFieldService.getUnknownTokens('No merge fields here.');
                blankTokens = AIPromptMergeFieldService.getUnknownTokens(null);
            Test.stopTest();

            // [2] Check only the unknown ones, once each
            Assert.areEqual(new List<String>{'{!Record.Lender__c}', '{!Nope}'}, unknownTokens, 'Each unknown merge field is listed once, in order.');
            Assert.isTrue(knownTokens.isEmpty(), 'Known merge fields are fine.');
            Assert.isTrue(plainTokens.isEmpty(), 'Plain text has none.');
            Assert.isTrue(blankTokens.isEmpty(), 'Blank text has none.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template that uses merge fields
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
            template.AISystemContext__c = 'For {!Org.Name}';
            template.AITone__c = 'Address {!User.FirstName}';
            template.AIPrompt__c = 'Help with {!Record.ObjectLabel}';
            template.AIExclusionRules__c = 'Never name {!Agent.Name}';
            template.MaxResponseLength__c = 120;
            insert template;

            Map<String, String> valueByToken = new Map<String, String>{AIAssistApplicationConstants.PROMPT_MERGE_ORG_NAME => 'Acme', AIAssistApplicationConstants.PROMPT_MERGE_USER_FIRST_NAME => 'Sam', AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL => 'Opportunity', AIAssistApplicationConstants.PROMPT_MERGE_AGENT_NAME => 'Ava'};

            // [2] Fill it, and fill a null template
            AIPromptTemplate__c filledTemplate;
            AIPromptTemplate__c nullTemplate;

            Test.startTest();
                filledTemplate = AIPromptMergeFieldService.buildFilledTemplate(template, valueByToken);
                nullTemplate = AIPromptMergeFieldService.buildFilledTemplate(null, valueByToken);
            Test.stopTest();

            // [3] Check the wording is filled and the rest is kept
            Assert.areEqual('For Acme', filledTemplate.AISystemContext__c, 'The context is filled.');
            Assert.areEqual('Address Sam', filledTemplate.AITone__c, 'The tone is filled.');
            Assert.areEqual('Help with Opportunity', filledTemplate.AIPrompt__c, 'The instructions are filled.');
            Assert.areEqual('Never name Ava', filledTemplate.AIExclusionRules__c, 'The never rules are filled.');
            Assert.areEqual(template.Id, filledTemplate.Id, 'The copy keeps the Id.');
            Assert.areEqual(120, filledTemplate.MaxResponseLength__c, 'The copy keeps the response length.');
            Assert.areEqual('For {!Org.Name}', [SELECT AISystemContext__c FROM AIPromptTemplate__c WHERE Id = :template.Id].AISystemContext__c, 'The saved template is not changed.');
            Assert.isNull(nullTemplate, 'No template gives no copy.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build values for an object that does not exist, and for an account Id that is not a record
            Map<String, String> noObjectValues;
            Map<String, String> noRecordValues;

            Test.startTest();
                noObjectValues = AIPromptMergeFieldService.buildValues(null, 'NotAnObject__c', UserInfo.getUserId(), false);
                noRecordValues = AIPromptMergeFieldService.buildValues(null, 'Account', '001000000000000AAA', false);
            Test.stopTest();

            // [2] Check the label and name are blank rather than an error
            Assert.areEqual('', noObjectValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL), 'An unknown object has no label.');
            Assert.areEqual('', noObjectValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME), 'An unknown object has no record name.');
            Assert.areEqual('Account', noRecordValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_OBJECT_LABEL), 'A real object has its label.');
            Assert.areEqual('', noRecordValues.get(AIAssistApplicationConstants.PROMPT_MERGE_RECORD_NAME), 'A record that is not there has no name.');
        }
    }
}
