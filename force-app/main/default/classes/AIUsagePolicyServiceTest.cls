/*
Class Name: AIUsagePolicyServiceTest

=================================================================
=================================================================

Description: Testing utility for AIUsagePolicyService: how a user's own settings row and the usage policies that apply to them combine into what they are allowed.

=================================================================
=================================================================
Applicable Classes:

AIUsagePolicyService: Coverage TBC

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

@IsTest private class AIUsagePolicyServiceTest {

    // testScenario1: With no row and no policy the answer is null; an inactive row counts as no row -> null for each.
    // testScenario2: With policies only, limits take the lowest value, the behavior that blocks most, and the widest visibility -> lowest limits, strictest behavior, widest scope.
    // testScenario3: Capabilities add up: a flag, or a channel, allowed by any policy is allowed, and a policy with no channels opens every channel -> combined channels and flags, null channels when open.
    // testScenario4: The numeric limits come from the policy only, and the user row's behavior wins where it is set and falls through to the policy where it is blank -> limits from the policy, own behavior wins.
    // testScenario5: A user row can switch a capability on, but cannot switch off one a policy grants -> row switches export on, policy keeps debug on.
    // testScenario6: New chats follow the user's row when they have one, otherwise any policy that allows them -> the row's off beats a policy's on, a policy allows when there is no row.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create an inactive user row
            AIUserSettings__c inactiveRow = new AIUserSettings__c(IsActive__c = false, DebugModeEnabled__c = true);

            // [2] Resolve with no row, an empty list and the inactive row
            Test.startTest();
                AIUserSettings__c nothing = AIUsagePolicyService.resolve(null, null);
                AIUserSettings__c emptyList = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>());
                AIUserSettings__c inactiveResult = AIUsagePolicyService.resolve(inactiveRow, null);
                AIUsagePolicy__c noLimits = AIUsagePolicyService.resolveUsageLimits(null, new List<AIUsagePolicy__c>());
            Test.stopTest();

            // [3] Check each answer is null
            Assert.isNull(nothing, 'No row and no policy means no personal limits.');
            Assert.isNull(emptyList, 'An empty list is the same.');
            Assert.isNull(inactiveResult, 'An inactive row is ignored.');
            Assert.isNull(noLimits, 'With no policy there are no limits.');
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
                AIUserSettings__c resolved = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ loose, strict, middle });
                AIUsagePolicy__c limits = AIUsagePolicyService.resolveUsageLimits(null, new List<AIUsagePolicy__c>{ loose, strict, middle });
            Test.stopTest();

            // [3] Check the lowest limits, strictest behavior and widest scope win
            Assert.areEqual(2, limits.MaxConcurrentConversations__c, 'The lowest.');
            Assert.areEqual(20, limits.MaxConversationsPer24Hours__c, 'The lowest that is set; a blank limit sets nothing.');
            Assert.areEqual(100000, limits.MaxTokensPer24Hours__c, 'The lowest.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES, limits.UsageLimitReachedBehavior__c, 'The behavior that blocks most.');
            Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL, resolved.ConversationVisibilityScope__c, 'The widest scope.');
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
                AIUserSettings__c both = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ first, second });
                AIUserSettings__c open = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ first, unrestricted });
            Test.stopTest();

            // [3] Split the combined channels
            Set<String> channels = new Set<String>(both.AllowedChannels__c.split(';'));

            // [4] Check channels and flags add up and an open policy allows every channel
            Assert.isTrue(channels.contains(AIAssistApplicationConstants.CHANNEL_MOBILE) && channels.contains(AIAssistApplicationConstants.CHANNEL_UTILITY_BAR), 'Channels allowed by either policy.');

            Assert.isTrue(both.ShouldCaptureExecutionSteps__c, 'Granted by the first.');
            Assert.isTrue(both.DebugModeEnabled__c, 'Granted by the second.');
            Assert.isFalse(both.ConversationExportEnabled__c, 'Granted by neither.');

            Assert.isNull(open.AllowedChannels__c, 'A policy with no list allows every channel.');
            Assert.isTrue(open.ConversationExportEnabled__c, 'Granted by that policy.');
        }
    }

    @IsTest static void testScenario4() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy and a user row that overrides some of its values
            AIUsagePolicy__c groupPolicy = new AIUsagePolicy__c(MaxConcurrentConversations__c = 3, MaxConversationsPer24Hours__c = 50, MaxTokensPer24Hours__c = 200000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);
            AIUserSettings__c row = new AIUserSettings__c(IsActive__c = true, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY);

            // [2] Resolve the row with the policy
            Test.startTest();
                AIUsagePolicy__c limits = AIUsagePolicyService.resolveUsageLimits(row, new List<AIUsagePolicy__c>{ groupPolicy });
                AIUsagePolicy__c limitsWithoutRow = AIUsagePolicyService.resolveUsageLimits(null, new List<AIUsagePolicy__c>{ groupPolicy });
            Test.stopTest();

            // [3] Check the limits come from the policy and the row's behavior wins where it is set
            Assert.areEqual(200000, limits.MaxTokensPer24Hours__c, 'The numeric limits come from the policy, never from the user\'s row.');
            Assert.areEqual(3, limits.MaxConcurrentConversations__c, 'The numeric limits come from the policy, never from the user\'s row.');
            Assert.areEqual(50, limits.MaxConversationsPer24Hours__c, 'The numeric limits come from the policy, never from the user\'s row.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY, limits.UsageLimitReachedBehavior__c, 'The user\'s own behavior wins.');
            Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES, limitsWithoutRow.UsageLimitReachedBehavior__c, 'With no row, the behavior comes from the policy.');
        }
    }

    @IsTest static void testScenario5() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy that grants capabilities and a row that tries to switch one off
            AIUsagePolicy__c grants = new AIUsagePolicy__c(DebugModeEnabled__c = true, ShouldCaptureExecutionSteps__c = true);
            AIUserSettings__c row = new AIUserSettings__c(IsActive__c = true, DebugModeEnabled__c = false, ConversationExportEnabled__c = true);

            // [2] Resolve the row with the policy
            Test.startTest();
                AIUserSettings__c resolved = AIUsagePolicyService.resolve(row, new List<AIUsagePolicy__c>{ grants });
            Test.stopTest();

            // [3] Check the row cannot remove a granted capability
            Assert.isTrue(resolved.DebugModeEnabled__c, 'An unticked box on the row does not take away what the policy grants.');
            Assert.isTrue(resolved.ConversationExportEnabled__c, 'A ticked box on the row switches it on for that user.');
            Assert.isTrue(resolved.ShouldCaptureExecutionSteps__c, 'From the policy.');
        }
    }

    @IsTest static void testScenario6() {

        User superUser = AIAssistTestDataFactory.createSuperUser();

        System.runAs(superUser) {
            // [1] Create a policy that allows new chats, a row that turns them off, and a row that leaves them on
            AIUsagePolicy__c allows = new AIUsagePolicy__c(IsUserInitiatedChatEnabled__c = true);
            AIUsagePolicy__c blocks = new AIUsagePolicy__c(IsUserInitiatedChatEnabled__c = false);
            AIUserSettings__c pausedRow = new AIUserSettings__c(IsActive__c = true, IsUserInitiatedChatEnabled__c = false);
            AIUserSettings__c openRow = new AIUserSettings__c(IsActive__c = true, IsUserInitiatedChatEnabled__c = true);

            // [2] Resolve each combination
            Test.startTest();
                AIUserSettings__c rowOffPolicyOn = AIUsagePolicyService.resolve(pausedRow, new List<AIUsagePolicy__c>{ allows });
                AIUserSettings__c rowOnPolicyOff = AIUsagePolicyService.resolve(openRow, new List<AIUsagePolicy__c>{ blocks });
                AIUserSettings__c noRowPolicyOn = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ blocks, allows });
                AIUserSettings__c noRowPolicyOff = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ blocks });
            Test.stopTest();

            // [3] Check the row decides when there is one, and the policies decide when there is not
            Assert.isFalse(rowOffPolicyOn.IsUserInitiatedChatEnabled__c, 'The row turning new chats off beats a policy allowing them.');
            Assert.isTrue(rowOnPolicyOff.IsUserInitiatedChatEnabled__c, 'The row allowing new chats beats a policy that does not.');
            Assert.isTrue(noRowPolicyOn.IsUserInitiatedChatEnabled__c, 'With no row, one allowing policy is enough.');
            Assert.isFalse(noRowPolicyOff.IsUserInitiatedChatEnabled__c, 'With no row and no allowing policy, new chats are off.');
        }
    }
}
