/*
Class Name: AIUsagePolicyService

=================================================================
=================================================================

Description: Works out what one user is allowed, from the usage policies that apply to them.

Step 1: Find the usage policies that apply to the user, in system mode: those assigned to them or to a permission set they hold, otherwise the default policies
Step 2: Combine them into one AIUsagePolicy__c that is never saved: strictest limits, widest capabilities
Step 3: Return that policy, or null when no policy applies
Step 4: Say what the user may do at all: full use when a policy applies, none when it does not

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIUsagePolicyService {

    // What this user is allowed: the usage policies that apply to them, combined. Null when no policy applies, which means the user has no access.
    public static AIUsagePolicy__c getUsagePolicy(Id userId) {

        // [1] Nothing to look up without a user
        if (userId == null) return null;

        // [2] Combine the policies that apply to the user
        return resolvePolicies(getUsagePoliciesForUser(userId));
    }

    // What the user may do with AI Assist. A usage policy that applies to them gives full use. Without one they have none.
    public static String getAccessLevel(Id userId) {

        // [1] Nothing to look up without a user
        if (userId == null) return AIAssistApplicationConstants.ACCESS_LEVEL_NONE;

        // [2] A policy that applies to the user, assigned or by default, gives full use
        return getUsagePoliciesForUser(userId).isEmpty() ? AIAssistApplicationConstants.ACCESS_LEVEL_NONE : AIAssistApplicationConstants.ACCESS_LEVEL_FULL;
    }

    // Combines the policies that apply to a user into what they are allowed. The answer is never saved. Limits are strictest-wins: the lowest number, and the behavior that blocks most (Block New Messages, then Block New Conversations Only, then Notify Only), so adding a policy can never loosen a limit. Capabilities are additive: a channel, export or debug mode allowed by any policy is allowed, the widest conversation visibility wins, and a policy with no channels listed allows every channel.
    public static AIUsagePolicy__c resolvePolicies(List<AIUsagePolicy__c> policies) {

        // [1] Treat no policies as an empty list
        List<AIUsagePolicy__c> applicable = policies == null ? new List<AIUsagePolicy__c>() : policies;

        // [2] Nothing applies to this user, so there is no answer
        if (applicable.isEmpty()) return null;

        // [3] Limits: the lowest across the policies, and the behavior that blocks most
        AIUsagePolicy__c resolved = new AIUsagePolicy__c(IsActive__c = true);
        resolved.MaxConcurrentConversations__c = lowest(applicable, AIUsagePolicy__c.MaxConcurrentConversations__c);
        resolved.MaxConversationsPer24Hours__c = lowest(applicable, AIUsagePolicy__c.MaxConversationsPer24Hours__c);
        resolved.MaxTokensPer24Hours__c = lowest(applicable, AIUsagePolicy__c.MaxTokensPer24Hours__c);
        resolved.UsageLimitReachedBehavior__c = strictestBehavior(applicable);

        // [4] Visibility and channels: the widest visibility, and the channels any policy allows
        resolved.ConversationVisibilityScope__c = widestVisibility(applicable);
        resolved.AllowedChannels__c = channelsAllowedByAny(applicable);

        // [5] Capabilities: on if any policy switches them on
        resolved.ShouldCaptureExecutionSteps__c = anyChecked(applicable, AIUsagePolicy__c.ShouldCaptureExecutionSteps__c);
        resolved.ConversationExportEnabled__c = anyChecked(applicable, AIUsagePolicy__c.ConversationExportEnabled__c);
        resolved.DebugModeEnabled__c = anyChecked(applicable, AIUsagePolicy__c.DebugModeEnabled__c);
        resolved.IsUserInitiatedChatEnabled__c = anyChecked(applicable, AIUsagePolicy__c.IsUserInitiatedChatEnabled__c);

        // [6] Return the answer
        return resolved;
    }

    // The lowest value set for a limit across the policies, or null when none of them sets it.
    private static Decimal lowest(List<AIUsagePolicy__c> policies, Schema.SObjectField limitField) {

        // [1] Keep the lowest value seen so far
        Decimal lowestLimit = null;

        for (AIUsagePolicy__c policy : policies) {

            // [2] A blank limit sets nothing, so skip it
            Decimal limitValue = (Decimal) policy.get(limitField);

            if (limitValue != null && (lowestLimit == null || limitValue < lowestLimit)) lowestLimit = limitValue;
        }

        return lowestLimit;
    }

    // True when at least one policy has the checkbox ticked.
    private static Boolean anyChecked(List<AIUsagePolicy__c> policies, Schema.SObjectField flagField) {

        for (AIUsagePolicy__c policy : policies) {

            // [1] One ticked policy is enough
            if ((Boolean) policy.get(flagField) == true) return true;
        }

        return false;
    }

    // How strongly a behavior blocks: the higher the number, the more it blocks.
    private static Integer behaviorRank(String behavior) {

        // [1] Rank the known behaviors; anything else ranks lowest
        if (behavior == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_MESSAGES) return 3;
        if (behavior == AIAssistApplicationConstants.USAGE_LIMIT_BLOCK_NEW_CONVERSATIONS_ONLY) return 2;
        if (behavior == AIAssistApplicationConstants.USAGE_LIMIT_NOTIFY_ONLY) return 1;

        return 0;
    }

    // The behavior that blocks most across the policies, or null when none of them sets one.
    private static String strictestBehavior(List<AIUsagePolicy__c> policies) {

        // [1] Keep the strictest behavior seen so far
        String strictest = null;

        for (AIUsagePolicy__c policy : policies) {

            // [2] Replace it when this policy blocks more
            if (behaviorRank(policy.UsageLimitReachedBehavior__c) > behaviorRank(strictest)) strictest = policy.UsageLimitReachedBehavior__c;
        }

        return strictest;
    }

    // How much a visibility scope shows: the higher the number, the more it shows.
    private static Integer visibilityRank(String scope) {

        // [1] Rank the known scopes; anything else ranks lowest
        if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_ALL) return 3;
        if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_SUBORDINATES) return 2;
        if (scope == AIAssistApplicationConstants.VISIBILITY_SCOPE_OWN) return 1;

        return 0;
    }

    // The widest conversation visibility across the policies, or null when none of them sets one.
    private static String widestVisibility(List<AIUsagePolicy__c> policies) {

        // [1] Keep the widest scope seen so far
        String widest = null;

        for (AIUsagePolicy__c policy : policies) {

            // [2] Replace it when this policy shows more
            if (visibilityRank(policy.ConversationVisibilityScope__c) > visibilityRank(widest)) widest = policy.ConversationVisibilityScope__c;
        }

        return widest;
    }

    // Blank means every channel, so one policy with no list opens them all; otherwise the union of the lists.
    private static String channelsAllowedByAny(List<AIUsagePolicy__c> policies) {

        // [1] Collect the channels listed by each policy
        Set<String> channels = new Set<String>();

        for (AIUsagePolicy__c policy : policies) {

            // [2] A policy with no list allows every channel, so stop here
            if (String.isBlank(policy.AllowedChannels__c)) return null;

            channels.addAll(policy.AllowedChannels__c.split(';'));
        }

        // [3] Return the combined list, or null when no policy listed any
        return channels.isEmpty() ? null : String.join(new List<String>(channels), ';');
    }

    // The API names of every permission set the user holds: assigned directly, and the name of each permission set group assigned to them together with the permission sets inside that group. A permission set reached only through a group has no assignment row of its own, so matching on assignment rows alone would miss it.
    private static Set<String> getHeldPermissionSetNames(Id userId) {

        // [1] Collect the names the user holds, and the groups they are assigned
        Set<String> heldNames = new Set<String>();
        Set<Id> heldGroupIds = new Set<Id>();

        // [2] Add each directly assigned permission set, and note any group
        for (PermissionSetAssignment heldAssignment : [SELECT PermissionSet.Name, PermissionSetGroupId, PermissionSetGroup.DeveloperName FROM PermissionSetAssignment WHERE AssigneeId = :userId WITH SYSTEM_MODE LIMIT 2000]) {

            heldNames.add(heldAssignment.PermissionSet.Name);

            if (heldAssignment.PermissionSetGroupId != null) {

                heldGroupIds.add(heldAssignment.PermissionSetGroupId);
                heldNames.add(heldAssignment.PermissionSetGroup.DeveloperName);
            }
        }

        // [3] Add the permission sets inside each group the user holds
        if (!heldGroupIds.isEmpty()) {

            for (PermissionSetGroupComponent member : [SELECT PermissionSet.Name FROM PermissionSetGroupComponent WHERE PermissionSetGroupId IN :heldGroupIds WITH SYSTEM_MODE LIMIT 2000]) heldNames.add(member.PermissionSet.Name);
        }

        return heldNames;
    }

    // The active policies that apply to a user: those assigned to them or to a permission set they hold, or, when there are none, the default policies.
    private static List<AIUsagePolicy__c> getUsagePoliciesForUser(Id userId) {

        // [1] Nothing to look up without a user
        if (userId == null) return new List<AIUsagePolicy__c>();

        // [2] Find the permission sets the user holds
        Set<String> heldPermissionSets = getHeldPermissionSetNames(userId);

        // [3] Find the policies assigned to the user, or to a permission set they hold
        Set<Id> policyIds = new Set<Id>();

        for (AIUsagePolicyAssignment__c assignment : [SELECT AIUsagePolicy__c FROM AIUsagePolicyAssignment__c WHERE IsActive__c = TRUE AND AIUsagePolicy__r.IsActive__c = TRUE AND ((AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER AND User__c = :userId) OR (AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET AND PermissionSetName__c IN :heldPermissionSets)) WITH SYSTEM_MODE LIMIT 200]) policyIds.add(assignment.AIUsagePolicy__c);

        // [4] Nothing assigned, so the default policies cover the user instead
        if (policyIds.isEmpty()) {

            return [SELECT Id, AllowedChannels__c, ConversationExportEnabled__c, ConversationVisibilityScope__c, DebugModeEnabled__c, MaxConcurrentConversations__c, MaxConversationsPer24Hours__c, MaxTokensPer24Hours__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WHERE IsActive__c = TRUE AND IsDefault__c = TRUE WITH SYSTEM_MODE LIMIT 200];
        }

        // [5] Return the active policies assigned to the user
        return [SELECT Id, AllowedChannels__c, ConversationExportEnabled__c, ConversationVisibilityScope__c, DebugModeEnabled__c, MaxConcurrentConversations__c, MaxConversationsPer24Hours__c, MaxTokensPer24Hours__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WHERE IsActive__c = TRUE AND Id IN :policyIds WITH SYSTEM_MODE LIMIT 200];
    }
}
