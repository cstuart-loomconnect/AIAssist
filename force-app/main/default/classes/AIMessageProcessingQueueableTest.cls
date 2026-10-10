/*
Class Name: AIMessageProcessingQueueableTest

=================================================================
=================================================================

Description: Testing utility for AIMessageProcessingQueueable: the asynchronous turn. The provider's HTTP endpoint is mocked, so these tests prove what the job loads, bounds, records and reports.

=================================================================
=================================================================
Applicable Classes:

AIMessageProcessingQueueable: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessageProcessingQueueableTest {

    // testScenario1: A turn is run -> it loads the conversation and agent, calls the provider with the question as the history, and records the reply.
    // testScenario2: A turn is run with many messages -> the history is bounded by message count, ends with the question being answered even when newer messages exist, and leaves out System messages.
    // testScenario3: A turn is run with very large messages -> the history is also bounded by characters, keeping the newest message whatever its size.
    // testScenario4: A turn is run after the lock has gone -> the job stands down without calling the provider or writing anything.
    // testScenario5: A turn is run for a message deleted after it was queued -> it is reported to the chat window without a failure record or an exception.
    // testScenario6: A turn gets a failed provider result -> it is recorded as a failed turn with its reason.
    // testScenario7: A turn is run for an agent with no model configuration -> it is logged and recorded as a configuration error.
    // testScenario8: A turn gets a retryable provider failure -> nothing is recorded yet because the finalizer retries it as a new job.
    // testScenario9: A retryable turn is run as a real job -> the finalizer retries it as a second attempt that answers, and the lock is freed.
    // testScenario10: The user ran a Suggested Action from an earlier reply, and another failed -> the history notes both on the replies they ran from, other messages are untouched, and nothing is saved.
    // testScenario11: The question asks for one of the agent's templates and another is the default -> the reply is answered with, and records, the template that was asked for and its version.
    // testScenario12: The question asks for no template and the agent has a default and another template -> the reply records the default.
    // testScenario13: The question asks for a template that has since been deactivated -> the default answers instead and the reply records it.
    // testScenario14: A turn on the Anthropic Agent API for a conversation with no saved session -> the new session id is saved on the conversation and the reply is recorded.
    // testScenario15: A turn on the Anthropic Agent API for a conversation whose saved session is gone -> a new session answers and its id replaces the saved one.
    // testScenario16: A turn on a stateless provider for a conversation with no saved session -> nothing is saved on the conversation.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the echo provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ECHO);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the reply and the answered question
        AIConversationMessage__c reply = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
        AIConversationMessage__c answeredQuestion = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        // [6] Check the reply echoes the question and the question is Complete
        Assert.areEqual('1|Test message 0', reply.MessageBody__c, 'The history should be the question alone.');
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE, answeredQuestion.ProcessingStatus__c, 'The question should be Complete.');
    }

    @IsTest static void testScenario2() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Add more older messages than the history allows, a newer message and System messages
        List<AIConversationMessage__c> older = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, AIAssistApplicationConstants.MAX_HISTORY_MESSAGES + 10, true);
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true);
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_SYSTEM, 10, 3, true);

        // [4] Install the echo provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ECHO);

        // [5] Run the job for the last older message
        Test.startTest();
            new AIMessageProcessingQueueable(older[older.size() - 1].Id, conversation.Id).execute(null);
        Test.stopTest();

        // [6] Read the reply
        AIConversationMessage__c reply = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [7] Check the history is capped and ends with the message being answered
        Assert.areEqual(AIAssistApplicationConstants.MAX_HISTORY_MESSAGES + '|' + older[older.size() - 1].MessageBody__c, reply.MessageBody__c, 'The history should be capped, and end with the message being answered, not the newer one.');
    }

    @IsTest static void testScenario3() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Add three messages that together exceed the character budget
        Integer half = (AIAssistApplicationConstants.MAX_HISTORY_CHARACTERS / 2) + 1;
        List<AIConversationMessage__c> big = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 3, false);
        for (AIConversationMessage__c message : big) {

            message.MessageBody__c = 'x'.repeat(half);
        }
        insert big;

        // [4] Install the echo provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ECHO);

        // [5] Run the job for the newest large message
        Test.startTest();
            new AIMessageProcessingQueueable(big[2].Id, conversation.Id).execute(null);
        Test.stopTest();

        // [6] Read the reply
        AIConversationMessage__c reply = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [7] Check only the newest message fitted in the history
        Assert.isTrue(reply.MessageBody__c.startsWith('1|'), 'Only the newest message should fit within the character budget.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation, then release it so the lock has gone
        AIConversationLockService.acquireLock(conversation.Id);
        AIConversationLockService.releaseLock(conversation.Id);

        // [3] Install the answering provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Count the messages written and the platform logs
        Integer writtenCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c != :AIAssistApplicationConstants.SENDER_USER];
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [6] Check nothing was written, the provider was not called and nothing was logged
        Assert.areEqual(0, writtenCount, 'There should be no reply and no failure record.');
        Assert.areEqual(0, AIAssistTestProviderMock.callCount, 'The provider should never have been called.');
        Assert.areEqual(0, logCount, 'Standing down should not be logged as a fault.');
    }

    @IsTest static void testScenario5() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Delete the question after it was queued
        Id deletedId = question.Id;
        delete question;

        // [4] Install the answering provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [5] Run the job for the deleted question
        Test.startTest();
            new AIMessageProcessingQueueable(deletedId, conversation.Id).execute(null);
        Test.stopTest();

        // [6] Count the messages left in the conversation
        Integer messageCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id];

        // [7] Check nothing was written and the provider was not called
        Assert.areEqual(0, messageCount, 'Nothing should have been written.');
        Assert.areEqual(0, AIAssistTestProviderMock.callCount, 'The provider should never have been called.');
    }

    @IsTest static void testScenario6() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the failing provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_FAIL);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the question back
        AIConversationMessage__c failed = [SELECT ProcessingStatus__c, FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];

        // [6] Check the question failed with a provider error
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, failed.ProcessingStatus__c, 'The question should have failed.');
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, failed.FailureReason__c, 'The failure reason should be a provider error.');
    }

    @IsTest static void testScenario7() {

        // [1] Create a chat user, an agent with no model configuration, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, null, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the answering provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the question back and count the platform logs
        AIConversationMessage__c failed = [SELECT ProcessingStatus__c, FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c];

        // [6] Check the question failed with a configuration error, was logged and the provider was not called
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, failed.ProcessingStatus__c, 'The question should have failed.');
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_CONFIGURATION_ERROR, failed.FailureReason__c, 'A setup problem should be a configuration error.');

        Assert.isTrue(logCount >= 1, 'The setup problem should have been logged.');
        Assert.areEqual(0, AIAssistTestProviderMock.callCount, 'The provider should never have been called.');
    }

    @IsTest static void testScenario8() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the provider that fails in a retryable way
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_RETRY);

        // [4] Note the status of the question before the run
        String statusBefore = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :question.Id].ProcessingStatus__c;

        // [5] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [6] Read the status again and count the messages written
        String statusAfter = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :question.Id].ProcessingStatus__c;
        Integer writtenCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c != :AIAssistApplicationConstants.SENDER_USER];

        // [7] Check the question is untouched and nothing was written
        Assert.areEqual(statusBefore, statusAfter, 'The question should be untouched: still waiting for its retry.');
        Assert.areEqual(0, writtenCount, 'Nothing else should have been written.');
    }

    @IsTest static void testScenario9() {

        // [1] Create a chat user, an agent, a conversation and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the provider that fails once then answers
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_RETRY);

        // [4] Enqueue the job so the finalizer can retry it
        Test.startTest();
            System.enqueueJob(new AIMessageProcessingQueueable(question.Id, conversation.Id));
        Test.stopTest();

        // [5] Read the replies and check whether the conversation is still locked
        List<AIConversationMessage__c> replies = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
        Boolean isLocked = AIConversationLockService.isConversationLocked(conversation.Id);

        // [6] Check the retry answered once and the lock is freed
        Assert.areEqual(1, replies.size(), 'There should be one reply.');
        Assert.areEqual(2, AIAssistTestProviderMock.callCount, 'The provider should have been called twice: the failed attempt and the retry.');
        Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, replies[0].MessageBody__c, 'The reply should come from the second attempt.');

        Assert.isFalse(isLocked, 'The conversation should be free again.');
    }

    @IsTest static void testScenario10() {

        // [1] Create a chat user, an agent, a conversation and an action
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIWorkflowAction__c action = AIAssistTestDataFactory.createAIWorkflowActions(1, AIAssistApplicationConstants.WORKFLOW_ACTION_TYPE_APEX, 'AIAssistTestAction', true)[0];

        // [2] Add three replies and a question
        List<AIConversationMessage__c> replies = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_AI_AGENT, 0, 3, true);
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [3] Record one success and one failure, leaving the third reply without an action
        AIExecutionStepRecorder.recordWorkflowActionStep(replies[0].Id, action, null, AIAssistApplicationConstants.EXECUTION_STEP_STATUS_SUCCESS, false, 1);
        AIExecutionStepRecorder.recordWorkflowActionStep(replies[1].Id, action, null, AIAssistApplicationConstants.EXECUTION_STEP_STATUS_FAILED, false, 1);

        // [4] Add the notes to the history in memory
        List<AIConversationMessage__c> history = [SELECT Id, MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id ORDER BY CreatedDate, Id];
        Map<Id, String> originalBodies = new Map<Id, String>();
        for (AIConversationMessage__c historyMessage : history) originalBodies.put(historyMessage.Id, historyMessage.MessageBody__c);

        Test.startTest();
            AIMessageProcessingQueueable.appendActionOutcomes(history);
        Test.stopTest();

        // [5] Check the notes are on the replies the actions ran from, and nowhere else
        Map<Id, AIConversationMessage__c> historyById = new Map<Id, AIConversationMessage__c>(history);

        Assert.isTrue(historyById.get(replies[0].Id).MessageBody__c.contains('"' + action.ActionName__c + '"') && historyById.get(replies[0].Id).MessageBody__c.contains('completed successfully'), 'The successful action should be noted on its reply.');
        Assert.isTrue(historyById.get(replies[1].Id).MessageBody__c.contains('failed'), 'The failed action should be noted on its reply.');

        Assert.areEqual(originalBodies.get(replies[2].Id), historyById.get(replies[2].Id).MessageBody__c, 'A reply with no action should be untouched.');
        Assert.areEqual(originalBodies.get(question.Id), historyById.get(question.Id).MessageBody__c, 'The question should be untouched.');

        // [6] Check nothing was saved
        for (AIConversationMessage__c savedMessage : [SELECT Id, MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id]) {

            Assert.areEqual(originalBodies.get(savedMessage.Id), savedMessage.MessageBody__c, 'The saved message body should not change.');
        }
    }

    @IsTest static void testScenario11() {

        // [1] Create a chat user, an agent with a default template and another template, a conversation and a question that asks for the other template
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
        templates[0].IsDefault__c = true;
        insert templates;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false)[0];
        question.AIPromptTemplate__c = templates[1].Id;
        insert question;

        // [2] Lock the conversation and install the answering provider
        AIConversationLockService.acquireLock(conversation.Id);
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [3] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [4] Read the reply and the template it was answered with
        AIConversationMessage__c reply = [SELECT AIPromptTemplate__c, PromptTemplateVersion__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];
        AIPromptTemplate__c askedFor = [SELECT Version__c FROM AIPromptTemplate__c WHERE Id = :templates[1].Id];

        // [5] Check the reply records the template that was asked for
        Assert.areEqual(templates[1].Id, reply.AIPromptTemplate__c, 'The reply should record the template that was asked for, not the default.');
        Assert.areEqual(askedFor.Version__c, reply.PromptTemplateVersion__c, 'The reply should record that template\'s version.');
    }

    @IsTest static void testScenario12() {

        // [1] Create a chat user, an agent with a default template and another template, a conversation and a question that asks for nothing
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
        templates[1].IsDefault__c = true;
        insert templates;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation and install the answering provider
        AIConversationLockService.acquireLock(conversation.Id);
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [3] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [4] Read the reply
        AIConversationMessage__c reply = [SELECT AIPromptTemplate__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [5] Check the reply records the default
        Assert.areEqual(templates[1].Id, reply.AIPromptTemplate__c, 'The reply should record the default template.');
    }

    @IsTest static void testScenario13() {

        // [1] Create a chat user, an agent with a default template and another template, a conversation and a question that asks for the other one
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        List<AIPromptTemplate__c> templates = AIAssistTestDataFactory.createAIPromptTemplates(agent.Id, 2, false);
        templates[0].IsDefault__c = true;
        insert templates;

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false)[0];
        question.AIPromptTemplate__c = templates[1].Id;
        insert question;

        // [2] Deactivate the template that was asked for, lock the conversation and install the answering provider
        templates[1].IsActive__c = false;
        update templates[1];

        AIConversationLockService.acquireLock(conversation.Id);
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [3] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [4] Read the reply
        AIConversationMessage__c reply = [SELECT AIPromptTemplate__c, ProcessingStatus__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [5] Check the default answered
        Assert.areEqual(templates[0].Id, reply.AIPromptTemplate__c, 'The default should answer when the asked-for template is no longer active.');
    }

    @IsTest static void testScenario14() {

        // [1] Create a chat user, an Anthropic Agent API model, an agent, a conversation with no saved session and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
        model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
        model.EnvironmentId__c = 'env_1';
        model.ApiPath__c = '/v1/sessions';
        insert model;

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the Anthropic Agent API provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_AGENT);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the conversation and the reply
        AIConversation__c savedConversation = [SELECT ExternalReference__c FROM AIConversation__c WHERE Id = :conversation.Id];
        AIConversationMessage__c reply = [SELECT MessageBody__c FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [6] Check the session id was saved and the reply recorded
        Assert.areEqual(AIAssistTestProviderMock.SESSION_ID_NEW, savedConversation.ExternalReference__c, 'The new session id should be saved on the conversation.');
        Assert.areEqual(AIAssistTestProviderMock.REPLY_TEXT, reply.MessageBody__c, 'The agent\'s reply should be recorded.');
    }

    @IsTest static void testScenario15() {

        // [1] Create a chat user, an Anthropic Agent API model, an agent, a conversation whose saved session no longer exists and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, false)[0];
        model.AIProvider__c = AIAssistApplicationConstants.AI_PROVIDER_ANTHROPIC_AGENT;
        model.EnvironmentId__c = 'env_1';
        model.ApiPath__c = '/v1/sessions';
        insert model;

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, model.Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, false)[0];
        conversation.ExternalReference__c = 'sesn_gone';
        insert conversation;
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the Anthropic Agent API provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_AGENT);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the conversation
        AIConversation__c savedConversation = [SELECT ExternalReference__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [6] Check the new session id replaced the saved one
        Assert.areEqual(AIAssistTestProviderMock.SESSION_ID_NEW, savedConversation.ExternalReference__c, 'The new session id should replace the one that no longer exists.');
    }

    @IsTest static void testScenario16() {

        // [1] Create a chat user, a stateless model, an agent, a conversation with no saved session and the question
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];
        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];

        // [2] Lock the conversation
        AIConversationLockService.acquireLock(conversation.Id);

        // [3] Install the stateless provider
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        // [4] Run the job for the question
        Test.startTest();
            new AIMessageProcessingQueueable(question.Id, conversation.Id).execute(null);
        Test.stopTest();

        // [5] Read the conversation
        AIConversation__c savedConversation = [SELECT ExternalReference__c FROM AIConversation__c WHERE Id = :conversation.Id];

        // [6] Check nothing was saved on the conversation
        Assert.isNull(savedConversation.ExternalReference__c, 'A stateless provider should save no reference.');
    }
}
