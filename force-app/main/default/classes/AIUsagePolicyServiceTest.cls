/*
Class Name: AIUsagePolicyServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsagePolicyService: how the usage policies that apply to a user combine into what they are allowed.

=================================================================
=================================================================
Applicable Classes:

AIUsagePolicyService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIUsagePolicyServiceTest {

    // testScenario1: Resolving null or an empty list of policies, or looking up a null user -> null for each, and no access.
    // testScenario2: With several policies, limits take the lowest value, the behavior that blocks most, and the widest visibility -> lowest limits, strictest behavior, widest scope.
    // testScenario3: Capabilities add up: a flag, or a channel, allowed by any policy is allowed, and a policy with no channels opens every channel -> combined channels and flags, null channels when open.
    // testScenario4: New chats are allowed when any policy allows them -> one allowing policy is enough, none allowing means off.
    // testScenario5: A user with a policy assigned to them is resolved from that policy and not the default policy -> assigned limits and full access.
    // testScenario6: A user with no assigned policy is resolved from the default policy, and with every policy switched off has no policy and no access -> default limits, then null and no access.
    // testScenario7: A user has a user assignment to a looser policy and a permission set assigned to a stricter one -> the user assignment wins, and the permission set policy is not combined in.
    // testScenario8: A user holds two permission sets with different policies -> only the stricter policy applies, and nothing is borrowed from the other.
    // testScenario9: Policies tie on each limit in turn, and on name -> the lower token limit, then conversation limit, then open conversation limit, then name, then Id decides, and no policies gives null.
    // testScenario10: Candidates are listed for a user with a user assignment, a permission set assignment and the default -> each is marked as a winner or not, and a null user has none.

    // testScenario11: A user holds a permission set group and the group is assigned a policy -> the group policy applies, and so does one assigned to a permission set inside the group.
    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Resolve null, an empty list and a null user
            Test.startTest();
                AIUsagePolicy__c nothing = AIUsagePolicyService.resolvePolicies(null);
                AIUsagePolicy__c emptyList = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>());
                AIUsagePolicy__c noUser = AIUsagePolicyService.getUsagePolicy(null);
                String noUserAccess = AIUsagePolicyService.getAccessLevel(null);
            Test.stopTest();

            // [2] Check each answer is null and the user has no access
            Assert.isNull(nothing, 'No policies means no answer.');
            Assert.isNull(emptyList, 'An empty list is the same.');
            Assert.isNull(noUser, 'No user means no policy.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_NONE, noUserAccess, 'No user means no access.');
        }
    }

    @IsTest static void testScenario2() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create three policies with different limits, behaviors and scopes
            AIUsagePolicy__c loose = new AIUsagePolicy__c(MaxConcurrentConversations__c = 5, MaxConversationsPer24Hours__c = 100, MaxTokensPer24Hours__c = 500000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY);
            loose.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;

            AIUsagePolicy__c strict = new AIUsagePolicy__c(MaxConcurrentConversations__c = 2, MaxTokensPer24Hours__c = 100000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);
            strict.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;

            AIUsagePolicy__c middle = new AIUsagePolicy__c(MaxConversationsPer24Hours__c = 20, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

            // [2] Resolve the policies together
            Test.startTest();
                AIUsagePolicy__c resolved = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>{ loose, strict, middle });
            Test.stopTest();

            // [3] Check the lowest limits, strictest behavior and widest scope win
            Assert.areEqual(2, resolved.MaxConcurrentConversations__c, 'The lowest concurrent limit wins.');
            Assert.areEqual(20, resolved.MaxConversationsPer24Hours__c, 'The lowest limit that is set wins; a blank limit sets nothing.');
            Assert.areEqual(100000, resolved.MaxTokensPer24Hours__c, 'The lowest token limit wins.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES, resolved.UsageLimitReachedBehavior__c, 'The behavior that blocks most wins.');
            Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL, resolved.ConversationVisibilityScope__c, 'The widest scope wins.');
            Assert.isTrue(resolved.IsActive__c, 'The answer is always active.');
        }
    }

    @IsTest static void testScenario3() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create policies with different channels and capabilities
            AIUsagePolicy__c first = new AIUsagePolicy__c(AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE, ShouldCaptureExecutionSteps__c = true);
            AIUsagePolicy__c second = new AIUsagePolicy__c(AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_UTILITY_BAR, DebugModeEnabled__c = true);
            AIUsagePolicy__c unrestricted = new AIUsagePolicy__c(ConversationExportEnabled__c = true);

            // [2] Resolve two restricted policies, then a restricted and an unrestricted one
            Test.startTest();
                AIUsagePolicy__c both = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>{ first, second });
                AIUsagePolicy__c open = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>{ first, unrestricted });
            Test.stopTest();

            // [3] Split the combined channels
            Set<String> channels = new Set<String>(both.AllowedChannels__c.split(';'));

            // [4] Check channels and flags add up and an open policy allows every channel
            Assert.isTrue(channels.contains(AIAssistApplicationConstants.CHANNEL_MOBILE) && channels.contains(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR), 'Channels allowed by either policy are allowed.');
            Assert.isTrue(both.ShouldCaptureExecutionSteps__c, 'Execution step capture is granted by the first policy.');
            Assert.isTrue(both.DebugModeEnabled__c, 'Debug mode is granted by the second policy.');
            Assert.isFalse(both.ConversationExportEnabled__c, 'Export is granted by neither policy.');
            Assert.isNull(open.AllowedChannels__c, 'A policy with no list allows every channel.');
            Assert.isTrue(open.ConversationExportEnabled__c, 'Export is granted by that policy.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy that allows new chats and one that does not
            AIUsagePolicy__c allows = new AIUsagePolicy__c(IsUserInitiatedChatEnabled__c = true);
            AIUsagePolicy__c blocks = new AIUsagePolicy__c(IsUserInitiatedChatEnabled__c = false);

            // [2] Resolve a mix of policies and a policy that does not allow them
            Test.startTest();
                AIUsagePolicy__c mixed = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>{ blocks, allows });
                AIUsagePolicy__c blocked = AIUsagePolicyService.resolvePolicies(new List<AIUsagePolicy__c>{ blocks });
            Test.stopTest();

            // [3] Check one allowing policy is enough
            Assert.isTrue(mixed.IsUserInitiatedChatEnabled__c, 'One allowing policy is enough.');
            Assert.isFalse(blocked.IsUserInitiatedChatEnabled__c, 'With no allowing policy, new chats are off.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user and assign a policy with its own limits and capabilities
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIUsagePolicy__c policyValues = new AIUsagePolicy__c(MaxConcurrentConversations__c = 3, MaxTokensPer24Hours__c = 200000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY, DebugModeEnabled__c = true);
            AIAssistTestDataFactory.createAIUsagePolicyForUser(chatUser.Id, policyValues);

            // [2] Look up the user's policy and access level
            Test.startTest();
                AIUsagePolicy__c resolved = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
                String accessLevel = AIUsagePolicyService.getAccessLevel(chatUser.Id);
            Test.stopTest();

            // [3] Check the assigned policy applies instead of the default
            Assert.areEqual(3, resolved.MaxConcurrentConversations__c, 'The assigned policy sets the concurrent limit.');
            Assert.areEqual(200000, resolved.MaxTokensPer24Hours__c, 'The assigned policy sets the token limit.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY, resolved.UsageLimitReachedBehavior__c, 'The assigned policy sets the behavior.');
            Assert.isTrue(resolved.DebugModeEnabled__c, 'The assigned policy grants debug mode.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_FULL, accessLevel, 'A user with a policy has full access.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user with no assigned policy
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];

            // [2] Look up the user's policy while the default policy is active
            Test.startTest();
                AIUsagePolicy__c defaultResolved = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
                String defaultAccess = AIUsagePolicyService.getAccessLevel(chatUser.Id);
            Test.stopTest();

            // [3] Switch every policy off and look the user up again
            AIAssistTestDataFactory.deactivateUsagePolicies();
            AIUsagePolicy__c noPolicy = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
            String noAccess = AIUsagePolicyService.getAccessLevel(chatUser.Id);

            // [4] Check the default policy covers the user, and without any policy they have none
            Assert.isNotNull(defaultResolved, 'The default policy applies to a user with none assigned.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_FULL, defaultAccess, 'The default policy gives full access.');
            Assert.isNull(noPolicy, 'With every policy switched off there is no policy.');
            Assert.areEqual(AIAssistApplicationConstants.ACCESS_LEVEL_NONE, noAccess, 'With no policy there is no access.');
        }
    }

    @IsTest static void testScenario7() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user holding a permission set, a strict policy for the set and a looser policy for the user
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{chatUser}, 'AIAssistUser');
            AIUsagePolicy__c strict = new AIUsagePolicy__c(Name = 'Strict', IsActive__c = true, MaxTokensPer24Hours__c = 1000, DebugModeEnabled__c = true);
            AIUsagePolicy__c loose = new AIUsagePolicy__c(Name = 'Loose', IsActive__c = true, MaxTokensPer24Hours__c = 900000);
            insert new List<AIUsagePolicy__c>{strict, loose};
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = strict.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = loose.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = chatUser.Id, IsActive__c = true)
            };

            // [2] Look up the user's policy
            Test.startTest();
                AIUsagePolicy__c resolved = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
            Test.stopTest();

            // [3] Check the user assignment won on its own
            Assert.areEqual(900000, resolved.MaxTokensPer24Hours__c, 'The user assignment sets the limit, even though it is looser.');
            Assert.isFalse(resolved.DebugModeEnabled__c, 'Nothing is borrowed from the permission set policy.');
        }
    }

    @IsTest static void testScenario8() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user holding two permission sets, each assigned a different policy
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{chatUser}, 'AIAssistUser');
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{chatUser}, 'AIAssistAdminUser');
            AIUsagePolicy__c strict = new AIUsagePolicy__c(Name = 'Strict', IsActive__c = true, MaxTokensPer24Hours__c = 1000);
            AIUsagePolicy__c loose = new AIUsagePolicy__c(Name = 'Loose', IsActive__c = true, MaxTokensPer24Hours__c = 900000, MaxConcurrentConversations__c = 2, DebugModeEnabled__c = true);
            insert new List<AIUsagePolicy__c>{strict, loose};
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = strict.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = loose.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistAdminUser', IsActive__c = true)
            };

            // [2] Look up the user's policy
            Test.startTest();
                AIUsagePolicy__c resolved = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
            Test.stopTest();

            // [3] Check only the stricter policy applies
            Assert.areEqual(1000, resolved.MaxTokensPer24Hours__c, 'The lower token limit wins.');
            Assert.isNull(resolved.MaxConcurrentConversations__c, 'The other policy limit is not borrowed.');
            Assert.isFalse(resolved.DebugModeEnabled__c, 'The other policy capability is not borrowed.');
        }
    }

    @IsTest static void testScenario9() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create policies that tie on each limit in turn, and two with the same name and limits
            AIUsagePolicy__c tokensLow = new AIUsagePolicy__c(Name = 'Z', MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 5, MaxConcurrentConversations__c = 2);
            AIUsagePolicy__c conversationsLow = new AIUsagePolicy__c(Name = 'Z', MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 3, MaxConcurrentConversations__c = 2);
            AIUsagePolicy__c concurrentLow = new AIUsagePolicy__c(Name = 'Z', MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 3, MaxConcurrentConversations__c = 1);
            AIUsagePolicy__c nameFirst = new AIUsagePolicy__c(Name = 'A', MaxTokensPer24Hours__c = 100, MaxConversationsPer24Hours__c = 3, MaxConcurrentConversations__c = 1);
            AIUsagePolicy__c sameOne = new AIUsagePolicy__c(Name = 'Same');
            AIUsagePolicy__c sameTwo = new AIUsagePolicy__c(Name = 'Same');
            insert new List<AIUsagePolicy__c>{sameOne, sameTwo};
            Id lowerId = String.valueOf(sameOne.Id) < String.valueOf(sameTwo.Id) ? sameOne.Id : sameTwo.Id;

            // [2] Pick the strictest of each set
            Test.startTest();
                AIUsagePolicy__c byConversations = AIUsagePolicyService.getStrictestPolicy(new List<AIUsagePolicy__c>{tokensLow, conversationsLow});
                AIUsagePolicy__c byConcurrent = AIUsagePolicyService.getStrictestPolicy(new List<AIUsagePolicy__c>{conversationsLow, concurrentLow});
                AIUsagePolicy__c byName = AIUsagePolicyService.getStrictestPolicy(new List<AIUsagePolicy__c>{concurrentLow, nameFirst});
                AIUsagePolicy__c byId = AIUsagePolicyService.getStrictestPolicy(new List<AIUsagePolicy__c>{sameTwo, sameOne});
                AIUsagePolicy__c none = AIUsagePolicyService.getStrictestPolicy(new List<AIUsagePolicy__c>());
            Test.stopTest();

            // [3] Check each pick
            Assert.areEqual(3, byConversations.MaxConversationsPer24Hours__c, 'The lower conversation limit wins a tie on tokens.');
            Assert.areEqual(1, byConcurrent.MaxConcurrentConversations__c, 'The lower open conversation limit wins a tie on the others.');
            Assert.areEqual('A', byName.Name, 'The first name wins a tie on every limit.');
            Assert.areEqual(lowerId, byId.Id, 'The lower Id wins a tie on name.');
            Assert.isNull(none, 'No policies means no answer.');
        }
    }

    @IsTest static void testScenario10() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user holding a permission set, with a user assignment and a permission set assignment
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            AIAssistTestDataFactory.assignPermissionSet(new List<User>{chatUser}, 'AIAssistUser');
            AIUsagePolicy__c userPolicy = new AIUsagePolicy__c(Name = 'User policy', IsActive__c = true);
            AIUsagePolicy__c setPolicy = new AIUsagePolicy__c(Name = 'Set policy', IsActive__c = true);
            insert new List<AIUsagePolicy__c>{userPolicy, setPolicy};
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = userPolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, User__c = chatUser.Id, IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = setPolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true)
            };

            // [2] List the candidates
            Test.startTest();
                List<AIUsagePolicyService.PolicyCandidate> candidates = AIUsagePolicyService.getPolicyCandidates(chatUser.Id);
                List<AIUsagePolicyService.PolicyCandidate> noCandidates = AIUsagePolicyService.getPolicyCandidates(null);
            Test.stopTest();

            // [3] Check the user assignment wins, the permission set loses and the default is not needed
            Assert.areEqual(3, candidates.size(), 'The user, the permission set and the default are listed.');
            Assert.isTrue(candidates[0].isWinner && candidates[0].tier == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER, 'The user assignment wins.');
            Assert.isFalse(candidates[1].isWinner, 'The permission set assignment does not win.');
            Assert.areEqual('AIAssistUser', candidates[1].assigneeName, 'The permission set is named.');
            Assert.isFalse(candidates[2].isWinner, 'The default is not needed.');
            Assert.isTrue(noCandidates.isEmpty(), 'No user means no candidates.');
        }
    }

    @IsTest static void testScenario11() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a user who holds a permission set group that contains a permission set
            User chatUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            User otherUser = AIAssistTestDataFactory.createUsers(1, true)[0];
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AIAssistUser' LIMIT 1].Id;
            PermissionSetGroup permissionSetGroup = new PermissionSetGroup(DeveloperName = 'AIPolicyServiceGroup', MasterLabel = 'AI Policy Service Group');

            System.runAs(AIAssistTestDataFactory.getSetupUser()) {

                insert permissionSetGroup;
                insert new PermissionSetGroupComponent(PermissionSetGroupId = permissionSetGroup.Id, PermissionSetId = permissionSetId);
                Test.calculatePermissionSetGroup(permissionSetGroup.Id);
                insert new List<PermissionSetAssignment>{
                    new PermissionSetAssignment(AssigneeId = chatUser.Id, PermissionSetGroupId = permissionSetGroup.Id),
                    new PermissionSetAssignment(AssigneeId = otherUser.Id, PermissionSetGroupId = permissionSetGroup.Id)
                };
            }

            // [2] Assign one policy to the group and another to the permission set inside it, for the other user
            AIUsagePolicy__c groupPolicy = new AIUsagePolicy__c(Name = 'Group policy', IsActive__c = true, MaxTokensPer24Hours__c = 4000);
            AIUsagePolicy__c insidePolicy = new AIUsagePolicy__c(Name = 'Inside policy', IsActive__c = true, MaxTokensPer24Hours__c = 7000);
            insert new List<AIUsagePolicy__c>{groupPolicy, insidePolicy};
            insert new List<AIUsagePolicyAssignment__c>{
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = groupPolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIPolicyServiceGroup', IsActive__c = true),
                new AIUsagePolicyAssignment__c(AIUsagePolicy__c = insidePolicy.Id, AssigneeType__c = AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET, PermissionSetName__c = 'AIAssistUser', IsActive__c = true)
            };

            // [3] Look up the user's policy
            Test.startTest();
                AIUsagePolicy__c resolved = AIUsagePolicyService.getUsagePolicy(chatUser.Id);
            Test.stopTest();

            // [4] Check the stricter of the group policy and the policy of the permission set inside it applies
            Assert.areEqual(4000, resolved.MaxTokensPer24Hours__c, 'The group and the set inside it both count, and the stricter wins.');
        }
    }
}
