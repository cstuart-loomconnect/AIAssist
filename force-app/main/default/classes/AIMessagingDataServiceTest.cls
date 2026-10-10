/*
Class Name: AIMessagingDataServiceTest

=================================================================
=================================================================

Description: Testing utility for AIMessagingDataService: the system-mode writes, and the marker that tells the message trigger a write is trusted.

=================================================================
=================================================================
Applicable Classes:

AIMessagingDataService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessagingDataServiceTest {

    // testScenario1: insertOrThrow and updateOrThrow write in system mode (null and empty lists do nothing) -> the AI Agent messages and the update are saved and the trusted-write marker is clear afterwards.
    // testScenario2: insertOrThrow and updateOrThrow are given records that fail -> each throws the generic label and the trusted-write marker is still cleared.
    // testScenario3: insertAndLogFailures, updateAndLogFailures are given a batch with one bad record, and a null list -> nothing throws, the good records are saved and the bad one is logged.

    private static final String TEST_CLASS_NAME = 'AIMessagingDataServiceTest';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation and two unsaved AI Agent messages
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 7, 2, false);

            // [2] Insert, update, and call both with null and empty lists
            Test.startTest();
                AIMessagingDataService.insertOrThrow(messages);
                messages[0].ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_FAILED;
                AIMessagingDataService.updateOrThrow(new List<SObject>{ messages[0] });

                AIMessagingDataService.insertOrThrow(null);
                AIMessagingDataService.updateOrThrow(new List<SObject>());
            Test.stopTest();

            // [3] Count the saved messages and read the updated one
            Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
            AIConversationMessage__c updatedMessage = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :messages[0].Id];

            // [4] Check the writes were saved and the trusted-write marker is clear
            Assert.areEqual(2, messageCount, 'The AI Agent messages were written, which only AIMessagingDataService may do.');
            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, updatedMessage.ProcessingStatus__c, 'The update was written.');
            Assert.isFalse(AIMessagingDataService.isTrustedWrite(), 'The marker is clear once the write is done.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Build a message with no conversation and an agent with an invalid value
            AIConversationMessage__c orphan = AIAssistTestDataFactory.createAIConversationMessages(null, AIAssistApplicationConstants.SENDER_AI_AGENT, 1, 1, false)[0];

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];
            agent.ConversationRetentionDays__c = -1;

            String insertMessage;
            String updateMessage;

            // [2] Insert and update them, catching the exception each throws
            Test.startTest();
                // The service throws by design here, so the exception is caught to read its message.
                try {

                    AIMessagingDataService.insertOrThrow(new List<SObject>{ orphan });

                } catch (AIMessagingDataService.AIMessagingDataServiceException ex) {

                    insertMessage = ex.getMessage();
                }

                try {

                    AIMessagingDataService.updateOrThrow(new List<SObject>{ agent });

                } catch (AIMessagingDataService.AIMessagingDataServiceException ex) {

                    updateMessage = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check both threw the generic label and the marker is clear
            Assert.areEqual(Label.AI_Error_Generic, insertMessage, 'An insert with no parent conversation should throw, and the user sees only the generic label.');
            Assert.areEqual(Label.AI_Error_Generic, updateMessage, 'An update the object model refuses should throw, and the user sees only the generic label.');
            Assert.isFalse(AIMessagingDataService.isTrustedWrite(), 'A failed write must not leave the marker set, or a user insert later in the transaction could forge a sender.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent, a conversation and two unsaved System messages
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, null, 1, true)[0];
            List<AIConversationMessage__c> messages = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 3, 2, false);

            // [2] Add a message with no conversation to the batch
            AIConversationMessage__c orphan = AIAssistTestDataFactory.createAIConversationMessages(null, AIAssistApplicationConstants.SENDER_SYSTEM, 3, 1, false)[0];
            messages.add(orphan);

            // [3] Insert and update with failures logged, then insert a null list
            Test.startTest();
                AIMessagingDataService.insertAndLogFailures(messages, TEST_CLASS_NAME, 'testScenario3');
                AIMessagingDataService.updateAndLogFailures(new List<SObject>{ new AIConversationMessage__c(Id = messages[0].Id) }, TEST_CLASS_NAME, 'testScenario3');
                AIMessagingDataService.insertAndLogFailures(null, TEST_CLASS_NAME, 'testScenario3');
            Test.stopTest();

            // [4] Count the saved messages and the platform logs
            Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id];
            Integer platformLogCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = :TEST_CLASS_NAME];

            // [5] Check the good records were saved and the bad one was logged
            Assert.areEqual(2, messageCount, 'The records that could be saved were saved.');
            Assert.areEqual(1, platformLogCount, 'The one that could not was logged.');
        }
    }
}
