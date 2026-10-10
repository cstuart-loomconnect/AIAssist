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
    // testScenario4: The user row overrides a policy where it has a value, and falls through to the policies where it is blank -> own values win, blanks come from the policy.
    // testScenario5: A user row can switch a capability on, but cannot switch off one a policy grants -> row switches export on, policy keeps debug on.

    @TestSetup static void setup() {

        AIAssistSettings__c settings = AIAssistSettings__c.getOrgDefaults();
        settings.IsEnabled__c = true;
        settings.IsExceptionLoggingEnabled__c = true;
        settings.IsPlatformLoggingEnabled__c = true;
        upsert settings;
    }

    @IsTest static void testScenario1() {

        // [1] Create an inactive user row
        AIUserSettings__c inactiveRow = new AIUserSettings__c(IsActive__c = false, DebugModeEnabled__c = true);

        // [2] Resolve with no row, an empty list and the inactive row
        Test.startTest();
            AIUserSettings__c nothing = AIUsagePolicyService.resolve(null, null);
            AIUserSettings__c emptyList = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>());
            AIUserSettings__c inactiveResult = AIUsagePolicyService.resolve(inactiveRow, null);
        Test.stopTest();

        // [3] Check each answer is null
        Assert.isNull(nothing, 'No row and no policy means no personal limits.');
        Assert.isNull(emptyList, 'An empty list is the same.');
        Assert.isNull(inactiveResult, 'An inactive row is ignored.');
    }

    @IsTest static void testScenario2() {

        // [1] Create three policies with different limits, behaviors and scopes
        AIUsagePolicy__c loose = new AIUsagePolicy__c(MaxConcurrentConversations__c = 5, MaxConversationsPer24Hours__c = 100, MaxTokensPer24Hours__c = 500000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY);
        loose.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN;

        AIUsagePolicy__c strict = new AIUsagePolicy__c(MaxConcurrentConversations__c = 2, MaxTokensPer24Hours__c = 100000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);
        strict.ConversationVisibilityScope__c = AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL;

        AIUsagePolicy__c middle = new AIUsagePolicy__c(MaxConversationsPer24Hours__c = 20, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY);

        // [2] Resolve the policies together
        Test.startTest();
            AIUserSettings__c resolved = AIUsagePolicyService.resolve(null, new List<AIUsagePolicy__c>{ loose, strict, middle });
        Test.stopTest();

        // [3] Check the lowest limits, strictest behavior and widest scope win
        Assert.areEqual(2, resolved.MaxConcurrentConversations__c, 'The lowest.');
        Assert.areEqual(20, resolved.MaxConversationsPer24Hours__c, 'The lowest that is set; a blank limit sets nothing.');
        Assert.areEqual(100000, resolved.MaxTokensPer24Hours__c, 'The lowest.');
        Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES, resolved.UsageLimitReachedBehavior__c, 'The behavior that blocks most.');
        Assert.areEqual(AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL, resolved.ConversationVisibilityScope__c, 'The widest scope.');
        Assert.isTrue(resolved.IsActive__c, 'The answer is always active.');
    }

    @IsTest static void testScenario3() {

        // [1] Create policies with different channels and capabilities
        AIUsagePolicy__c first = new AIUsagePolicy__c(AllowedChannels__c = AIAssistApplicationConstants.CHANNEL_MOBILE, WorkflowActionsEnabled__c = true);
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

        Assert.isTrue(both.WorkflowActionsEnabled__c, 'Granted by the first.');
        Assert.isTrue(both.DebugModeEnabled__c, 'Granted by the second.');
        Assert.isFalse(both.ConversationExportEnabled__c, 'Granted by neither.');

        Assert.isNull(open.AllowedChannels__c, 'A policy with no list allows every channel.');
        Assert.isTrue(open.ConversationExportEnabled__c, 'Granted by that policy.');
    }

    @IsTest static void testScenario4() {

        // [1] Create a policy and a user row that overrides some of its values
        AIUsagePolicy__c groupPolicy = new AIUsagePolicy__c(MaxConcurrentConversations__c = 3, MaxConversationsPer24Hours__c = 50, MaxTokensPer24Hours__c = 200000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES);
        AIUserSettings__c row = new AIUserSettings__c(IsActive__c = true, MaxTokensPer24Hours__c = 900000, UsageLimitReachedBehavior__c = AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY);

        // [2] Resolve the row with the policy
        Test.startTest();
            AIUserSettings__c resolved = AIUsagePolicyService.resolve(row, new List<AIUsagePolicy__c>{ groupPolicy });
        Test.stopTest();

        // [3] Check the row wins where set and blanks come from the policy
        Assert.areEqual(900000, resolved.MaxTokensPer24Hours__c, 'The user\'s own value wins, even where it is higher.');
        Assert.areEqual(AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY, resolved.UsageLimitReachedBehavior__c, 'The user\'s own behavior wins.');

        Assert.areEqual(3, resolved.MaxConcurrentConversations__c, 'Blank on the row, so taken from the policy.');
        Assert.areEqual(50, resolved.MaxConversationsPer24Hours__c, 'Blank on the row, so taken from the policy.');
    }

    @IsTest static void testScenario5() {

        // [1] Create a policy that grants capabilities and a row that tries to switch one off
        AIUsagePolicy__c grants = new AIUsagePolicy__c(DebugModeEnabled__c = true, WorkflowActionsEnabled__c = true);
        AIUserSettings__c row = new AIUserSettings__c(IsActive__c = true, DebugModeEnabled__c = false, ConversationExportEnabled__c = true);

        // [2] Resolve the row with the policy
        Test.startTest();
            AIUserSettings__c resolved = AIUsagePolicyService.resolve(row, new List<AIUsagePolicy__c>{ grants });
        Test.stopTest();

        // [3] Check the row cannot remove a granted capability
        Assert.isTrue(resolved.DebugModeEnabled__c, 'An unticked box on the row does not take away what the policy grants.');
        Assert.isTrue(resolved.ConversationExportEnabled__c, 'A ticked box on the row switches it on for that user.');
        Assert.isTrue(resolved.WorkflowActionsEnabled__c, 'From the policy.');
    }
}
