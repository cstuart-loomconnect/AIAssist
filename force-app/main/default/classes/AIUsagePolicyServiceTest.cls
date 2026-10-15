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
}
