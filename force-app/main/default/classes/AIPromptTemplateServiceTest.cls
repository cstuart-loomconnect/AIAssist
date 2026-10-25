/*
Class Name: AIPromptTemplateServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplateService: which Prompt Template answers a message, and how a template is split into the sections the model receives.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplateServiceTest {

    // testScenario1: An agent has its own template and the org has a default -> the agent's own template answers and nothing is offered to the model.
    // testScenario2: A template is asked for that is active -> it wins over the agent's own template, and an inactive or null request is ignored.
    // testScenario3: An agent has no template, or its template is inactive -> the default answers.
    // testScenario4: There is no default and the agent has no usable template, and no agent is given -> the choice has no template.
    // testScenario5: A template is looked up by its Developer Name -> an active one is found, and a blank name, an unknown name and an inactive template give nothing.
    // testScenario6: A template with every part of its wording and a response length is split into sections -> they come in the order persona, context, tone, instructions, never, response length.
    // testScenario7: A template with only instructions and no persona, a template that is null, and a response length of zero -> only the sections with text are returned.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default template, the agent's own template and an agent that has it
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 2, false);
            templates[0].IsDefault__c = true;
            insert templates;

            agent.AIPromptTemplate__c = templates[1].Id;
            update agent;

            // [2] Work out the choice for a message that asked for nothing
            AIPromptTemplateService.PromptTemplateChoice choice;

            Test.startTest();
                choice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
            Test.stopTest();

            // [3] Check the agent's own template answers and the model has nothing to switch to
            Assert.areEqual(templates[1].Id, choice.promptTemplate.Id, 'The agent\'s own template answers, not the default.');
            Assert.isTrue(choice.routingTemplates.isEmpty(), 'The model is offered no other template.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create the agent's own template, a template a command can ask for and an inactive one
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 3, false);
            templates[2].IsActive__c = false;
            insert templates;

            agent.AIPromptTemplate__c = templates[0].Id;
            update agent;

            // [2] Work out the choice for an active request, an inactive request and a null request
            AIPromptTemplateService.PromptTemplateChoice askedForChoice;
            AIPromptTemplateService.PromptTemplateChoice inactiveChoice;
            AIPromptTemplateService.PromptTemplateChoice nullChoice;

            Test.startTest();
                askedForChoice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, templates[1].Id);
                inactiveChoice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, templates[2].Id);
                nullChoice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
            Test.stopTest();

            // [3] Check the active request wins and the others fall back to the agent's own template
            Assert.areEqual(templates[1].Id, askedForChoice.promptTemplate.Id, 'The template that was asked for answers.');
            Assert.areEqual(templates[0].Id, inactiveChoice.promptTemplate.Id, 'An inactive request is ignored and the agent\'s own template answers.');
            Assert.areEqual(templates[0].Id, nullChoice.promptTemplate.Id, 'No request means the agent\'s own template answers.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a default template, an inactive template and two agents
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true);

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 2, false);
            templates[0].IsDefault__c = true;
            insert templates;

            templates[1].IsActive__c = false;
            update templates[1];

            agents[1].AIPromptTemplate__c = templates[1].Id;
            update agents[1];

            // [2] Work out the choice for an agent with no template and one whose template is inactive
            AIPromptTemplateService.PromptTemplateChoice noTemplateChoice;
            AIPromptTemplateService.PromptTemplateChoice inactiveTemplateChoice;

            Test.startTest();
                noTemplateChoice = AIPromptTemplateService.getPromptTemplateChoice(agents[0].Id, null);
                inactiveTemplateChoice = AIPromptTemplateService.getPromptTemplateChoice(agents[1].Id, null);
            Test.stopTest();

            // [3] Check the default answers for both
            Assert.areEqual(templates[0].Id, noTemplateChoice.promptTemplate.Id, 'An agent with no template uses the default.');
            Assert.areEqual(templates[0].Id, inactiveTemplateChoice.promptTemplate.Id, 'An agent whose template is inactive uses the default.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with no template and no default in the org
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            // [2] Work out the choice with no default, and with no agent at all
            AIPromptTemplateService.PromptTemplateChoice noDefaultChoice;
            AIPromptTemplateService.PromptTemplateChoice noAgentChoice;

            Test.startTest();
                noDefaultChoice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
                noAgentChoice = AIPromptTemplateService.getPromptTemplateChoice(null, null);
            Test.stopTest();

            // [3] Check neither finds a template
            Assert.isNull(noDefaultChoice.promptTemplate, 'With no template and no default, nothing answers.');
            Assert.isNull(noAgentChoice.promptTemplate, 'With no agent, nothing answers.');
            Assert.isTrue(noAgentChoice.routingTemplates.isEmpty(), 'And nothing is offered.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an active template with a Developer Name and an inactive one
            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(null, 2, false);
            templates[0].DeveloperName__c = 'draft_client_email';
            templates[1].DeveloperName__c = 'retired_template';
            templates[1].IsActive__c = false;
            insert templates;

            // [2] Look up each name, a blank name and an unknown name
            AIPromptTemplate__c foundTemplate;
            AIPromptTemplate__c blankNameTemplate;
            AIPromptTemplate__c unknownNameTemplate;
            AIPromptTemplate__c inactiveTemplate;

            Test.startTest();
                foundTemplate = AIPromptTemplateService.findActiveTemplate('draft_client_email');
                blankNameTemplate = AIPromptTemplateService.findActiveTemplate('');
                unknownNameTemplate = AIPromptTemplateService.findActiveTemplate('no_such_template');
                inactiveTemplate = AIPromptTemplateService.findActiveTemplate('retired_template');
            Test.stopTest();

            // [3] Check only the active template is found
            Assert.areEqual(templates[0].Id, foundTemplate.Id, 'The active template is found by its Developer Name.');
            Assert.isNull(blankNameTemplate, 'A blank name finds nothing.');
            Assert.isNull(unknownNameTemplate, 'An unknown name finds nothing.');
            Assert.isNull(inactiveTemplate, 'An inactive template is not found.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a template with every part of its wording and a response length
            AIPromptTemplate__c template = new AIPromptTemplate__c(AISystemContext__c = 'You help advisers.', AITone__c = 'Concise.', AIPrompt__c = 'Answer from the data.', AIExclusionRules__c = 'Never guess.', MaxResponseLength__c = 250);

            // [2] Split it into sections
            List<AIPromptTemplateService.PromptSection> sections;

            Test.startTest();
                sections = AIPromptTemplateService.getPromptSections('A patient adviser.', template);
            Test.stopTest();

            // [3] Check the sections and their order
            Assert.areEqual(6, sections.size(), 'Every part of the wording is a section.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_PERSONA, sections[0].heading, 'The persona comes first.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_CONTEXT, sections[1].heading, 'Then the context.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_TONE, sections[2].heading, 'Then the tone.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_INSTRUCTIONS, sections[3].heading, 'Then the instructions.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_NEVER, sections[4].heading, 'Then the never rules.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_RESPONSE_LENGTH, sections[5].heading, 'And the response length last.');
            Assert.areEqual('Keep replies under 250 words.', sections[5].text, 'The response length is a sentence.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a template with only instructions and one with a response length of zero
            AIPromptTemplate__c instructionsOnly = new AIPromptTemplate__c(AIPrompt__c = 'Answer briefly.');
            AIPromptTemplate__c zeroLength = new AIPromptTemplate__c(AIPrompt__c = 'Answer briefly.', MaxResponseLength__c = 0);

            // [2] Split them, and split a missing template with no persona
            List<AIPromptTemplateService.PromptSection> instructionsOnlySections;
            List<AIPromptTemplateService.PromptSection> zeroLengthSections;
            List<AIPromptTemplateService.PromptSection> nullTemplateSections;

            Test.startTest();
                instructionsOnlySections = AIPromptTemplateService.getPromptSections(null, instructionsOnly);
                zeroLengthSections = AIPromptTemplateService.getPromptSections('', zeroLength);
                nullTemplateSections = AIPromptTemplateService.getPromptSections(null, null);
            Test.stopTest();

            // [3] Check only the sections with text come back
            Assert.areEqual(1, instructionsOnlySections.size(), 'Only the instructions have text.');
            Assert.areEqual(AIAssistApplicationConstants.PROMPT_SECTION_INSTRUCTIONS, instructionsOnlySections[0].heading, 'That section is the instructions.');
            Assert.areEqual(1, zeroLengthSections.size(), 'A response length of zero adds no section.');
            Assert.isTrue(nullTemplateSections.isEmpty(), 'No template and no persona gives no sections.');
        }
    }
}
