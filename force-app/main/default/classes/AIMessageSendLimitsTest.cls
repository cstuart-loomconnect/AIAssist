/*
Class Name: AIMessageSendLimitsTest

=================================================================
=================================================================

Description: Tests the limits applied when a message is sent, all set on AIAssistSettings__c: the cap on messages in flight (extra messages wait and are started when a place is free), the per-user messages-per-minute limit and the maximum message length.

=================================================================
=================================================================
Applicable Classes:

AIConversationMessageService: Coverage TBC
AIUsageLimitService: Coverage TBC
AIMessageValidator: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessageSendLimitsTest {

    // testScenario1: At the cap on messages in flight a new message is kept Queued and waiting, with no job and no lock; under the cap it is started -> only the first message has a job and holds its conversation, the second waits Queued with its conversation unlocked.
    // testScenario2: A waiting message is started by its sender once a place is free, and not while the cap is still reached or by another user -> started once by its sender only, conversation locked and one job queued.
    // testScenario3: A user at the messages-per-minute limit is refused, and another user is not -> the third message is refused with the rate limited label, the other user's first is accepted.
    // testScenario4: A message longer than the configured maximum is refused, and one at the maximum is accepted -> too long label for 21 characters, no refusal for 20.
    // testScenario5: A message that has waited at the cap for longer than the timeout is failed as Service Busy by any user's poll or by the maintenance job, is not started afterwards, and one still inside the timeout is left waiting -> failed as Service Busy, in-timeout message started and not failed.
    // testScenario6: A chat window update does the held-message work only for a conversation that has a message waiting at the cap -> a conversation with none leaves another user's expired waiting message alone, the one with a waiting message reports it held and still processing, and another user's window sees nothing held.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access, an agent and a mock provider
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Set the limit on the settings record
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.put('MaxMessagesInFlight__c', 1);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIConversationMessage__c started;
            AIConversationMessage__c held;
            Integer jobs;

            // [3] Send two messages as the first user and read the state before the job runs
            System.runAs(users[0]) {

                Test.startTest();
                    started = AIConversationMessageService.sendMessage(agent.Id, 'First', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                    held = AIConversationMessageService.sendMessage(agent.Id, 'Second, in another conversation', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

                    jobs = AIUsageLimitService.countQueuedMessageJobs();

                    // Read before stopTest: the queued job runs on stopTest and would release the lock being asserted.
                    started = [SELECT IsAwaitingCapacity__c, AIConversation__r.ProcessingLockedUntil__c FROM AIConversationMessage__c WHERE Id = :started.Id WITH SYSTEM_MODE];
                    held = [SELECT IsAwaitingCapacity__c, ProcessingStatus__c, AIConversation__r.ProcessingLockedUntil__c FROM AIConversationMessage__c WHERE Id = :held.Id WITH SYSTEM_MODE];
                Test.stopTest();
            }

            // [4] Check only the first message was started and the second waits
            Assert.areEqual(1, jobs, 'Only the first message has a job.');
            Assert.isFalse(started.IsAwaitingCapacity__c, 'The first was started.');

            Assert.isNotNull(started.AIConversation__r.ProcessingLockedUntil__c, 'The first holds its conversation.');

            Assert.isTrue(held.IsAwaitingCapacity__c, 'The second waits for a place.');
            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, held.ProcessingStatus__c, 'The second is Queued, not refused.');
            Assert.isNull(held.AIConversation__r.ProcessingLockedUntil__c, 'Nothing is working on the second, so its conversation is not locked.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access, an agent and a mock provider
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Create a conversation with a message waiting for a place
            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 1, true)[0];

            AIConversationMessage__c waiting;
            System.runAs(users[0]) {

                waiting = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false)[0];
                waiting.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
                waiting.IsAwaitingCapacity__c = true;
                AIMessagingDataService.insertOrThrow(new List<SObject>{ waiting });
            }

            Boolean startedByAnother;
            Boolean startedAtTheCap;
            Boolean startedWithRoom;
            Boolean startedTwice;
            Integer jobs;

            // [3] Try to start the waiting message as another user, at the cap, with room, and again
            Test.startTest();
                AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
                settings.put('MaxMessagesInFlight__c', 5);
                System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
                AIAssistSettingsService.cachedSettings = null;

                System.runAs(users[1]) {

                    startedByAnother = AIConversationMessageService.startHeldMessage();
                }
                System.runAs(users[0]) {

                    AIUsageLimitService.inFlightForTest = 5;
                    startedAtTheCap = AIConversationMessageService.startHeldMessage();
                    AIUsageLimitService.inFlightForTest = null;
                    startedWithRoom = AIConversationMessageService.startHeldMessage();
                    startedTwice = AIConversationMessageService.startHeldMessage();
                }

                jobs = AIUsageLimitService.countQueuedMessageJobs();
                // Read before stopTest: the queued job runs on stopTest and would release the lock being asserted.
                waiting = [SELECT IsAwaitingCapacity__c, AIConversation__r.ProcessingLockedUntil__c FROM AIConversationMessage__c WHERE Id = :waiting.Id];
            Test.stopTest();

            // [4] Check it was started once, by its sender only, once a place was free
            Assert.isFalse(startedByAnother, 'Only its sender can start it.');
            Assert.isFalse(startedAtTheCap, 'Not while the cap is still reached.');
            Assert.isTrue(startedWithRoom, 'Started once a place is free.');
            Assert.isFalse(startedTwice, 'And only once.');

            Assert.isFalse(waiting.IsAwaitingCapacity__c, 'No longer waiting.');
            Assert.isNotNull(waiting.AIConversation__r.ProcessingLockedUntil__c, 'Its conversation is locked for the turn.');
            Assert.areEqual(1, jobs, 'One job was queued for it.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access, an agent and a mock provider
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Set the limit on the settings record
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.put('MaxMessagesPerUserPerMinute__c', 2);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            String third;
            String othersFirst;

            // [3] Send three messages as the first user and one as the second user
            Test.startTest();
                System.runAs(users[0]) {

                    AIConversationMessageService.sendMessage(agent.Id, 'One', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                    AIConversationMessageService.sendMessage(agent.Id, 'Two', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                    try {

                        AIConversationMessageService.sendMessage(agent.Id, 'Three', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

                    } catch (Exception refusal) {

                        third = refusal.getMessage();
                    }
                }
                System.runAs(users[1]) {

                    try {

                        AIConversationMessageService.sendMessage(agent.Id, 'One', AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

                    } catch (Exception refusal) {

                        othersFirst = refusal.getMessage();
                    }
                }
            Test.stopTest();

            // [4] Check the third message is refused and the other user is not
            Assert.areEqual(Label.AI_Error_Rate_Limited, third, 'The third message inside a minute is refused.');
            Assert.isNull(othersFirst, 'The limit is per user.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access, an agent and a mock provider
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Set the limit on the settings record
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.put('MaxMessageLength__c', 20);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            String tooLong;
            String atTheMaximum;

            // [3] Send a message one character over the maximum and one at the maximum
            Test.startTest();
                System.runAs(users[0]) {

                    try {

                        AIConversationMessageService.sendMessage(agent.Id, 'x'.repeat(21), AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

                    } catch (Exception refusal) {

                        tooLong = refusal.getMessage();
                    }

                    try {

                        AIConversationMessageService.sendMessage(agent.Id, 'x'.repeat(20), AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);

                    } catch (Exception refusal) {

                        atTheMaximum = refusal.getMessage();
                    }
                }
            Test.stopTest();

            // [4] Check the long message is refused and the other is accepted
            Assert.areEqual(Label.AI_Error_Message_Too_Long, tooLong, 'One character over the configured maximum.');
            Assert.isNull(atTheMaximum, 'At the maximum is accepted.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access, an agent and a mock provider
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Create three conversations each with a waiting message, aging two of them
            List<AIConversation__c> conversations = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 3, true);

            List<AIConversationMessage__c> waiting = new List<AIConversationMessage__c>();
            System.runAs(users[0]) {

                for (AIConversation__c conversation : conversations) {

                    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(conversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false)[0];
                    message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
                    message.IsAwaitingCapacity__c = true;
                    waiting.add(message);
                }
                AIMessagingDataService.insertOrThrow(waiting);
            }

            Datetime longAgo = System.now().addMinutes(-AIAssistApplicationConstants.HELD_MESSAGE_TIMEOUT_MINUTES - 1);
            Test.setCreatedDate(waiting[0].Id, longAgo);
            Test.setCreatedDate(waiting[1].Id, longAgo.addDays(-3));

            // [3] Set the limit on the settings record
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.put('MaxMessagesInFlight__c', 5);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            Boolean startedByAnother;
            Boolean startedBySender;
            Integer failedByMaintenance;
            Map<Id, AIConversationMessage__c> afterPoll;

            // [4] Poll as another user, run the maintenance job, then start as the sender
            Test.startTest();
                AIUsageLimitService.inFlightForTest = 5;

                System.runAs(users[1]) {

                    startedByAnother = AIConversationMessageService.startHeldMessage();
                }

                // The state between the poll and the maintenance job is itself under test, so it is read here.
                afterPoll = new Map<Id, AIConversationMessage__c>([SELECT ProcessingStatus__c, FailureReason__c, IsAwaitingCapacity__c FROM AIConversationMessage__c WHERE Id IN :waiting]);

                failedByMaintenance = AIConversationMessageService.failExpiredHeldMessages(false);
                AIUsageLimitService.inFlightForTest = null;
                System.runAs(users[0]) {

                    startedBySender = AIConversationMessageService.startHeldMessage();
                }
            Test.stopTest();

            // [5] Read the final state of the messages
            Map<Id, AIConversationMessage__c> afterAll = new Map<Id, AIConversationMessage__c>([SELECT ProcessingStatus__c, FailureReason__c, IsAwaitingCapacity__c FROM AIConversationMessage__c WHERE Id IN :waiting]);

            // [6] Check the poll, the maintenance job and the sender each did their part
            Assert.isFalse(startedByAnother, 'Another user starts nothing.');

            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, afterPoll.get(waiting[0].Id).ProcessingStatus__c, 'But their poll fails the message that waited too long.');
            Assert.areEqual(AIAssistApplicationConstants.FAILURE_REASON_SERVICE_BUSY, afterPoll.get(waiting[0].Id).FailureReason__c, 'As busy, which offers Try again.');
            Assert.isFalse(afterPoll.get(waiting[0].Id).IsAwaitingCapacity__c, 'No longer waiting.');

            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, afterPoll.get(waiting[1].Id).ProcessingStatus__c, 'A poll looks at the last day only.');

            Assert.areEqual(1, failedByMaintenance, 'The maintenance job at them all.');
            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, afterAll.get(waiting[1].Id).ProcessingStatus__c, 'The one from three days ago.');

            Assert.isTrue(startedBySender, 'The message inside the timeout started.');
            Assert.isFalse(afterAll.get(waiting[2].Id).IsAwaitingCapacity__c, 'It is the one that was started.');
            Assert.areNotEqual(AIAssistApplicationConstants.PROCESSING_STATUS_FAILED, afterAll.get(waiting[2].Id).ProcessingStatus__c, 'And it was not failed.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with access and an agent
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestProviderMock.install(AIAssistTestProviderMock.KIND_ANSWER);

            // [2] Create a conversation with a waiting message and one without for the first user, and a conversation with an expired waiting message for the second
            AIConversation__c holdingConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 1, true)[0];
            AIConversation__c quietConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[0].Id, 1, true)[0];
            AIConversation__c otherConversation = AIAssistTestDataFactory.createAIConversations(agent.Id, users[1].Id, 1, true)[0];

            List<AIConversationMessage__c> waiting = new List<AIConversationMessage__c>();
            for (Integer index = 0; index < 2; index++) {

                System.runAs(users[index]) {

                    AIConversationMessage__c message = AIAssistTestDataFactory.createAIConversationMessages(index == 0 ? holdingConversation.Id : otherConversation.Id, AIAssistApplicationConstants.SENDER_USER, 0, 1, false)[0];
                    message.ProcessingStatus__c = AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED;
                    message.IsAwaitingCapacity__c = true;
                    AIMessagingDataService.insertOrThrow(new List<SObject>{ message });
                    waiting.add(message);
                }
            }

            Test.setCreatedDate(waiting[1].Id, System.now().addMinutes(-AIAssistApplicationConstants.HELD_MESSAGE_TIMEOUT_MINUTES - 1));

            // [3] Set the limit on the settings record
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.put('MaxMessagesInFlight__c', 5);
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            AIChatDataStructure.ConversationUpdate quietUpdate;
            String otherStatusAfterQuiet;
            AIChatDataStructure.ConversationUpdate holdingUpdate;
            AIChatDataStructure.ConversationUpdate otherUpdate;

            // [4] Update the quiet conversation, then the one holding a message, then the other user's own, with the cap reached
            Test.startTest();
                AIUsageLimitService.inFlightForTest = 5;

                System.runAs(users[0]) {

                    quietUpdate = AIChatController.getConversationUpdate(quietConversation.Id, null);
                }

                // The state after the quiet update is itself under test, so it is read here.
                otherStatusAfterQuiet = [SELECT ProcessingStatus__c FROM AIConversationMessage__c WHERE Id = :waiting[1].Id].ProcessingStatus__c;

                System.runAs(users[0]) {

                    holdingUpdate = AIChatController.getConversationUpdate(holdingConversation.Id, null);
                }

                System.runAs(users[1]) {

                    otherUpdate = AIChatController.getConversationUpdate(otherConversation.Id, null);
                }
            Test.stopTest();

            // [5] Check the quiet update did no held-message work, and the others reported what they hold
            Assert.isFalse(quietUpdate.isHeld, 'Nothing is waiting in the quiet conversation.');
            Assert.areEqual(AIAssistApplicationConstants.PROCESSING_STATUS_QUEUED, otherStatusAfterQuiet, 'So it did not sweep another user\'s expired message.');
            Assert.isTrue(holdingUpdate.isHeld, 'The cap is still reached, so the message is still waiting.');
            Assert.isTrue(holdingUpdate.isProcessing, 'And the window keeps polling.');
            Assert.isFalse(otherUpdate.isHeld, 'The other user\'s message was failed by the sweep, so it is no longer waiting.');
        }
    }
}
