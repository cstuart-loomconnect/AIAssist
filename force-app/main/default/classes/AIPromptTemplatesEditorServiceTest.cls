/*
Class Name: AIPromptTemplatesEditorServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplatesEditorService: reading, checking, previewing, saving, archiving and defaulting the prompt templates, and keeping their test messages.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplatesEditorService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplatesEditorServiceTest {

    // testScenario1: Templates and agents are listed -> each row counts the active agents that answer with it, and the default counts the agents with no template of their own.
    // testScenario2: One template is read, and a missing template is read -> the detail has every field and the agent count, and the missing one is refused.
    // testScenario3: The merge fields and the agents to try are requested -> six merge fields, and only active agents with a model, with their first object.
    // testScenario4: A good template is previewed with an agent, and a bad one is previewed -> the good one has sections with values marked and a token estimate, and the bad one has problems and no sections.
    // testScenario5: The publish dialog is built for a new template, a changed template and an unchanged one -> new reaches nobody, changed names its sections and raises the version, unchanged keeps it.
    // testScenario6: A new template is saved, an existing one is changed, and bad ones are saved -> the first two are saved and versioned, and the bad ones come back as problems.
    // testScenario7: The agents of a template are listed with conversations -> users and open conversations are counted, and the default also lists an agent that falls back to it.
    // testScenario8: A template is archived with one agent moved and one sent to the default, and the default is archived -> the agents move and the template is off, and the default and a bad target are refused.
    // testScenario9: A template is activated and made the default -> an empty one is refused to activate, an inactive one is refused as default, and the default moves in one save.
    // testScenario10: Test messages are saved, listed, marked and deleted -> they are kept in order, and bad ones, a 26th and a bad mark are refused.
    // testScenario11: A user with only the end user permission set calls the service -> the access label is shown.
    // testScenario12: The first object of agents with none, one and two objects is read -> blank, the object and the first.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default, an own template, an inactive template and three agents
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(3, model.Id, true);

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 3, false);
            templates[0].IsDefault__c = true;
            insert templates;

            templates[2].IsActive__c = false;
            update templates[2];

            agents[0].AIPromptTemplate__c = templates[1].Id;
            agents[2].IsActive__c = false;
            update agents;

            // [2] Read the rows
            List<AIPromptTemplatesDataStructure.TemplateRow> rows;

            Test.startTest();
                rows = AIPromptTemplatesEditorService.getTemplateRows();
            Test.stopTest();

            // [3] Index the rows by template
            Map<Id, AIPromptTemplatesDataStructure.TemplateRow> rowByTemplateId = new Map<Id, AIPromptTemplatesDataStructure.TemplateRow>();
            for (AIPromptTemplatesDataStructure.TemplateRow row : rows) rowByTemplateId.put(row.templateId, row);

            // [4] Check the counts and flags
            Assert.areEqual(3, rows.size(), 'Every template is listed.');
            Assert.areEqual(1, rowByTemplateId.get(templates[1].Id).agentCount, 'The own template has the one agent that has it.');
            Assert.areEqual(1, rowByTemplateId.get(templates[0].Id).agentCount, 'The default has the active agent with no template, not the inactive one.');
            Assert.isTrue(rowByTemplateId.get(templates[0].Id).isDefault, 'The default is flagged.');
            Assert.isFalse(rowByTemplateId.get(templates[2].Id).isActive, 'The inactive template is flagged.');
            Assert.areEqual(0, rowByTemplateId.get(templates[2].Id).agentCount, 'The inactive template has no agents.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a template that has wording
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
            template.DeveloperName__c = 'MortgageAdviser';
            template.AISystemContext__c = 'Context text';
            template.AITone__c = 'Tone text';
            template.AIExclusionRules__c = 'Never text';
            template.MaxResponseLength__c = 250;
            insert template;

            agent.AIPromptTemplate__c = template.Id;
            update agent;

            // [2] Read the template, and a template that is not there
            AIPromptTemplatesDataStructure.TemplateDetail detail;
            String missingMessage;

            Test.startTest();
                detail = AIPromptTemplatesEditorService.getTemplateDetail(template.Id);

                try {
                    AIPromptTemplatesEditorService.getTemplateDetail(UserInfo.getUserId());
                } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) {
                    missingMessage = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check every field and the refusal
            Assert.areEqual(template.Name, detail.templateName, 'The name is read.');
            Assert.areEqual('MortgageAdviser', detail.developerName, 'The API name is read.');
            Assert.areEqual('Context text', detail.systemContext, 'The context is read.');
            Assert.areEqual('Tone text', detail.tone, 'The tone is read.');
            Assert.areEqual('Answer briefly.', detail.prompt, 'The instructions are read.');
            Assert.areEqual('Never text', detail.exclusionRules, 'The never rules are read.');
            Assert.areEqual(250, detail.maxResponseLength, 'The response length is read.');
            Assert.areEqual(1, detail.agentCount, 'One active agent answers with it.');
            Assert.isNotNull(detail.lastModifiedByName, 'Who last changed it is read.');
            Assert.areEqual(Label.AI_Prompts_Error_Not_Found, missingMessage, 'A template that is gone is refused with its label.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with two objects, an agent with no model and an inactive agent
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, false);
            agents[0].ObjectApiNames__c = 'Opportunity, Account';
            agents[1].IsActive__c = false;
            insert agents;
            insert AIAssistTestDataFactory.createAIAgents(1, null, false);

            // [2] Ask for the merge fields and the agents
            List<AIPromptTemplatesDataStructure.MergeFieldOption> mergeFields;
            List<AIPromptTemplatesDataStructure.AgentOption> agentOptions;

            Test.startTest();
                mergeFields = AIPromptTemplatesEditorService.getMergeFieldOptions();
                agentOptions = AIPromptTemplatesEditorService.getAgentOptions();
            Test.stopTest();

            // [3] Check only the usable agent is offered, with its first object
            Assert.areEqual(6, mergeFields.size(), 'Six merge fields are offered.');
            Assert.areEqual(1, agentOptions.size(), 'Only the active agent with a model is offered.');
            Assert.areEqual(agents[0].Id, agentOptions[0].agentId, 'It is the right agent.');
            Assert.areEqual('Opportunity', agentOptions[0].objectApiName, 'Its first object is offered.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a persona, and a good and a bad template detail
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.AIAgentPersona__c = 'A patient adviser.';
            insert agent;

            AIPromptTemplatesDataStructure.TemplateDetail goodDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            goodDetail.templateName = 'Good';
            goodDetail.developerName = 'Good';
            goodDetail.systemContext = 'You are {!Agent.Name}.';
            goodDetail.prompt = 'Answer briefly.';
            goodDetail.maxResponseLength = 100;

            AIPromptTemplatesDataStructure.TemplateDetail badDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            badDetail.templateName = 'Bad';
            badDetail.developerName = 'Bad';
            badDetail.systemContext = 'Lender {!Record.Lender__c}';

            // [2] Preview both
            AIPromptTemplatesDataStructure.PreviewResult goodPreview;
            AIPromptTemplatesDataStructure.PreviewResult badPreview;

            Test.startTest();
                goodPreview = AIPromptTemplatesEditorService.getPreview(goodDetail, agent.Id, null);
                badPreview = AIPromptTemplatesEditorService.getPreview(badDetail, null, null);
            Test.stopTest();

            // [3] Check the good preview
            Assert.isTrue(goodPreview.problems.isEmpty(), 'The good template has no problems.');
            Assert.areEqual(4, goodPreview.sections.size(), 'Persona, context, instructions and response length.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_PERSONA, goodPreview.sections[0].heading, 'The persona comes first.');
            Assert.isTrue(goodPreview.sections[1].segments[1].isValue, 'The agent name is marked as a value.');
            Assert.areEqual(agent.Name, goodPreview.sections[1].segments[1].text, 'And shows the agent name.');
            Assert.isTrue(goodPreview.estimatedTokens > 0, 'The tokens are estimated.');

            // [4] Check the bad preview
            Assert.areEqual(2, badPreview.problems.size(), 'The unknown merge field and the missing instructions are reported.');
            Assert.isTrue(badPreview.sections.isEmpty(), 'No sections are shown while there are problems.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template used by an agent, with a passed test message and a worse one
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true)[0];
            insert new List<AIPromptTestMessage__c>{ new AIPromptTestMessage__c(AIPromptTemplate__c = template.Id, MessageBody__c = 'One', LastRunStatus__c = 'Passed'), new AIPromptTestMessage__c(AIPromptTemplate__c = template.Id, MessageBody__c = 'Two', LastRunStatus__c = 'Passed', EditedVerdict__c = 'Worse'), new AIPromptTestMessage__c(AIPromptTemplate__c = template.Id, MessageBody__c = 'Three') };

            AIPromptTemplatesDataStructure.TemplateDetail changedDetail = AIPromptTemplatesEditorService.getTemplateDetail(template.Id);
            changedDetail.prompt = 'Answer very briefly.';
            changedDetail.exclusionRules = 'Never guess.';
            AIPromptTemplatesDataStructure.TemplateDetail unchangedDetail = AIPromptTemplatesEditorService.getTemplateDetail(template.Id);
            AIPromptTemplatesDataStructure.TemplateDetail newDetail = new AIPromptTemplatesDataStructure.TemplateDetail();

            // [2] Build the dialog for each
            AIPromptTemplatesDataStructure.PublishImpact changedImpact;
            AIPromptTemplatesDataStructure.PublishImpact unchangedImpact;
            AIPromptTemplatesDataStructure.PublishImpact newImpact;

            Test.startTest();
                changedImpact = AIPromptTemplatesEditorService.getPublishImpact(changedDetail);
                unchangedImpact = AIPromptTemplatesEditorService.getPublishImpact(unchangedDetail);
                newImpact = AIPromptTemplatesEditorService.getPublishImpact(newDetail);
            Test.stopTest();

            // [3] Check each
            Assert.isTrue(newImpact.isNew, 'A template that is not saved is new.');
            Assert.isTrue(newImpact.agentUses.isEmpty(), 'A new template reaches nobody.');
            Assert.areEqual(new List<String>{AIAssistApplicationConstants.PROMPT_SECTION_INSTRUCTIONS, AIAssistApplicationConstants.PROMPT_SECTION_NEVER}, changedImpact.changedSections, 'The changed sections are named.');
            Assert.areEqual(changedImpact.currentVersion + 1, changedImpact.nextVersion, 'A change raises the version.');
            Assert.areEqual(1, changedImpact.agentUses.size(), 'The agent that has the template is reached.');
            Assert.areEqual(3, changedImpact.testMessageCount, 'Three test messages are saved.');
            Assert.areEqual(1, changedImpact.testPassedCount, 'One passed and was not marked worse.');
            Assert.isTrue(unchangedImpact.changedSections.isEmpty(), 'Nothing changed.');
            Assert.areEqual(unchangedImpact.currentVersion, unchangedImpact.nextVersion, 'No change keeps the version.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a new template, a name taken by it, and a template with every kind of problem
            AIPromptTemplatesDataStructure.TemplateDetail newDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            newDetail.templateName = '  New one ';
            newDetail.developerName = 'NewOne';
            newDetail.prompt = ' Answer briefly. ';
            newDetail.maxResponseLength = 200;

            AIPromptTemplatesDataStructure.TemplateDetail takenDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            takenDetail.templateName = 'Taken';
            takenDetail.developerName = 'newone';
            takenDetail.prompt = 'Answer.';

            AIPromptTemplatesDataStructure.TemplateDetail badDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            badDetail.templateName = ' ';
            badDetail.developerName = 'no spaces';
            badDetail.maxResponseLength = 0;
            badDetail.tone = '{!Nope}';

            AIPromptTemplatesDataStructure.TemplateDetail blankApiDetail = new AIPromptTemplatesDataStructure.TemplateDetail();
            blankApiDetail.templateName = 'Blank API';
            blankApiDetail.prompt = 'Answer.';

            // [2] Save the new template, change it, and try the others
            AIPromptTemplatesDataStructure.SaveResult newResult;
            AIPromptTemplatesDataStructure.SaveResult changedResult;
            AIPromptTemplatesDataStructure.SaveResult takenResult;
            AIPromptTemplatesDataStructure.SaveResult badResult;
            AIPromptTemplatesDataStructure.SaveResult blankApiResult;

            Test.startTest();
                newResult = AIPromptTemplatesEditorService.saveTemplate(newDetail);

                AIPromptTemplatesDataStructure.TemplateDetail changedDetail = AIPromptTemplatesEditorService.getTemplateDetail(newResult.detail.templateId);
                changedDetail.prompt = 'Answer very briefly.';
                changedResult = AIPromptTemplatesEditorService.saveTemplate(changedDetail);

                takenResult = AIPromptTemplatesEditorService.saveTemplate(takenDetail);
                badResult = AIPromptTemplatesEditorService.saveTemplate(badDetail);
                blankApiResult = AIPromptTemplatesEditorService.saveTemplate(blankApiDetail);
            Test.stopTest();

            // [3] Check the saves
            Assert.isTrue(newResult.isSaved, 'The new template is saved.');
            Assert.areEqual('New one', newResult.detail.templateName, 'The name is trimmed.');
            Assert.areEqual('Answer briefly.', newResult.detail.prompt, 'The instructions are trimmed.');
            Assert.isTrue(newResult.detail.isActive, 'A new template is active.');
            Assert.isFalse(newResult.detail.isDefault, 'A new template is not the default.');
            Assert.areEqual(1, newResult.detail.version, 'A new template is version 1.');
            Assert.isTrue(changedResult.isSaved, 'The change is saved.');
            Assert.areEqual(2, changedResult.detail.version, 'The change raises the version.');

            // [4] Check the problems
            Assert.isFalse(takenResult.isSaved, 'A name that is taken is refused.');
            Assert.areEqual(Label.AI_Prompts_Error_Api_Name_Taken, takenResult.problems[0].message, 'The refusal says it is taken.');
            Assert.isFalse(badResult.isSaved, 'A bad template is refused.');
            Assert.areEqual(new List<String>{AIAssistApplicationConstants.PROMPT_FIELD_NAME, AIAssistApplicationConstants.PROMPT_FIELD_DEVELOPER_NAME, AIAssistApplicationConstants.PROMPT_FIELD_MAX_RESPONSE_LENGTH, AIAssistApplicationConstants.PROMPT_FIELD_TONE, AIAssistApplicationConstants.PROMPT_FIELD_PROMPT}, new List<String>{badResult.problems[0].fieldName, badResult.problems[1].fieldName, badResult.problems[2].fieldName, badResult.problems[3].fieldName, badResult.problems[4].fieldName}, 'Each problem names its field in order.');
            Assert.areEqual(Label.AI_Prompts_Error_Api_Name_Format, badResult.problems[1].message, 'A name with spaces has the wrong shape.');
            Assert.isFalse(blankApiResult.isSaved, 'A blank API name is refused.');
            Assert.areEqual(Label.AI_Prompts_Error_Api_Name_Required, blankApiResult.problems[0].message, 'The refusal says the API name is needed.');
            Assert.areEqual(1, [SELECT COUNT() FROM AIPromptTemplate__c], 'Only the one template was saved.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default template, an agent with it and a second agent with none, and conversations for the first
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
            template.IsDefault__c = true;
            insert template;

            agents[0].AIPromptTemplate__c = template.Id;
            update agents[0];

            List<User> otherUsers = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.createAIConversations(agents[0].Id, null, 2, true);
            AIAssistTestDataFactory.createAIConversations(agents[0].Id, otherUsers[0].Id, 1, true);

            // [2] List the agents of the template
            List<AIPromptTemplatesDataStructure.AgentUse> agentUses;

            Test.startTest();
                agentUses = AIPromptTemplatesEditorService.getAgentUses(template.Id);
            Test.stopTest();

            // [3] Index the agents
            Map<Id, AIPromptTemplatesDataStructure.AgentUse> agentUseByAgentId = new Map<Id, AIPromptTemplatesDataStructure.AgentUse>();
            for (AIPromptTemplatesDataStructure.AgentUse agentUse : agentUses) agentUseByAgentId.put(agentUse.agentId, agentUse);

            // [4] Check the counts and the fallback
            Assert.areEqual(2, agentUses.size(), 'The agent that has it and the agent that falls back to it.');
            Assert.areEqual(2, agentUseByAgentId.get(agents[0].Id).userCount, 'Two users have had a conversation.');
            Assert.areEqual(3, agentUseByAgentId.get(agents[0].Id).openConversationCount, 'Three conversations are open.');
            Assert.isFalse(agentUseByAgentId.get(agents[0].Id).usesFallback, 'The first agent has the template.');
            Assert.isTrue(agentUseByAgentId.get(agents[1].Id).usesFallback, 'The second agent falls back to it.');
            Assert.areEqual(0, agentUseByAgentId.get(agents[1].Id).userCount, 'It has no users yet.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default, a template to archive, a target and two agents that have the one to archive
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 3, false);
            templates[0].IsDefault__c = true;
            insert templates;

            agents[0].AIPromptTemplate__c = templates[1].Id;
            agents[1].AIPromptTemplate__c = templates[1].Id;
            update agents;

            AIPromptTemplatesDataStructure.ArchiveMove moveToTarget = new AIPromptTemplatesDataStructure.ArchiveMove();
            moveToTarget.agentId = agents[0].Id;
            moveToTarget.newTemplateId = templates[2].Id;

            AIPromptTemplatesDataStructure.ArchiveMove moveToDefault = new AIPromptTemplatesDataStructure.ArchiveMove();
            moveToDefault.agentId = agents[1].Id;

            AIPromptTemplatesDataStructure.ArchiveMove moveToArchived = new AIPromptTemplatesDataStructure.ArchiveMove();
            moveToArchived.agentId = agents[1].Id;
            moveToArchived.newTemplateId = templates[1].Id;

            // [2] Read the options, refuse a move to the template itself, refuse the default, then archive
            AIPromptTemplatesDataStructure.ArchiveOptions options;
            AIPromptTemplatesDataStructure.ArchiveOptions defaultOptions;
            String badTargetMessage;
            String defaultMessage;

            Test.startTest();
                options = AIPromptTemplatesEditorService.getArchiveOptions(templates[1].Id);
                defaultOptions = AIPromptTemplatesEditorService.getArchiveOptions(templates[0].Id);

                try {
                    AIPromptTemplatesEditorService.archiveTemplate(templates[1].Id, new List<AIPromptTemplatesDataStructure.ArchiveMove>{ moveToArchived });
                } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) {
                    badTargetMessage = ex.getMessage();
                }

                try {
                    AIPromptTemplatesEditorService.archiveTemplate(templates[0].Id, null);
                } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) {
                    defaultMessage = ex.getMessage();
                }

                AIPromptTemplatesEditorService.archiveTemplate(templates[1].Id, new List<AIPromptTemplatesDataStructure.ArchiveMove>{ moveToTarget, moveToDefault });
            Test.stopTest();

            // [3] Read the results back
            Map<Id, AIAgent__c> agentById = new Map<Id, AIAgent__c>([SELECT AIPromptTemplate__c FROM AIAgent__c WHERE Id IN :agents]);
            AIPromptTemplate__c archived = [SELECT IsActive__c FROM AIPromptTemplate__c WHERE Id = :templates[1].Id];

            // [4] Check the options, the refusals and the moves
            Assert.isFalse(options.isDefault, 'The template to archive is not the default.');
            Assert.areEqual(2, options.agentUses.size(), 'Both agents that have it are listed.');
            Assert.areEqual(2, options.templateOptions.size(), 'The other two active templates are offered.');
            Assert.areEqual(templates[0].Name, options.defaultName, 'The default is named.');
            Assert.isTrue(defaultOptions.isDefault, 'The default is flagged.');
            Assert.areEqual(Label.AI_Prompts_Error_Move_Target_Invalid, badTargetMessage, 'An agent cannot move to the template being archived.');
            Assert.areEqual(Label.AI_Prompts_Error_Default_Cannot_Archive, defaultMessage, 'The default cannot be archived.');
            Assert.areEqual(templates[2].Id, agentById.get(agents[0].Id).AIPromptTemplate__c, 'The first agent moved to the chosen template.');
            Assert.isNull(agentById.get(agents[1].Id).AIPromptTemplate__c, 'The second agent went to the default.');
            Assert.isFalse(archived.IsActive__c, 'The template is archived.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default, a second active template, an inactive template and one with no instructions
            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 4, false);
            templates[0].IsDefault__c = true;
            insert templates;

            templates[2].IsActive__c = false;
            update templates[2];

            AIPromptTemplate__c emptyTemplate = new AIPromptTemplate__c(Name = 'Empty');
            insert emptyTemplate;

            // [2] Activate the empty and the inactive, make the inactive the default, and make the second the default
            String emptyMessage;
            String inactiveMessage;

            Test.startTest();
                try {
                    AIPromptTemplatesEditorService.activateTemplate(emptyTemplate.Id);
                } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) {
                    emptyMessage = ex.getMessage();
                }

                try {
                    AIPromptTemplatesEditorService.setDefaultTemplate(templates[2].Id);
                } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) {
                    inactiveMessage = ex.getMessage();
                }

                AIPromptTemplatesEditorService.activateTemplate(templates[2].Id);
                AIPromptTemplatesEditorService.setDefaultTemplate(templates[1].Id);
            Test.stopTest();

            // [3] Read back which templates are active and the default
            AIPromptTemplate__c activated = [SELECT IsActive__c FROM AIPromptTemplate__c WHERE Id = :templates[2].Id];
            AIPromptTemplate__c savedDefault = [SELECT Id FROM AIPromptTemplate__c WHERE IsDefault__c = TRUE];

            // [4] Check the refusals and the results
            Assert.areEqual(Label.AI_Prompts_Error_Instructions_Required, emptyMessage, 'A template with no instructions cannot be activated.');
            Assert.areEqual(Label.AI_Prompts_Error_Default_Must_Be_Active, inactiveMessage, 'An inactive template cannot be the default.');
            Assert.isTrue(activated.IsActive__c, 'The inactive template was activated.');
            Assert.areEqual(templates[1].Id, savedDefault.Id, 'The default moved in one save.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            List<String> refusals = new List<String>();

            // [2] Save two messages, mark one on each side, delete the second and try the refusals
            AIPromptTemplatesDataStructure.TestMessage first;
            AIPromptTemplatesDataStructure.TestMessage second;
            AIPromptTemplatesDataStructure.TestMessage marked;
            List<AIPromptTemplatesDataStructure.TestMessage> listedBefore;
            List<AIPromptTemplatesDataStructure.TestMessage> listedAfter;

            Test.startTest();
                first = AIPromptTemplatesEditorService.saveTestMessage(template.Id, '  Will rates fall? ');
                second = AIPromptTemplatesEditorService.saveTestMessage(template.Id, 'Second');
                AIPromptTemplatesEditorService.setVerdict(first.testMessageId, AIAssistApplicationConstants.PROMPT_VERDICT_SIDE_SAVED, AIAssistApplicationConstants.PROMPT_VERDICT_WORSE);
                marked = AIPromptTemplatesEditorService.setVerdict(first.testMessageId, AIAssistApplicationConstants.PROMPT_VERDICT_SIDE_EDITED, AIAssistApplicationConstants.PROMPT_VERDICT_BETTER);
                listedBefore = AIPromptTemplatesEditorService.getTestMessages(template.Id);
                AIPromptTemplatesEditorService.deleteTestMessage(second.testMessageId);
                listedAfter = AIPromptTemplatesEditorService.getTestMessages(template.Id);

                try { AIPromptTemplatesEditorService.saveTestMessage(template.Id, ' '); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesEditorService.saveTestMessage(template.Id, 'x'.repeat(AIAssistApplicationConstants.PROMPT_TEST_MESSAGE_MAX_LENGTH + 1)); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesEditorService.saveTestMessage(null, 'Hello'); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesEditorService.setVerdict(first.testMessageId, 'saved', 'Great'); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIPromptTemplatesEditorService.deleteTestMessage(second.testMessageId); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }

                for (Integer messageIndex = 0; messageIndex < AIAssistApplicationConstants.PROMPT_TEST_MESSAGES_MAX_PER_TEMPLATE - 1; messageIndex++) AIPromptTemplatesEditorService.saveTestMessage(template.Id, 'Message ' + messageIndex);

                try { AIPromptTemplatesEditorService.saveTestMessage(template.Id, 'One too many'); } catch (AIPromptTemplatesEditorService.AIPromptTemplatesEditorServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check the messages and the refusals
            Assert.areEqual('Will rates fall?', first.messageBody, 'The message is trimmed.');
            Assert.areEqual(2, listedBefore.size(), 'Both messages are listed.');
            Assert.areEqual(first.testMessageId, listedBefore[0].testMessageId, 'The oldest is first.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_VERDICT_WORSE, listedBefore[0].savedVerdict, 'The saved side is marked.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_VERDICT_BETTER, marked.editedVerdict, 'The edited side is marked.');
            Assert.areEqual(1, listedAfter.size(), 'The deleted message is gone.');
            Assert.areEqual(new List<String>{Label.AI_Prompts_Error_Message_Required, Label.AI_Prompts_Error_Message_Too_Long, Label.AI_Prompts_Error_Save_First, Label.AI_Prompts_Error_Verdict, Label.AI_Prompts_Error_Not_Found, Label.AI_Prompts_Error_Too_Many_Messages}, refusals, 'Each bad call shows its own label.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            String refusal;

            // [2] Read the list as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try {
                        AIPromptTemplatesEditorService.getTemplateRows();
                    } catch (Exception ex) {
                        refusal = ex.getMessage();
                    }
                }
            Test.stopTest();

            // [3] Check the access label
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label is shown.');
        }
    }

    @IsTest static void testScenario12() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build agents with no object, one object and two objects
            AIAgent__c noObject = new AIAgent__c();
            AIAgent__c oneObject = new AIAgent__c(ObjectApiNames__c = ' Case ');
            AIAgent__c twoObjects = new AIAgent__c(ObjectApiNames__c = 'Opportunity,Account');

            // [2] Read the first object of each, and of no agent
            String noObjectName;
            String oneObjectName;
            String twoObjectsName;
            String noAgentName;
            AIAgent__c noAgent;

            Test.startTest();
                noObjectName = AIPromptTemplatesEditorService.getFirstObjectApiName(noObject);
                oneObjectName = AIPromptTemplatesEditorService.getFirstObjectApiName(oneObject);
                twoObjectsName = AIPromptTemplatesEditorService.getFirstObjectApiName(twoObjects);
                noAgentName = AIPromptTemplatesEditorService.getFirstObjectApiName(null);
                noAgent = AIPromptTemplatesEditorService.findAgent(null);
            Test.stopTest();

            // [3] Check each
            Assert.isNull(noObjectName, 'An agent with no object has none.');
            Assert.areEqual('Case', oneObjectName, 'The one object is trimmed.');
            Assert.areEqual('Opportunity', twoObjectsName, 'The first of two is used.');
            Assert.isNull(noAgentName, 'No agent has no object.');
            Assert.isNull(noAgent, 'No Id finds no agent.');
        }
    }
}
