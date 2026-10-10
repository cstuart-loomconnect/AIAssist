/*
Class Name: AIPromptTemplateServiceTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplateService: which of an Agent's Prompt Templates answers a message, and which others the model may switch to.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplateServiceTest {

    // testScenario1: An agent has a default and three other templates, one without a description, one without a name and one inactive -> the default starts the turn and only the named, described, active template is offered to the model.
    // testScenario2: A template is asked for that is active on the agent -> it is used and the model is offered nothing to switch to.
    // testScenario3: A template is asked for that is inactive, belongs to another agent or is a null Id -> the request is ignored and the default is used.
    // testScenario4: An agent has exactly one active template and no default ticked -> that template is the default and nothing is offered.
    // testScenario5: An agent has several active templates and none is the default -> no template starts the turn and every described one is offered.
    // testScenario6: An agent has no templates, and no agent is given -> the choice has no template and nothing to offer.
    // testScenario7: A template is looked up by its Developer Name -> an active one is found, and a blank name, an unknown name, an inactive template and another agent's template give nothing.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a default template and three others
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 5, false);
            templates[0].IsDefault__c = true;
            templates[1].DeveloperName__c = 'draft_client_email';
            templates[1].Description__c = 'Drafts an email to the client.';
            templates[2].DeveloperName__c = 'summarise_account';
            templates[3].Description__c = 'Has a description but no name.';
            templates[4].DeveloperName__c = 'retired_template';
            templates[4].Description__c = 'Used to be offered.';
            templates[4].IsActive__c = false;
            insert templates;

            // [2] Work out the choice for a message that asked for nothing
            AIPromptTemplateService.PromptTemplateChoice choice;

            Test.startTest();
                choice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
            Test.stopTest();

            // [3] Check the default starts the turn and one template is offered
            Assert.areEqual(templates[0].Id, choice.promptTemplate.Id, 'The default template should start the turn.');
            Assert.areEqual(1, choice.routingTemplates.size(), 'Only a named, described, active template should be offered.');
            Assert.areEqual(templates[1].Id, choice.routingTemplates[0].Id, 'The email template should be the one offered.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a default template and another described one
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
            templates[0].IsDefault__c = true;
            templates[1].DeveloperName__c = 'draft_client_email';
            templates[1].Description__c = 'Drafts an email to the client.';
            insert templates;

            // [2] Work out the choice for a message that asked for the email template
            AIPromptTemplateService.PromptTemplateChoice choice;

            Test.startTest();
                choice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, templates[1].Id);
            Test.stopTest();

            // [3] Check the asked-for template is used and nothing is offered
            Assert.areEqual(templates[1].Id, choice.promptTemplate.Id, 'The template that was asked for should be used.');
            Assert.isTrue(choice.routingTemplates.isEmpty(), 'The model should have nothing to switch to when the user chose.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two agents, a default template, an inactive one and another agent's template
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agents[0].Id, 2, false);
            templates[0].IsDefault__c = true;
            templates[1].IsActive__c = false;
            insert templates;

            AIPromptTemplate__c otherAgentsTemplate = AIAssistTestDataFactory.createAIPromptTemplates(agents[1].Id, 1, true)[0];

            // [2] Work out the choice for each request that cannot be honoured
            AIPromptTemplateService.PromptTemplateChoice inactiveChoice;
            AIPromptTemplateService.PromptTemplateChoice otherAgentChoice;
            AIPromptTemplateService.PromptTemplateChoice nullChoice;

            Test.startTest();
                inactiveChoice = AIPromptTemplateService.getPromptTemplateChoice(agents[0].Id, templates[1].Id);
                otherAgentChoice = AIPromptTemplateService.getPromptTemplateChoice(agents[0].Id, otherAgentsTemplate.Id);
                nullChoice = AIPromptTemplateService.getPromptTemplateChoice(agents[0].Id, null);
            Test.stopTest();

            // [3] Check each falls back to the default
            Assert.areEqual(templates[0].Id, inactiveChoice.promptTemplate.Id, 'An inactive template should be ignored.');
            Assert.areEqual(templates[0].Id, otherAgentChoice.promptTemplate.Id, 'Another agent\'s template should be ignored.');
            Assert.areEqual(templates[0].Id, nullChoice.promptTemplate.Id, 'No request should use the default.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with one active template and no default ticked
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c onlyTemplate = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true)[0];

            // [2] Work out the choice for a message that asked for nothing
            AIPromptTemplateService.PromptTemplateChoice choice;

            Test.startTest();
                choice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
            Test.stopTest();

            // [3] Check the only template is the default and nothing is offered
            Assert.areEqual(onlyTemplate.Id, choice.promptTemplate.Id, 'The only active template should count as the default.');
            Assert.isTrue(choice.routingTemplates.isEmpty(), 'There is nothing else to offer.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with two described templates and no default
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
            templates[0].DeveloperName__c = 'draft_client_email';
            templates[0].Description__c = 'Drafts an email to the client.';
            templates[1].DeveloperName__c = 'summarise_account';
            templates[1].Description__c = 'Summarises an account.';
            insert templates;

            // [2] Work out the choice for a message that asked for nothing
            AIPromptTemplateService.PromptTemplateChoice choice;

            Test.startTest();
                choice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
            Test.stopTest();

            // [3] Check no template starts the turn and both are offered
            Assert.isNull(choice.promptTemplate, 'No template should start the turn when none is the default.');
            Assert.areEqual(2, choice.routingTemplates.size(), 'Both described templates should be offered to the model.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with no templates
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            // [2] Work out the choice for the agent and for no agent
            AIPromptTemplateService.PromptTemplateChoice noTemplatesChoice;
            AIPromptTemplateService.PromptTemplateChoice noAgentChoice;

            Test.startTest();
                noTemplatesChoice = AIPromptTemplateService.getPromptTemplateChoice(agent.Id, null);
                noAgentChoice = AIPromptTemplateService.getPromptTemplateChoice(null, null);
            Test.stopTest();

            // [3] Check neither has a template or anything to offer
            Assert.isNull(noTemplatesChoice.promptTemplate, 'An agent with no templates has no template.');
            Assert.isTrue(noTemplatesChoice.routingTemplates.isEmpty(), 'An agent with no templates offers nothing.');
            Assert.isNull(noAgentChoice.promptTemplate, 'No agent has no template.');
            Assert.isTrue(noAgentChoice.routingTemplates.isEmpty(), 'No agent offers nothing.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two agents, an active template, an inactive one and another agent's template
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agents[0].Id, 2, false);
            templates[0].DeveloperName__c = 'draft_client_email';
            templates[1].DeveloperName__c = 'retired_template';
            templates[1].IsActive__c = false;
            insert templates;

            List<AIPromptTemplate__c> otherTemplates = AIAssistTestDataFactory.createAIPromptTemplates(agents[1].Id, 1, false);
            otherTemplates[0].DeveloperName__c = 'summarise_account';
            insert otherTemplates;

            // [2] Look each one up
            AIPromptTemplate__c found;
            AIPromptTemplate__c blankName;
            AIPromptTemplate__c unknownName;
            AIPromptTemplate__c inactive;
            AIPromptTemplate__c otherAgents;

            Test.startTest();
                found = AIPromptTemplateService.findActiveTemplate(agents[0].Id, 'draft_client_email');
                blankName = AIPromptTemplateService.findActiveTemplate(agents[0].Id, ' ');
                unknownName = AIPromptTemplateService.findActiveTemplate(agents[0].Id, 'made_up');
                inactive = AIPromptTemplateService.findActiveTemplate(agents[0].Id, 'retired_template');
                otherAgents = AIPromptTemplateService.findActiveTemplate(agents[0].Id, 'summarise_account');
            Test.stopTest();

            // [3] Check only the active template of that agent is found
            Assert.areEqual(templates[0].Id, found.Id, 'The active template should be found by its name.');
            Assert.isNull(blankName, 'A blank name should find nothing.');
            Assert.isNull(unknownName, 'An unknown name should find nothing.');
            Assert.isNull(inactive, 'An inactive template should not be found.');
            Assert.isNull(otherAgents, 'Another agent\'s template should not be found.');
        }
    }
}
