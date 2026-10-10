/*
Class Name: AIPromptTemplateTriggerHandlerTest

=================================================================
=================================================================

Description: Testing utility for AIPromptTemplateTrigger and AIPromptTemplateTriggerHandler: the version that goes up only when the wording the model is given changes, and the one active default template per agent.

=================================================================
=================================================================
Applicable Classes:

AIPromptTemplateTriggerHandler: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIPromptTemplateTriggerHandlerTest {

    // testScenario1: Change the prompt, system context, tone and exclusion rules on four templates -> each version goes up by one.
    // testScenario2: Change something that is not the wording -> the version is left alone.
    // testScenario3: Change the wording on 201 templates in bulk -> every one is versioned once with no queries in the update.
    // testScenario4: Settings switched off, wording changed, and the handler called with null input -> nothing is versioned and nothing is thrown.
    // testScenario5: The handler throws unexpectedly during a wording change -> the version is not raised and one platform log is written.
    // testScenario6: A second active default is inserted for an agent that already has one, with a default for another agent beside it -> only the second default for the same agent is refused with the label.
    // testScenario7: Two defaults for one agent are inserted together -> the first is saved and the second is refused.
    // testScenario8: The default is moved by unticking it and ticking another, and then a template is ticked while another is still the default -> the move is saved and the clash is refused, and an unrelated edit to the default is never refused.
    // testScenario9: The default rule throws unexpectedly -> the second default is not refused and one platform log names the method.
    // testScenario10: A default that is not active, a Developer Name with capitals or spaces, and a valid Developer Name are inserted -> the first two are refused by their validation rules and the valid one is saved.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create four inactive templates and note their starting version
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 4, false);
            for (AIPromptTemplate__c template : templates) template.IsActive__c = false;
            insert templates;

            Decimal startVersion = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :templates[0].Id].Version__c;

            // [2] Change the prompt, context, tone and exclusion rules, one per template
            Test.startTest();
                templates[0].AIPrompt__c = 'A new prompt.';
                templates[1].AISystemContext__c = 'New context.';
                templates[2].AITone__c = 'Formal';
                templates[3].AIExclusionRules__c = 'Never discuss pricing.';
                update templates;
            Test.stopTest();

            // [3] Read the templates back
            List<AIPromptTemplate__c> savedTemplates = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id IN :templates];

            // [4] Check each version went up by one
            Assert.areEqual(4, savedTemplates.size(), 'All four templates should be saved.');
            for (AIPromptTemplate__c saved : savedTemplates) {
                Assert.areEqual(startVersion + 1, saved.Version__c, 'The version should go up by one for the change.');
            }
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template and note its starting version
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true)[0];
            Decimal startVersion = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :template.Id].Version__c;

            // [2] Change something that is not the wording
            Test.startTest();
                template.IsActive__c = false;
                update template;
            Test.stopTest();

            // [3] Read the template back
            AIPromptTemplate__c saved = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :template.Id];

            // [4] Check the version is unchanged
            Assert.areEqual(startVersion, saved.Version__c, 'The version should be unchanged when the wording is unchanged.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create 201 inactive templates
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 201, false);
            for (AIPromptTemplate__c template : templates) template.IsActive__c = false;
            insert templates;

            Integer queries;

            // [2] Change the system context on every template and note the queries used
            Test.startTest();
                for (AIPromptTemplate__c template : templates) template.AISystemContext__c = 'New context';
                update templates;
                queries = Limits.getQueries();
            Test.stopTest();

            // [3] Count the versioned templates
            Integer versionedCount = [SELECT COUNT() FROM AIPromptTemplate__c WHERE Version__c = 2];

            // [4] Check every template was versioned once with no extra queries
            Assert.areEqual(201, versionedCount, 'Every template should be versioned once.');
            Assert.isTrue(queries <= 3, 'There should be no queries in the update: ' + queries);
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template, note its version and switch the application off
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true);
            Decimal startVersion = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :templates[0].Id].Version__c;

            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsEnabled__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            // [2] Change the wording, then call the handler with null input
            Test.startTest();
                templates[0].AIPrompt__c = 'Changed while off.';
                update templates;
                AIPromptTemplateTriggerHandler.handleBeforeUpdate(null, null);
            Test.stopTest();

            // [3] Read the template and the logs back
            AIPromptTemplate__c saved = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :templates[0].Id];
            Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

            // [4] Check the version is unchanged and nothing was logged
            Assert.areEqual(startVersion, saved.Version__c, 'The template should not be versioned while the application is switched off.');
            Assert.areEqual(0, logCount, 'Null input should be ignored without logging.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a template, note its version and force the handler to throw
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIPromptTemplate__c template = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, true)[0];
            Decimal startVersion = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :template.Id].Version__c;

            AIPromptTemplateTriggerHandler.isTestCustomExceptionThrown = true;

            // [2] Change the wording
            Test.startTest();
                template.AIPrompt__c = 'Changed while failing.';
                update template;
            Test.stopTest();

            // [3] Read the template and the logs back
            AIPromptTemplate__c saved = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :template.Id];
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the version is unchanged and one log names the handler
            Assert.areEqual(startVersion, saved.Version__c, 'The version should not be raised when the handler fails.');
            Assert.areEqual(1, logs.size(), 'Exactly one platform log should be written.');

            Assert.areEqual('AIPromptTemplateTriggerHandler', logs[0].ClassName__c, 'The log should name the handler class.');
            Assert.areEqual('handleBeforeUpdate', logs[0].MethodName__c, 'The log should name the failing method.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two agents and give the first a default template
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            AIPromptTemplate__c firstDefault = AIAssistTestDataFactory.createAIPromptTemplates(agents[0].Id, 1, false)[0];
            firstDefault.IsDefault__c = true;
            insert firstDefault;

            AIPromptTemplate__c clashingDefault = AIAssistTestDataFactory.createAIPromptTemplates(agents[0].Id, 1, false)[0];
            clashingDefault.IsDefault__c = true;

            AIPromptTemplate__c otherAgentsDefault = AIAssistTestDataFactory.createAIPromptTemplates(agents[1].Id, 1, false)[0];
            otherAgentsDefault.IsDefault__c = true;

            List<Database.SaveResult> results;

            // [2] Insert a second default for the first agent and a default for the second agent
            Test.startTest();
                results = Database.insert(new List<AIPromptTemplate__c>{ clashingDefault, otherAgentsDefault }, false);
            Test.stopTest();

            // [3] Count the active defaults each agent has
            Integer firstAgentDefaults = [SELECT COUNT() FROM AIPromptTemplate__c WHERE AIAgent__c = :agents[0].Id AND IsDefault__c = TRUE];
            Integer secondAgentDefaults = [SELECT COUNT() FROM AIPromptTemplate__c WHERE AIAgent__c = :agents[1].Id AND IsDefault__c = TRUE];

            // [4] Check only the clash was refused
            Assert.isFalse(results[0].isSuccess(), 'A second default for the same agent should be refused.');
            Assert.areEqual(Label.AI_Error_Prompt_Template_Default_Exists, results[0].getErrors()[0].getMessage(), 'The refusal should say the agent already has a default.');
            Assert.isTrue(results[1].isSuccess(), 'A default for another agent should be saved.');
            Assert.areEqual(1, firstAgentDefaults, 'The first agent should keep one default.');
            Assert.areEqual(1, secondAgentDefaults, 'The second agent should have its own default.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and two default templates for it
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
            templates[0].IsDefault__c = true;
            templates[1].IsDefault__c = true;

            List<Database.SaveResult> results;

            // [2] Insert both together
            Test.startTest();
                results = Database.insert(templates, false);
            Test.stopTest();

            // [3] Count the defaults saved
            Integer savedDefaults = [SELECT COUNT() FROM AIPromptTemplate__c WHERE AIAgent__c = :agent.Id AND IsDefault__c = TRUE];

            // [4] Check the first was saved and the second refused
            Assert.isTrue(results[0].isSuccess(), 'The first default should be saved.');
            Assert.isFalse(results[1].isSuccess(), 'The second default in the same save should be refused.');
            Assert.areEqual(1, savedDefaults, 'Only one default should be saved.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a default and a second active template
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
            templates[0].IsDefault__c = true;
            insert templates;

            List<Database.SaveResult> unrelatedEditResults;
            List<Database.SaveResult> moveResults;
            List<Database.SaveResult> clashResults;

            // [2] Edit the default's description, then move the default to the second template, then tick the first again while the second is the default
            Test.startTest();
                templates[0].Description__c = 'An unrelated edit.';
                unrelatedEditResults = Database.update(new List<AIPromptTemplate__c>{ templates[0] }, false);

                templates[0].IsDefault__c = false;
                templates[1].IsDefault__c = true;
                moveResults = Database.update(templates, false);

                templates[0].IsDefault__c = true;
                clashResults = Database.update(new List<AIPromptTemplate__c>{ templates[0] }, false);
            Test.stopTest();

            // [3] Read back which template is the default
            AIPromptTemplate__c savedDefault = [SELECT Id FROM AIPromptTemplate__c WHERE AIAgent__c = :agent.Id AND IsDefault__c = TRUE];

            // [4] Check the unrelated edit and the move were saved and the clash was refused
            Assert.isTrue(unrelatedEditResults[0].isSuccess(), 'Editing the default for another reason should never be refused.');
            Assert.isTrue(moveResults[0].isSuccess() && moveResults[1].isSuccess(), 'Moving the default in one save should be saved.');
            Assert.isFalse(clashResults[0].isSuccess(), 'Ticking a second default should be refused.');
            Assert.areEqual(templates[1].Id, savedDefault.Id, 'The moved default should be the one that remains.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent with a default, and force the default rule to throw
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIPromptTemplate__c firstDefault = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            firstDefault.IsDefault__c = true;
            insert firstDefault;

            AIPromptTemplate__c secondDefault = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 1, false)[0];
            secondDefault.IsDefault__c = true;

            AIPromptTemplateTriggerHandler.isTestDefaultRuleExceptionThrown = true;

            // [2] Insert a second default
            Test.startTest();
                insert secondDefault;
            Test.stopTest();

            // [3] Read the defaults and the logs back
            Integer savedDefaults = [SELECT COUNT() FROM AIPromptTemplate__c WHERE AIAgent__c = :agent.Id AND IsDefault__c = TRUE];
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the rule was not applied and one log names the method
            Assert.areEqual(2, savedDefaults, 'The second default should not be refused when the rule fails.');
            Assert.areEqual(1, logs.size(), 'Exactly one platform log should be written.');

            Assert.areEqual('AIPromptTemplateTriggerHandler', logs[0].ClassName__c, 'The log should name the handler class.');
            Assert.areEqual('handleBeforeSave', logs[0].MethodName__c, 'The log should name the failing method.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and three templates: an inactive default, a bad Developer Name and a good one
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 3, false);
            templates[0].IsActive__c = false;
            templates[0].IsDefault__c = true;
            templates[1].DeveloperName__c = 'Draft Client Email';
            templates[2].DeveloperName__c = 'draft_client_email';

            List<Database.SaveResult> results;

            // [2] Insert all three
            Test.startTest();
                results = Database.insert(templates, false);
            Test.stopTest();

            // [3] Check the first two were refused and the good one saved
            Assert.isFalse(results[0].isSuccess(), 'A default that is not active should be refused.');
            Assert.isFalse(results[1].isSuccess(), 'A Developer Name with capitals and spaces should be refused.');
            Assert.isTrue(results[2].isSuccess(), 'A valid Developer Name should be saved.');
        }
    }
}
