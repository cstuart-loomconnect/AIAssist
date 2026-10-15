/*
Class Name: AIConversationShareServiceTest

=================================================================
=================================================================

Description: Testing utility for AIConversationShareService: sharing a conversation read-only with individual users, finding who it can be shared with, and taking a share back.

=================================================================
=================================================================
Applicable Classes:

AIConversationShareService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIConversationShareServiceTest {

    // testScenario1: The starter shares a Global-agent conversation with an eligible user -> a Read DirectShare row exists, the recipient has the title as subtitle, and sharing again adds no second row.
    // testScenario2: A recipient with no title shows the role name and one with neither shows a blank subtitle, and getShares lists them by name.
    // testScenario3: Sharing is refused for a Private agent, with oneself, with a user no usage policy applies to, with an inactive user, with a missing user and for someone else's conversation.
    // testScenario4: A conversation already shared with 25 users refuses a 26th, and still accepts the same user again.
    // testScenario5: Searching needs two characters, escapes wildcards, and leaves out the starter, shared users, inactive users and users who hold no AI Assist permission set, and returns at most ten.
    // testScenario6: Unsharing removes only that user's row, does nothing for an unshared user, and is refused for a non-owner.
    // testScenario7: A non-owner cannot list shares or search, and the lookup methods answer from the share rows.

    private static final String AGENT_VISIBILITY_PRIVATE = 'Private';
    private static final String AGENT_VISIBILITY_GLOBAL = 'Global';

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, the starter's conversation and a user who can open the window
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            User recipientUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            recipientUser.Title = 'Head of Testing';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update recipientUser; }

            AIChatDataStructure.ShareRecipient first;
            AIChatDataStructure.ShareRecipient second;

            // [2] Share it twice with the same user
            Test.startTest();
                first = AIConversationShareService.shareConversation(conversation.Id, recipientUser.Id);
                second = AIConversationShareService.shareConversation(conversation.Id, recipientUser.Id);
            Test.stopTest();

            // [3] Read the share rows
            List<AIConversation__Share> shareRows = [SELECT UserOrGroupId, AccessLevel, RowCause FROM AIConversation__Share WHERE ParentId = :conversation.Id AND UserOrGroupId = :recipientUser.Id];

            // [4] Check one Read DirectShare row exists and the recipient is described
            Assert.areEqual(1, shareRows.size(), 'Sharing twice should leave one share row.');
            Assert.areEqual('Read', shareRows[0].AccessLevel, 'The share should be read-only.');
            Assert.areEqual(Schema.AIConversation__Share.RowCause.DirectShare__c, shareRows[0].RowCause, 'The share should use the DirectShare reason.');
            Assert.areEqual(recipientUser.Id, first.userId, 'The recipient should be the user.');
            Assert.areEqual('Head of Testing', first.subtitle, 'The subtitle should be the title.');
            Assert.areEqual(first.userId, second.userId, 'Sharing again should give the same recipient.');
            Assert.isTrue(AIConversationShareService.hasDirectShare(conversation.Id, recipientUser.Id), 'The user should have a direct share.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, a conversation and two users: one with a role only, one with neither title nor role
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> recipients = AIAssistTestDataFactory.createUsers(2, false);
            recipients[0].LastName = 'Aaa Role';
            recipients[1].LastName = 'Bbb Plain';

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {
                UserRole role = new UserRole(Name = 'AI Assist Share Role');
                insert role;
                recipients[0].UserRoleId = role.Id;
                insert recipients;
            }

            List<AIChatDataStructure.ShareRecipient> shares;

            // [2] Share with both and list the shares
            Test.startTest();
                AIConversationShareService.shareConversation(conversation.Id, recipients[1].Id);
                AIConversationShareService.shareConversation(conversation.Id, recipients[0].Id);
                shares = AIConversationShareService.getShares(conversation.Id);
            Test.stopTest();

            // [3] Check the order and the subtitles
            Assert.areEqual(2, shares.size(), 'Both users should be listed.');
            Assert.areEqual(recipients[0].Id, shares[0].userId, 'The shares should be listed by name.');
            Assert.areEqual('AI Assist Share Role', shares[0].subtitle, 'With no title the role name should be the subtitle.');
            Assert.areEqual('', shares[1].subtitle, 'With neither title nor role the subtitle should be blank.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global and a Private agent, conversations on each, and an eligible user, a user no policy applies to and an inactive user
            AIAgent__c globalAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            globalAgent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert globalAgent;

            AIAgent__c privateAgent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            privateAgent.ConversationVisibility__c = AGENT_VISIBILITY_PRIVATE;
            insert privateAgent;

            AIConversation__c onGlobal = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, UserInfo.getUserId(), 1, true)[0];
            AIConversation__c onPrivate = AIAssistTestDataFactory.createAIConversations(privateAgent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(4, true);
            AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(globalAgent.Id, users[3].Id, 1, true)[0];
            users[2].IsActive = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update users[2]; }
            AIAssistTestDataFactory.deactivateUsagePolicies();
            AIAssistTestDataFactory.createAIUsagePolicyForUser(users[0].Id, new AIUsagePolicy__c());

            List<String> refusals = new List<String>();

            // [2] Try each sharing that must be refused
            Test.startTest();
                try { AIConversationShareService.shareConversation(onPrivate.Id, users[0].Id); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(onGlobal.Id, UserInfo.getUserId()); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(onGlobal.Id, users[1].Id); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(onGlobal.Id, users[2].Id); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(onGlobal.Id, null); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(onGlobal.Id, onGlobal.Id); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusals.add(ex.getMessage()); }
                try { AIConversationShareService.shareConversation(theirs.Id, users[0].Id); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
            Test.stopTest();

            // [3] Check each refusal and that nothing was shared
            Assert.areEqual(Label.AI_Error_Share_Not_Global, refusals[0], 'A Private agent should not be shared.');
            Assert.areEqual(Label.AI_Error_Share_Self, refusals[1], 'Sharing with oneself should be refused.');
            Assert.areEqual(Label.AI_Error_Share_User_Ineligible, refusals[2], 'A user no usage policy applies to should be refused.');
            Assert.areEqual(Label.AI_Error_Share_User_Ineligible, refusals[3], 'An inactive user should be refused.');
            Assert.areEqual(Label.AI_Error_Share_User_Ineligible, refusals[4], 'A missing user should be refused.');
            Assert.areEqual(Label.AI_Error_Share_User_Ineligible, refusals[5], 'An Id that is not a user should be refused.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[6], 'Someone else\'s conversation should be not found.');
            Assert.areEqual(0, [SELECT COUNT() FROM AIConversation__Share WHERE RowCause = :Schema.AIConversation__Share.RowCause.DirectShare__c], 'Nothing should have been shared.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, a conversation and 26 users, 25 of them already shared with
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(26, true);
            List<AIConversation__Share> shareRows = new List<AIConversation__Share>();

            for (Integer index = 0; index < users.size(); index++) {

                if (index < 25) shareRows.add(new AIConversation__Share(ParentId = conversation.Id, UserOrGroupId = users[index].Id, AccessLevel = 'Read', RowCause = Schema.AIConversation__Share.RowCause.DirectShare__c));
            }

            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert shareRows; }

            String refusal;
            AIChatDataStructure.ShareRecipient again;

            // [2] Share with a 26th user, and again with one already shared with
            Test.startTest();
                try { AIConversationShareService.shareConversation(conversation.Id, users[25].Id); } catch (AIConversationShareService.AIConversationShareServiceException ex) { refusal = ex.getMessage(); }
                again = AIConversationShareService.shareConversation(conversation.Id, users[0].Id);
            Test.stopTest();

            // [3] Check the limit holds but an existing share is still accepted
            Assert.areEqual(Label.AI_Error_Share_Limit, refusal, 'A 26th share should be refused.');
            Assert.areEqual(users[0].Id, again.userId, 'Sharing again with a shared user should still answer.');
            Assert.areEqual(25, [SELECT COUNT() FROM AIConversation__Share WHERE ParentId = :conversation.Id AND RowCause = :Schema.AIConversation__Share.RowCause.DirectShare__c], 'There should still be 25 shares.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, a conversation and 14 users named Zqsearch, with different states
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(14, false);

            for (Integer index = 0; index < users.size(); index++) users[index].LastName = 'Zqsearch ' + (index < 10 ? '0' : '') + index;

            users[13].LastName = 'Zqsearch %_ 13';
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { insert users; }

            List<User> permittedUsers = new List<User>();

            for (Integer index = 0; index < users.size(); index++) {

                if (index != 11) permittedUsers.add(users[index]);
            }

            AIAssistTestDataFactory.assignPermissionSet(permittedUsers, AIAssistApplicationConstants.PERMISSION_SET_USER);
            users[10].IsActive = false;
            System.runAs(AIAssistTestDataFactory.getSetupUser()) { update users[10]; }

            AIConversationShareService.shareConversation(conversation.Id, users[0].Id);

            List<AIChatDataStructure.ShareRecipient> tooShort;
            List<AIChatDataStructure.ShareRecipient> blank;
            List<AIChatDataStructure.ShareRecipient> found;
            List<AIChatDataStructure.ShareRecipient> wildcard;
            List<AIChatDataStructure.ShareRecipient> literal;
            List<AIChatDataStructure.ShareRecipient> starter;

            // [2] Search with short, blank, normal, wildcard and literal text
            Test.startTest();
                tooShort = AIConversationShareService.searchShareableUsers(conversation.Id, 'Z');
                blank = AIConversationShareService.searchShareableUsers(conversation.Id, null);
                found = AIConversationShareService.searchShareableUsers(conversation.Id, 'zqsearch');
                wildcard = AIConversationShareService.searchShareableUsers(conversation.Id, 'Z%h 1');
                literal = AIConversationShareService.searchShareableUsers(conversation.Id, '%_ 13');
                starter = AIConversationShareService.searchShareableUsers(conversation.Id, superUser.LastName);
            Test.stopTest();

            // [3] Check the results
            Set<Id> foundIds = new Set<Id>();
            for (AIChatDataStructure.ShareRecipient foundUser : found) foundIds.add(foundUser.userId);

            Set<Id> starterIds = new Set<Id>();
            for (AIChatDataStructure.ShareRecipient starterUser : starter) starterIds.add(starterUser.userId);

            Assert.isTrue(tooShort.isEmpty(), 'One character should find nothing.');
            Assert.isTrue(blank.isEmpty(), 'No text should find nothing.');
            Assert.areEqual(10, found.size(), 'At most ten users should come back.');
            Assert.isFalse(foundIds.contains(users[0].Id), 'A user already shared with should be left out.');
            Assert.isFalse(foundIds.contains(users[10].Id), 'An inactive user should be left out.');
            Assert.isFalse(foundIds.contains(users[11].Id), 'A user with no AI Assist permission set should be left out.');
            Assert.isTrue(wildcard.isEmpty(), 'A percent sign should not act as a wildcard.');
            Assert.areEqual(1, literal.size(), 'A percent sign and underscore should match themselves.');
            Assert.areEqual(users[13].Id, literal[0].userId, 'The literal match should be the user with those characters.');
            Assert.isFalse(starterIds.contains(UserInfo.getUserId()), 'The starter should never be offered.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, a conversation shared with two users, and another user's conversation
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(3, true);
            AIConversation__c theirs = AIAssistTestDataFactory.createAIConversations(agent.Id, users[2].Id, 1, true)[0];
            AIConversationShareService.shareConversation(conversation.Id, users[0].Id);
            AIConversationShareService.shareConversation(conversation.Id, users[1].Id);

            String refusal;

            // [2] Unshare one user, an unshared user, and try someone else's conversation
            Test.startTest();
                AIConversationShareService.unshareConversation(conversation.Id, users[0].Id);
                AIConversationShareService.unshareConversation(conversation.Id, users[2].Id);
                AIConversationShareService.unshareConversation(conversation.Id, null);

                try { AIConversationShareService.unshareConversation(theirs.Id, users[0].Id); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusal = ex.getMessage(); }
            Test.stopTest();

            // [3] Check only the one row went
            Assert.isFalse(AIConversationShareService.hasDirectShare(conversation.Id, users[0].Id), 'The unshared user should lose the share.');
            Assert.isTrue(AIConversationShareService.hasDirectShare(conversation.Id, users[1].Id), 'The other share should stay.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusal, 'A non-owner should be refused with not found.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a Global agent, a conversation shared with one user, and a user who is not the starter
            AIAgent__c agent = AIAssistTestDataFactory.createAIAgents(1, AIAssistTestDataFactory.createAIModelConfigurations(1, true)[0].Id, false)[0];
            agent.ConversationVisibility__c = AGENT_VISIBILITY_GLOBAL;
            insert agent;

            AIConversation__c conversation = AIAssistTestDataFactory.createAIConversations(agent.Id, UserInfo.getUserId(), 1, true)[0];
            List<User> users = AIAssistTestDataFactory.createUsers(2, true);
            AIAssistTestDataFactory.assignPermissionSet(users, AIAssistApplicationConstants.PERMISSION_SET_USER);
            AIConversationShareService.shareConversation(conversation.Id, users[0].Id);

            List<String> refusals = new List<String>();
            Set<Id> sharedWith;
            Set<Id> sharedWithOther;

            // [2] Ask as the user it is shared with, who is not the starter
            Test.startTest();
                System.runAs(users[0]) {
                    try { AIConversationShareService.getShares(conversation.Id); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
                    try { AIConversationShareService.searchShareableUsers(conversation.Id, 'Assist'); } catch (AIChatConversationService.AIChatConversationServiceException ex) { refusals.add(ex.getMessage()); }
                }

                sharedWith = AIConversationShareService.getConversationIdsSharedWith(users[0].Id, 10);
                sharedWithOther = AIConversationShareService.getConversationIdsSharedWith(users[1].Id, 10);
            Test.stopTest();

            // [3] Check the refusals and the lookups
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[0], 'A non-owner should not list the shares.');
            Assert.areEqual(Label.AI_Error_Conversation_Not_Found, refusals[1], 'A non-owner should not search.');
            Assert.areEqual(new Set<Id>{ conversation.Id }, sharedWith, 'The shared user should have the conversation.');
            Assert.isTrue(sharedWithOther.isEmpty(), 'An unshared user should have none.');
        }
    }
}
