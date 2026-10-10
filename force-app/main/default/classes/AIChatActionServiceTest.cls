/*
Class Name: AIChatActionServiceTest

=================================================================
=================================================================

Description: Testing utility for AIChatActionService: the Suggested Action card, its input fields, and running it through the dispatcher.

=================================================================
=================================================================
Applicable Classes:

AIChatActionService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIChatActionServiceTest {

    // testScenario1: A card shows the action, its confirmation requirement, and the default confirmation text when none is set.
    // testScenario2: An input schema becomes fields with types, labels and required flags, and a malformed schema becomes none.
    // testScenario3: run executes the suggested action and returns its output, and a refusal comes back as a result with the Custom Label, not an exception.
    // testScenario4: A reply with no suggested action cannot be run.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a workflow action that does not require confirmation
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_FLOW, 'Some_Flow', false)[0];
            action.RequiresConfirmation__c = false;

            // [2] Build the suggested action card
            AIChatDataStructure.SuggestedAction card;

            Test.startTest();
                card = AIChatActionService.buildSuggestionAction(action);
            Test.stopTest();

            // [3] Check the card details
            Assert.areEqual(action.ActionName__c, card.name, 'The card should show the action name.');
            Assert.isFalse(card.requiresConfirmation, 'The card should not require confirmation.');
            Assert.areEqual(Label.AI_Chat_Confirm_Action_Default, card.confirmationMessage, 'The default confirmation text should be the Custom Label.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Define an input schema with several property types
            String schema = '{"properties":{"due_date":{"type":"string","format":"date"},"count":{"type":"integer","title":"How many"},"notes":{"type":"string","maxLength":1000,"description":"Anything"},"flag":{"type":"boolean"},"name":{}},"required":["name"]}';

            // [2] Build the input fields for valid, malformed and blank schemas
            List<AIChatDataStructure.ActionInputField> fields;
            List<AIChatDataStructure.ActionInputField> malformedFields;
            List<AIChatDataStructure.ActionInputField> blankFields;

            Test.startTest();
                fields = AIChatActionService.buildInputFields(schema);
                malformedFields = AIChatActionService.buildInputFields('{not json');
                blankFields = AIChatActionService.buildInputFields(null);
            Test.stopTest();

            // [3] Index the built fields by name
            Map<String, AIChatDataStructure.ActionInputField> byName = new Map<String, AIChatDataStructure.ActionInputField>();
            for (AIChatDataStructure.ActionInputField field : fields)
            byName.put(field.name, field);

            // [4] Check the field types, labels and required flags
            Assert.areEqual('date', byName.get('due_date').inputType, 'A date format should become a date field.');
            Assert.areEqual('number', byName.get('count').inputType, 'An integer should become a number field.');
            Assert.areEqual('How many', byName.get('count').label, 'The schema title should become the label.');
            Assert.areEqual('textarea', byName.get('notes').inputType, 'A long string should become a text area.');
            Assert.areEqual('checkbox', byName.get('flag').inputType, 'A boolean should become a checkbox.');

            Assert.isTrue(byName.get('name').required && byName.get('name').label == 'Name', 'A required property should be required, with a humanised label.');
            Assert.areEqual(0, malformedFields.size() + blankFields.size(), 'A malformed or blank schema should give no fields.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and a chat user with the user permission set
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, 'AIAssistUser');

            // [2] Create the user settings and UI settings
            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, false)[0];
            AIAssistTestDataFactory.upsertUiSettings(true);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert settings; }

            // [3] Create a workflow action and link it to the agent
            AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIWorkflowActionDispatcherTest.EchoExecutor', true)[0];
            action.InputSchema__c = '{"properties":{"x":{}}}';
            update action;

            AIAssistTestDataFactory.createAIAgentWorkflowActions(agent.Id, new List<AIWorkflowAction__c>{ action }, true);

            // [4] Create a conversation and an AI reply that suggests the action
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, false)[0];
            reply.SuggestedWorkflowAction__c = action.Id;
            AIMessagingDataService.insertOrThrow(new List<SObject>{ reply });

            // [5] Run the suggested action as the chat user
            AIChatDataStructure.ActionResult ran;

            System.runAs(chatUser) {
                AIConversationMessage__c loaded = AIChatConversationService.getOwnedAgentMessage(reply.Id);

                Test.startTest();
                    ran = AIChatActionService.runSuggestedAction(loaded, '{"x":"hi"}', true);
                Test.stopTest();
            }

            // [6] Check the action ran and returned its output
            Assert.isTrue(ran.isSuccess, 'The suggested action should run.');
            Assert.areEqual('echo:hi', ran.message, 'The result should carry the action output.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation and an AI reply with no suggested action
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            AIConversationMessage__c reply = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 5, 1, true)[0];
            AIConversationMessage__c loaded = AIChatConversationService.getOwnedAgentMessage(reply.Id);

            // [2] Try to run the suggested action
            String shown;

            Test.startTest();
                try {
                    AIChatActionService.runSuggestedAction(loaded, null, true);
                } catch (AIChatActionService.AIChatActionServiceException ex) {
                    shown = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the refusal message
            Assert.isNotNull(shown, 'A reply with no suggested action should not run.');
            Assert.areEqual(Label.AI_Error_Action_Not_Permitted, shown, 'The refusal should be the not-permitted Custom Label.');
        }
    }
}
