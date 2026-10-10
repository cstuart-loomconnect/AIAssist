/*
Class Name: AIMessageProcessingFinalizerTest

=================================================================
=================================================================

Description: Testing utility for AIMessageProcessingFinalizer: what must always happen when a turn ends: release or hand on the lock, retry, and tell the chat window when nothing else can.

=================================================================
=================================================================
Applicable Classes:

AIMessageProcessingFinalizer: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessageProcessingFinalizerTest {

    // testScenario1: A turn that ended normally with nothing waiting is finalized -> the lock is released.
    // testScenario2: A newer message that arrived during the turn is finalized -> it is handed the lock, queued and answered.
    // testScenario3: A requested retry is finalized -> the same message is queued again with the tokens so far and the conversation stays locked.
    // testScenario4: A job that started after its lock expired is finalized -> the turn is failed as a timeout and the lock is left alone.
    // testScenario5: A retry cannot be queued -> the turn is failed as a provider error and the lock is released.
    // testScenario6: The waiting message cannot be queued -> the lock is released and the failure is logged.
    // testScenario7: Null tokens are recorded and the turn context is requested -> tokens are zero and the context holds the turn's details.
    // testScenario8: A conversation that has been deleted is finalized -> the finalizer does not throw.

    private static final String FINALIZER_CLASS_NAME = 'AIMessageProcessingFinalizer';

    // Fills the asynchronous queue so the finalizer cannot add to it.
    private class IdleJob implements Queueable {

        public void execute(QueueableContext context) {
        }
    }

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create a conversation with a locked turn and a finalizer for it
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);

        // [2] Run the finalizer
        Test.startTest();
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        Boolean isLocked = AIConversationLockService.isConversationLocked(conversation.Id);

        // [4] Check the outcome
        Assert.isFalse(isLocked, 'The lock should be released.');
    }

    @IsTest static void testScenario2() {

        // [1] Create a locked turn, a newer waiting message, a mock provider and a finalizer
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIConversationMessage__c newer = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);

        // [2] Run the finalizer
        Test.startTest();
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c newerAfter = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :newer.Id];

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_COMPLETE, newerAfter.ProcessingStatus__c, 'The waiting message should be picked up and answered.');
    }

    @IsTest static void testScenario3() {

        // [1] Create a locked turn, a mock provider and a finalizer with a retry requested
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);
        AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);
        finalizer.scheduleRetry(40, 10);

        Boolean lockedAfterFinalizer;

        // [2] Run the finalizer
        Test.startTest();
            finalizer.execute(null);
            // the lock must be read before Test.stopTest runs the retry and releases it
            lockedAfterFinalizer = AIConversationLockService.isConversationLocked(conversation.Id);
        Test.stopTest();

        // [3] Read the results back
        Integer replyCount = [SELECT COUNT() FROM AIConversationMessage__c WHERE AIConversation__c = :conversation.Id AND Sender__c = :AIAssistApplicationConstants.SENDER_AI_AGENT];

        // [4] Check the outcome
        Assert.isTrue(lockedAfterFinalizer, 'The lock should be kept for the retry.');
        Assert.areEqual(40, finalizer.inputTokens, 'The tokens should be carried.');
        Assert.areEqual(1, replyCount, 'The retry should run and answer.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a locked turn and a finalizer whose lock has expired
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);
        finalizer.markLockExpired();

        // [2] Run the finalizer
        Test.startTest();
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c questionAfter = [SELECT FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];
        Boolean isLocked = AIConversationLockService.isConversationLocked(conversation.Id);

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_TIMEOUT, questionAfter.FailureReason__c, 'The turn should be failed as a timeout.');
        Assert.isTrue(isLocked, 'The lock should be left for whoever holds it now.');
    }

    @IsTest static void testScenario5() {

        // [1] Create a locked turn and a finalizer with a retry requested
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);
        finalizer.scheduleRetry(10, 5);

        // [2] Fill the queue with idle jobs then run the finalizer
        Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {

                System.enqueueJob(new IdleJob());
            }
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        AIConversationMessage__c questionAfter = [SELECT FailureReason__c FROM AIConversationMessage__c WHERE Id = :question.Id];
        Boolean isLocked = AIConversationLockService.isConversationLocked(conversation.Id);

        // [4] Check the outcome
        Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_PROVIDER_ERROR, questionAfter.FailureReason__c, 'The turn should end as failed.');
        Assert.isFalse(isLocked, 'The lock should be freed.');
    }

    @IsTest static void testScenario6() {

        // [1] Create a locked turn with a newer waiting message and a finalizer
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);
        AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);

        // [2] Fill the queue with idle jobs then run the finalizer
        Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {

                System.enqueueJob(new IdleJob());
            }
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        Boolean isLocked = AIConversationLockService.isConversationLocked(conversation.Id);
        Integer logCount = [SELECT COUNT() FROM AIPlatformLog__c WHERE ClassName__c = :FINALIZER_CLASS_NAME];

        // [4] Check the outcome
        Assert.isFalse(isLocked, 'The lock should be freed, not left behind a job nobody queued.');
        Assert.isTrue(logCount >= 1, 'The failure should be logged.');
    }

    @IsTest static void testScenario7() {

        // [1] Create a locked turn and a finalizer with no starting tokens
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, null, chatUser.Id);

        AIMessageOutcomeService.AIResponseContext responseContext;

        // [2] Record null tokens and ask for the turn context
        Test.startTest();
            finalizer.recordTokensSpent(null, null);
            responseContext = finalizer.getResponseContext();
        Test.stopTest();

        // [3] Check the outcome
        Assert.areEqual(0, finalizer.inputTokens + finalizer.outputTokens, 'Null tokens should be recorded as none.');
        Assert.areEqual(conversation.Id, responseContext.conversationId, 'The context should hold the conversation.');
        Assert.areEqual(question.Id, responseContext.triggeringMessageId, 'The context should hold the triggering message.');
        Assert.areEqual(chatUser.Id, responseContext.userId, 'The context should hold the user.');
    }

    @IsTest static void testScenario8() {

        // [1] Create a locked turn and a finalizer, then delete the conversation
        User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

        AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

        AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, chatUser.Id, 1, true)[0];

        AIConversationMessage__c question = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, true)[0];
        AIConversationLockService.acquireLock(conversation.Id);

        AIMessageProcessingFinalizer finalizer = new AIMessageProcessingFinalizer(question.Id, conversation.Id, 1, chatUser.Id);
        delete conversation;

        // [2] Run the finalizer
        Test.startTest();
            finalizer.execute(null);
        Test.stopTest();

        // [3] Read the results back
        Integer conversationCount = [SELECT COUNT() FROM AIConversation__c WHERE Id = :conversation.Id];

        // [4] Check the outcome
        Assert.areEqual(0, conversationCount, 'The conversation should still be gone and the finalizer should not have thrown.');
    }
}
