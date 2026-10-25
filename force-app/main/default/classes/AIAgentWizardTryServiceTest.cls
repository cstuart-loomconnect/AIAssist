/*
Class Name: AIAgentWizardTryServiceTest

=================================================================
=================================================================

Description: Testing utility for AIAgentWizardTryService: the trial message of the Review step.

=================================================================
=================================================================
Applicable Classes:

AIAgentWizardTryService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIAgentWizardTryServiceTest {

    // testScenario1: A draft with a chosen template and a record is tried -> the model replies once and the reply is reported.
    // testScenario2: A draft with no template is tried when a default template exists, and when none exists at all -> each still gets a reply.
    // testScenario3: The model refuses the call -> the result is not successful and shows the safe message.
    // testScenario4: No draft, a blank message, a message that is too long, no model and a model that is gone -> each is refused with its own label.
    // testScenario5: A user without the Manage Settings permission tries a message -> the access label is shown.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft that names a template, a record to merge, and a provider that answers
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIPromptTemplate__c promptTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, true)[0];
            Account account = AIAssistTestDataFactory.createAccounts(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.promptTemplateId = promptTemplate.Id;
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Try a message
            Test.startTest();
                AIAgentWizardDataStructure.TryResult result = AIAgentWizardTryService.tryAgent(draft, 'Hello', account.Id);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isTrue(result.isSuccessful, 'The model replied.');
            Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, result.replyText, 'The reply is the model\'s.');
            Assert.isNull(result.errorMessage, 'There is no error.');
            Assert.areEqual(1, AIAssistTestProviderMock.callCount, 'The model is called once.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIConversation__c], 'No conversation is saved.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft with no template, and a provider that answers
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            draft.objectApiNames = null;
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Try with no template at all, then with a default template
            Test.startTest();
                AIAgentWizardDataStructure.TryResult plainResult = AIAgentWizardTryService.tryAgent(draft, 'Hello', null);
                AIPromptTemplate__c defaultTemplate = AIAssistTestDataFactory.createAIPromptTemplates(null, 1, false)[0];
                defaultTemplate.IsDefault__c = true;
                insert defaultTemplate;
            Test.stopTest();

            AIAgentWizardDataStructure.TryResult defaultResult = AIAgentWizardTryService.tryAgent(draft, 'Hello', null);

            // [3] Check the outcome
            Assert.isTrue(plainResult.isSuccessful, 'A plain prompt is used when there is no template.');
            Assert.isTrue(defaultResult.isSuccessful, 'The default template is used when none is chosen.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft and a provider that refuses
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

            // [2] Try a message
            Test.startTest();
                AIAgentWizardDataStructure.TryResult result = AIAgentWizardTryService.tryAgent(draft, 'Hello', null);
            Test.stopTest();

            // [3] Check the outcome
            Assert.isFalse(result.isSuccessful, 'The model did not reply.');
            Assert.areEqual(Label.AI_Prompts_Error_Run_Failed, result.errorMessage, 'The safe message is shown.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a draft with no model, and one whose model never was saved
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(model.Id);
            AIAgentWizardDataStructure.AgentDraft noModelDraft = AIAssistTestDataFactory.createAIAgentDraft(null);
            AIAgentWizardDataStructure.AgentDraft goneModelDraft = AIAssistTestDataFactory.createAIAgentDraft(AIModelConfiguration__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
            String noDraftRefusal;
            String blankRefusal;
            String longRefusal;
            String noModelRefusal;
            String goneModelRefusal;

            // [2] Try each
            Test.startTest();
                try { AIAgentWizardTryService.tryAgent(null, 'Hello', null); } catch (Exception ex) { noDraftRefusal = ex.getMessage(); }
                try { AIAgentWizardTryService.tryAgent(draft, '  ', null); } catch (Exception ex) { blankRefusal = ex.getMessage(); }
                try { AIAgentWizardTryService.tryAgent(draft, 'x'.repeat(4001), null); } catch (Exception ex) { longRefusal = ex.getMessage(); }
                try { AIAgentWizardTryService.tryAgent(noModelDraft, 'Hello', null); } catch (Exception ex) { noModelRefusal = ex.getMessage(); }
                try { AIAgentWizardTryService.tryAgent(goneModelDraft, 'Hello', null); } catch (Exception ex) { goneModelRefusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Wizard_Error_Draft_Required, noDraftRefusal, 'A missing draft is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Message_Required, blankRefusal, 'A blank message is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_Message_Too_Long, longRefusal, 'A long message is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_No_Model, noModelRefusal, 'A draft with no model is refused.');
            Assert.areEqual(Label.AI_Wizard_Error_No_Model, goneModelRefusal, 'A model that is gone is refused.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds only the end user permission set, and a draft
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, 'AIAssistUser');
            AIAgentWizardDataStructure.AgentDraft draft = AIAssistTestDataFactory.createAIAgentDraft(null);
            String refusal;

            // [2] Try as that user
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIAgentWizardTryService.tryAgent(draft, 'Hello', null); } catch (Exception ex) { refusal = ex.getMessage(); }
                }
            Test.stopTest();

            // [3] Check the outcome
            Assert.areEqual(Label.AI_Settings_Error_Access, refusal, 'The access label should be shown.');
        }
    }
}
