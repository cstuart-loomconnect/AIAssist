/*
Class Name: AIMessageValidatorTest

=================================================================
=================================================================

Description: Testing utility for AIMessageValidator: every reason a user can be refused when sending a message, as a real end user holding only the AI Assist User permission set.

=================================================================
=================================================================
Applicable Classes:

AIMessageValidator: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIMessageValidatorTest {

    // testScenario1: An open agent and an acceptable message are validated -> the request is allowed and the context carries the user, the agent and the user's settings.
    // testScenario2: A message is validated while the application is switched off -> it is refused.
    // testScenario3: A message is validated in maintenance mode -> it is refused.
    // testScenario4: A blank, null, over-length and exactly-at-the-limit message are validated -> the first three are refused and the last is allowed.
    // testScenario5: A missing, mistyped, deleted and inactive agent are validated -> all are refused, all but the inactive one as plain 'not available'.
    // testScenario6: Agents are validated as a user who is and is not assigned -> an Assigned Users Only agent is closed until assigned by name or permission set, and an open agent needs no assignment.
    // testScenario7: Users who never accepted, accepted an earlier version and accepted the current version are validated -> the first two are refused and the last is allowed.
    // testScenario8: An undefined channel, a channel outside the allow-list, one on the list and none are validated -> the first two are refused and the last two are allowed.
    // testScenario9: Chats about a record are validated -> an owned record is allowed and a mismatched object name, an unreadable record and an unsupported object are refused.

    private static final String ALLOWED = 'ALLOWED';
    private static final String MESSAGE_BODY = 'Hello';
    private static final String PERMISSION_SET_NAME = 'AIAssistUser';
    private static final String UNDEFINED_CHANNEL = 'Carrier Pigeon';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a chat user with the permission set, an open agent and the user's settings
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{ chatUser }, PERMISSION_SET_NAME);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistTestDataFactory.createAIUserSettings(chatUser.Id, true);

            AIMessageValidator.ChatContext context;

            // [2] Validate an acceptable message as the chat user
            Test.startTest();
                System.runAs(chatUser) {

                    context = AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, null, null);
                }
            Test.stopTest();

            // [3] Check the context carries the user, the agent and the user's settings
            Assert.areEqual(chatUser.Id, context.userId, 'The context should carry the user.');
            Assert.areEqual(agent.Id, context.agent.Id, 'The context should carry the agent.');
            Assert.isNotNull(context.userSettings, 'The context should carry the user\'s settings.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and switch the application off
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.IsEnabled__c = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            String outcome;

            // [2] Validate a message and keep the refusal
            Test.startTest();
                try {

                    AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, null, null, null);
                    outcome = ALLOWED;

                } catch (AIMessageValidator.AIMessageValidatorException ex) {

                    outcome = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the message was refused
            Assert.areEqual(Label.AI_Error_Application_Inactive, outcome, 'A switched-off application should refuse with the Custom Label.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and switch maintenance mode on
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIAssistUISettings__c uiSettings = AIAssistUISettings__c.getOrgDefaults();
            uiSettings.IsMaintenanceMode__c = true;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { upsert uiSettings; }

            String outcome;

            // [2] Validate a message and keep the refusal
            Test.startTest();
                try {

                    AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, null, null, null);
                    outcome = ALLOWED;

                } catch (AIMessageValidator.AIMessageValidatorException ex) {

                    outcome = ex.getMessage();
                }
            Test.stopTest();

            // [3] Check the message was refused
            Assert.areEqual(Label.AI_Error_Maintenance_Mode, outcome, 'Maintenance mode should refuse with the Custom Label.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an agent and a message exactly at the length limit
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];
            String atTheLimit = 'x'.repeat(AIAssistApplicationConstants.MAX_USER_MESSAGE_CHARACTERS);
            List<String> outcomes = new List<String>();

            // [2] Validate a blank, a null, an over-length and an at-the-limit message
            Test.startTest();
                for (String body : new List<String>{
                    '   ',
                    null,
                    atTheLimit + 'x',
                    atTheLimit
                }) {

                    try {

                        AIMessageValidator.validateSendRequest(agent.Id, body, null, null, null);
                        outcomes.add(ALLOWED);

                    } catch (AIMessageValidator.AIMessageValidatorException ex) {

                        outcomes.add(ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check the first three are refused and the last is allowed
            Assert.areEqual(Label.AI_Error_Message_Empty, outcomes[0], 'A blank message should be refused.');
            Assert.areEqual(Label.AI_Error_Message_Empty, outcomes[1], 'A null message should be refused.');
            Assert.areEqual(Label.AI_Error_Message_Too_Long, outcomes[2], 'A message one over the limit should be refused.');

            Assert.areEqual(ALLOWED, outcomes[3], 'A message exactly at the limit should be allowed.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an inactive agent and a deleted agent
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, true);

            agents[0].IsActive__c = false;
            update agents[0];

            Id deletedId = agents[1].Id;
            delete agents[1];

            Map<Id, String> outcomeByAgentId = new Map<Id, String>();

            // [2] Validate a message for the inactive agent, the deleted agent, a wrong-type Id and no Id
            Test.startTest();
                for (Id agentId : new List<Id>{
                    agents[0].Id,
                    deletedId,
                    UserInfo.getUserId(),
                    null
                }) {

                    try {

                        AIMessageValidator.validateSendRequest(agentId, MESSAGE_BODY, null, null, null);
                        outcomeByAgentId.put(agentId, ALLOWED);

                    } catch (AIMessageValidator.AIMessageValidatorException ex) {

                        outcomeByAgentId.put(agentId, ex.getMessage());
                    }
                }
            Test.stopTest();

            // [3] Check all are refused, all but the inactive one as not available
            Assert.areEqual(Label.AI_Error_Agent_Inactive, outcomeByAgentId.get(agents[0].Id), 'An inactive agent should be refused as inactive.');

            Assert.areEqual(Label.AI_Error_Agent_Not_Available, outcomeByAgentId.get(deletedId), 'A deleted agent should be refused as not available.');
            Assert.areEqual(Label.AI_Error_Agent_Not_Available, outcomeByAgentId.get(UserInfo.getUserId()), 'An Id of the wrong type should be refused the same way.');
            Assert.areEqual(Label.AI_Error_Agent_Not_Available, outcomeByAgentId.get(null), 'No Id at all should be refused the same way.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with the permission set
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, PERMISSION_SET_NAME);

            // [2] Create three Assigned Users Only agents and one open agent
            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(4, model.Id, false);

            agents[0].AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            agents[1].AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            agents[2].AccessMode__c = AIAssistApplicationConstants.ACCESS_MODE_ASSIGNED_ONLY;
            insert agents;

            // [3] Assign the second agent to the first user by name and the third agent by permission set
            AIAssistTestDataFactory.createAIAgentAssignments(agents[1].Id, new List<User>{ users[0] }, null, true);
            AIAssistTestDataFactory.createAIAgentAssignments(agents[2].Id, null, PERMISSION_SET_NAME, true);
            Map<Id, String> outcomeByAgentId = new Map<Id, String>();

            // [4] Validate a message for each agent as the first user
            Test.startTest();
                System.runAs(users[0]) {

                    for (AIAgent__c agent : agents) {

                        try {

                            AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, null, null, null);
                            outcomeByAgentId.put(agent.Id, ALLOWED);

                        } catch (AIMessageValidator.AIMessageValidatorException ex) {

                            outcomeByAgentId.put(agent.Id, ex.getMessage());
                        }
                    }
                }
            Test.stopTest();

            // [5] Check the unassigned agent is closed and the others are allowed
            Assert.areEqual(Label.AI_Error_Agent_Not_Assigned, outcomeByAgentId.get(agents[0].Id), 'An agent nobody is assigned to should be closed.');

            Assert.areEqual(ALLOWED, outcomeByAgentId.get(agents[1].Id), 'An agent assigned by name should be allowed.');
            Assert.areEqual(ALLOWED, outcomeByAgentId.get(agents[2].Id), 'An agent assigned by permission set should be allowed.');
            Assert.areEqual(ALLOWED, outcomeByAgentId.get(agents[3].Id), 'An agent open to all users should be allowed.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create three users with the permission set and an open agent
            List<User> users = AIAssistTestDataFactory.createUsers(3, true);
            AIAssistTestDataFactory.assignPermissionSet(users, PERMISSION_SET_NAME);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            // [2] Set the current terms version to v2
            AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
            settings.CurrentTermsVersion__c = 'v2';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update settings; }
            AIAssistSettingsService.cachedSettings = null;

            // [3] Let the second user accept v1 and the third user accept v2
            System.runAs(users[1]) {

                insert AIAssistTestDataFactory.createAITermsAcknowledgments(users[1].Id, 'v1', 1, false);
            }
            System.runAs(users[2]) {

                insert AIAssistTestDataFactory.createAITermsAcknowledgments(users[2].Id, 'v2', 1, false);
            }

            List<String> outcomes = new List<String>();

            // [4] Validate a message as each user
            Test.startTest();
                for (User user : users) {

                    System.runAs(user) {

                        try {

                            AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, null, null, null);
                            outcomes.add(ALLOWED);

                        } catch (AIMessageValidator.AIMessageValidatorException ex) {

                            outcomes.add(ex.getMessage());
                        }
                    }
                }
            Test.stopTest();

            // [5] Check the first two users are refused and the last is allowed
            Assert.areEqual(Label.AI_Error_Terms_Not_Acknowledged, outcomes[0], 'A user who never accepted should be refused.');
            Assert.areEqual(Label.AI_Error_Terms_Version_Changed, outcomes[1], 'A user who accepted an earlier version should be refused.');
            Assert.areEqual(ALLOWED, outcomes[2], 'A user who accepted the current version should be allowed.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with the permission set, an open agent and a mobile-only channel allow-list
            List<User> users = AIAssistTestDataFactory.createUsers(1, true);
            AIAssistTestDataFactory.assignPermissionSet(users, PERMISSION_SET_NAME);

            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, true)[0];

            AIUserSettings__c settings = AIAssistTestDataFactory.createAIUserSettings(users[0].Id, false)[0];
            settings.AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert settings; }

            Map<String, String> outcomeByChannel = new Map<String, String>();

            // [2] Validate a message on an undefined channel, an unlisted channel, a listed channel and no channel
            Test.startTest();
                System.runAs(users[0]) {

                    for (String channel : new List<String>{
                        UNDEFINED_CHANNEL,
                        AIAssistApplicationConstants.CHANNEL_UTILITY_BAR,
                        AIAssistApplicationConstants.CHANNEL_MOBILE,
                        ''
                    }) {

                        try {

                            AIMessageValidator.validateSendRequest(agent.Id, MESSAGE_BODY, channel, null, null);
                            outcomeByChannel.put(channel, ALLOWED);

                        } catch (AIMessageValidator.AIMessageValidatorException ex) {

                            outcomeByChannel.put(channel, ex.getMessage());
                        }
                    }
                }
            Test.stopTest();

            // [3] Check the first two are refused and the last two are allowed
            Assert.areEqual(Label.AI_Error_Channel_Not_Allowed, outcomeByChannel.get(UNDEFINED_CHANNEL), 'An undefined channel should be refused before it fails on the restricted picklist.');
            Assert.areEqual(Label.AI_Error_Channel_Not_Allowed, outcomeByChannel.get(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR), 'A channel outside the allow-list should be refused.');

            Assert.areEqual(ALLOWED, outcomeByChannel.get(AIAssistApplicationConstants.CHANNEL_MOBILE), 'A channel on the allow-list should be allowed.');
            Assert.areEqual(ALLOWED, outcomeByChannel.get(''), 'No channel supplied should be unrestricted.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create two users with the permission set and two agents, the second built for Contact
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, PERMISSION_SET_NAME);

            AIModelConfiguration__c model = AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0];
            List<AIAgent__c> agents = AIAssistTestDataFactory.createAIAgents(2, model.Id, false);
            agents[1].ObjectApiNames__c = 'Contact';
            insert agents;

            // [2] Create an account owned by the first user and a conversation owned by the second
            Account ownAccount;
            System.runAs(users[0]) {

                ownAccount = AIAssistTestDataFactory.createAccounts(1, true)[0];
            }

            AIConversation__c theirConversation = AIAssistTestDataFactory.createAIConversations(agents[0].Id, users[1].Id, 1, true)[0];

            List<String> outcomes = new List<String>();

            // [3] Validate five chats about records as the first user, matching the order of the checks below
            List<Id> agentIds = new List<Id>{
                agents[0].Id,
                agents[0].Id,
                agents[0].Id,
                agents[0].Id,
                agents[1].Id
            };
            List<String> objectNames = new List<String>{
                'Account',
                null,
                'Contact',
                'AIConversation__c',
                'Account'
            };
            List<Id> recordIds = new List<Id>{
                ownAccount.Id,
                ownAccount.Id,
                ownAccount.Id,
                theirConversation.Id,
                ownAccount.Id
            };

            Test.startTest();
                System.runAs(users[0]) {

                    for (Integer index = 0; index < agentIds.size(); index++) {

                        try {

                            AIMessageValidator.validateSendRequest(agentIds[index], MESSAGE_BODY, null, objectNames[index], recordIds[index]);
                            outcomes.add(ALLOWED);

                        } catch (AIMessageValidator.AIMessageValidatorException ex) {

                            outcomes.add(ex.getMessage());
                        }
                    }
                }
            Test.stopTest();

            // [4] Check the owned record is allowed and the mismatched, unreadable and unsupported ones are refused
            Assert.areEqual(ALLOWED, outcomes[0], 'The user should be able to chat about their own record.');
            Assert.areEqual(ALLOWED, outcomes[1], 'A blank object name should be filled in from the Id.');

            Assert.areEqual(Label.AI_Error_Record_Access_Denied, outcomes[2], 'An object name that does not match the Id should be refused.');
            Assert.areEqual(Label.AI_Error_Record_Access_Denied, outcomes[3], 'Another user\'s private conversation should be refused as a record this user cannot see.');
            Assert.areEqual(Label.AI_Error_Agent_Not_Available, outcomes[4], 'An agent built for Contact should not be offered for an Account.');
        }
    }
}
