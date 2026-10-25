/*
Class Name: AIAgentWizardControllerTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWizardController: the Apex calls of the AI Agent Wizard tab.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardController: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardControllerTest {

    // testScenario1: A manager calls each method through the controller -> each call returns what its service returns.
    // testScenario2: A user without the Manage Settings permission calls every method of the controller -> the access label is shown for each, and nothing is logged for it.
    // testScenario3: A manager asks for an agent that does not exist -> the not found label is shown.
    // testScenario4: A save fails on the platform because the name is too long -> the generic label is shown and the error is logged once.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a model, an agent to copy and a draft, and a provider that answers
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Call each method, saving last because the platform refuses a callout after unsaved changes
            Test.startTest();
                AIModelsDataStructure.TestResult testResult = AIAgentWizardController.testModel(model.Id);
                AIAgentWizardDataStructure.TryResult tryResult = AIAgentWizardController.tryAgent(JSON.serialize(draft), 'Hello', null);
                AIAgentWizardDataStructure.WizardPage page = AIAgentWizardController.getWizardPage(null);
                AIAgentWizardDataStructure.AgentDraft copyDraft = AIAgentWizardController.getCopyDraft(agent.Id);
                List<AIAgentWizardDataStructure.ObjectOption> objects = AIAgentWizardController.searchObjects('account');
                AIAgentWizardDataStructure.DraftCheck check = AIAgentWizardController.checkDraft(JSON.serialize(draft));
                List<AIAgentWizardDataStructure.AssigneeOption> assignees = AIAgentWizardController.searchAssignees('AIAssistUser');
                AIAgentWizardDataStructure.UserCheck userCheck = AIAgentWizardController.checkUser(JSON.serialize(draft), superUser.Id);
                AIAgentWizardDataStructure.SaveResult saveResult = AIAgentWizardController.saveAgent(JSON.serialize(draft), true);
                List<AIAgentWizardDataStructure.AgentRow> rows = AIAgentWizardController.getAgentList();
                AIAgentWizardDataStructure.AgentRow offRow = AIAgentWizardController.setAgentActive(agent.Id, false);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(testResult.isSuccessful, 'The model test should pass.');
            Assert.isTrue(tryResult.isSuccessful, 'The trial should get a reply.');
            Assert.areEqual(1, page.models.size(), 'The page should offer the model.');
            Assert.areEqual('Copy of ' + agent.Name, copyDraft.agentName, 'The copy should be named as a copy.');
            Assert.isFalse(objects.isEmpty(), 'Objects should match the text.');
            Assert.isTrue(check.canActivate, 'The draft should be ready.');
            Assert.isFalse(assignees.isEmpty(), 'The permission set should be found.');
            Assert.isTrue(userCheck.hasAccess, 'The super user should have an agent that is open to all.');
            Assert.isTrue(saveResult.isActive, 'The agent should be saved live.');
            Assert.areEqual(2, rows.size(), 'Both agents should be listed.');
            Assert.isFalse(offRow.isActive, 'The agent should be switched off.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            List<String> refusals = new List<String>();

            // [2] Call every method as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIAgentWizardController.getWizardPage(null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.getCopyDraft(null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.searchObjects('account'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.checkDraft(JSON.serialize(draft)); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.testModel(null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.searchAssignees('abc'); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.checkUser(JSON.serialize(draft), users[0].Id); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.tryAgent(JSON.serialize(draft), 'Hello', null); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.saveAgent(JSON.serialize(draft), false); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.getAgentList(); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                    try { AIAgentWizardController.setAgentActive(null, false); } catch (AuraHandledException ex) { refusals.add(ex.getMessage()); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(11, refusals.size(), 'Every method should refuse.');
            Assert.areEqual(new Set<String>{Label.AI_Settings_Error_Access}, new Set<String>(refusals), 'The access label should be shown each time.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIPlatformLog__c], 'A refusal is not an error, so nothing should be logged.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build the Id of an agent that was never saved
            Id missingId = AIAgent__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001AAA';
            String refusal;

            // [2] Ask for a copy of it
            Test.startTest();
                try { AIAgentWizardController.getCopyDraft(missingId); } catch (AuraHandledException ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Not_Found, refusal, 'The not found label should be shown.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft whose name is longer than the field allows, which the platform refuses on save
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.agentName = 'x'.repeat(300);
            String refusal;

            // [2] Save it
            Test.startTest();
                try { AIAgentWizardController.saveAgent(JSON.serialize(draft), false); } catch (AuraHandledException ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Read the log
            List<AIPlatformLog__c> logs = [SELECT ClassName__c, MethodName__c FROM AIPlatformLog__c];

            // [4] Check the outcome
            Assert.areEqual(Label.AI_Error_Generic, refusal, 'The generic label should be shown.');
            Assert.areEqual(1, logs.size(), 'The error should be logged once.');
            Assert.areEqual('AIAgentWizardController', logs[0].ClassName__c, 'The log should name the controller.');
            Assert.areEqual('saveAgent', logs[0].MethodName__c, 'The log should name the method.');
        }
    }
}
