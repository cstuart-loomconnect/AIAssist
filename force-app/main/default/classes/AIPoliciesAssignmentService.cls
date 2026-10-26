/*
Class Name: AIPoliciesAssignmentService

=================================================================
=================================================================

Description: Finds, adds, switches and removes the users and permission sets an AI Usage Policy is assigned to.

Step 1: Find the users and permission sets an admin can pick, with the policy each gets today
Step 2: Warn when the pick already has a policy, and say which policy would win
Step 3: Add, switch on or off, and remove an assignment
Step 4: Say how many users a permission set covers, and what its label is
Step 5: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPoliciesAssignmentService {

    public class AIPoliciesAssignmentServiceException extends Exception {}

    // The users or the permission sets and permission set groups whose name matches the text, each with the policy they get today. The text must be long enough to be worth searching. Leave policyId blank when no policy is being edited, as the Check a user box does.
    public static List<AIPoliciesDataStructure.AssigneeOption> findAssignees(Id policyId, String assigneeType, String searchText) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();
        List<AIPoliciesDataStructure.AssigneeOption> options = new List<AIPoliciesDataStructure.AssigneeOption>();

        // [2] Wait for enough text to make the search worth running
        String trimmedText = String.isBlank(searchText) ? '' : searchText.trim();
        if (trimmedText.length() < AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MIN_LENGTH) return options;

        String likeText = '%' + String.escapeSingleQuotes(trimmedText) + '%';

        // [3] Search the kind of assignee the admin chose
        if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) return findUsers(policyId, likeText);
        if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) return findPermissionSets(policyId, likeText);

        throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Assignee);
    }

    // Says what happens when the user or permission set is added to the policy: a sentence when they already have a policy of their own, and nothing when they do not.
    public static AIPoliciesDataStructure.AssignmentWarning getAssignmentWarning(Id policyId, String assigneeType, Id assigneeId) {

        // [1] Refuse a user who may not use the tab, and a policy that is gone
        AIAssistSettingsEditorService.requireManager();
        AIPoliciesDataStructure.AssignmentWarning warning = new AIPoliciesDataStructure.AssignmentWarning();
        AIUsagePolicy__c policy = findPolicy(policyId);

        // [2] Find who is being added, and the assignments they already have to other active policies
        Boolean isUser = assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER;
        String assigneeName = null;
        String permissionSetName = null;
        Integer usersCovered = 1;

        if (isUser) {

            List<User> users = [SELECT Name FROM User WHERE Id = :assigneeId WITH SYSTEM_MODE LIMIT 1];
            if (users.isEmpty()) return warning;

            assigneeName = users[0].Name;

        } else {

            AIPoliciesDataStructure.AssigneeOption permissionSet = getPermissionSetOption(assigneeId);
            permissionSetName = permissionSet.detail;
            assigneeName = permissionSet.name;
            usersCovered = getUsersCovered(new Set<String>{permissionSetName}).get(permissionSetName);
        }

        Id userId = isUser ? assigneeId : null;
        List<AIUsagePolicyAssignment__c> assignments = [SELECT AIUsagePolicy__c FROM AIUsagePolicyAssignment__c WHERE IsActive__c = TRUE AND AIUsagePolicy__c != :policyId AND AIUsagePolicy__r.IsActive__c = TRUE AND AssigneeType__c = :assigneeType AND User__c = :userId AND PermissionSetName__c = :permissionSetName WITH SYSTEM_MODE LIMIT 200];
        if (assignments.isEmpty()) return warning;

        // [3] Find the other policies and the strictest of them together with this one
        Set<Id> otherPolicyIds = new Set<Id>();

        for (AIUsagePolicyAssignment__c assignment : assignments) otherPolicyIds.add(assignment.AIUsagePolicy__c);

        List<AIUsagePolicy__c> candidates = [SELECT Id, Name, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c FROM AIUsagePolicy__c WHERE Id IN :otherPolicyIds WITH SYSTEM_MODE ORDER BY Name LIMIT 200];
        AIUsagePolicy__c firstOther = candidates[0];
        candidates.add(policy);
        AIUsagePolicy__c winner = AIUsagePolicyService.getStrictestPolicy(candidates);

        // [4] Say it in a sentence
        String tokensText = winner.MaxTokensPer24Hours__c == null ? Label.AI_Policies_No_Token_Limit : String.format(Label.AI_Policies_Tokens_A_Day, new List<String>{winner.MaxTokensPer24Hours__c.format()});
        warning.hasWarning = true;

        if (isUser) warning.message = String.format(Label.AI_Policies_Warning_User, new List<String>{assigneeName, firstOther.Name, winner.Name, tokensText});
        else warning.message = String.format(Label.AI_Policies_Warning_Permission_Set, new List<String>{assigneeName, firstOther.Name, String.valueOf(usersCovered), winner.Name, tokensText});

        return warning;
    }

    // Assigns a policy to a user or to a permission set or permission set group, and returns the policy as saved.
    public static AIPoliciesDataStructure.PolicyView addAssignment(Id policyId, String assigneeType, Id assigneeId) {

        // [1] Refuse a user who may not use the tab, and a policy that is gone
        AIAssistSettingsEditorService.requireManager();
        findPolicy(policyId);

        // [2] Build the assignment for the chosen type
        AIUsagePolicyAssignment__c assignment = new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policyId, AssigneeType__c = assigneeType, IsActive__c = true);

        if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) {

            if (assigneeId == null || assigneeId.getSobjectType() != Schema.User.SObjectType) throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Assignee);
            assignment.User__c = assigneeId;

        } else if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) {

            assignment.PermissionSetName__c = getPermissionSetOption(assigneeId).detail;

        } else {

            throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Assignee);
        }

        // [3] The same assignee twice on one policy is refused
        if (hasAssignment(assignment)) throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Duplicate);

        Database.insert(assignment, AccessLevel.SYSTEM_MODE);

        return AIPoliciesEditorService.getPolicy(policyId);
    }

    // Switches an assignment on or off, and returns the policy as saved.
    public static AIPoliciesDataStructure.PolicyView setAssignmentActive(Id assignmentId, Boolean isActive) {

        // [1] Refuse a user who may not use the tab, and an assignment that is gone
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicyAssignment__c assignment = findAssignment(assignmentId);

        // [2] Save the new state
        Database.update(new AIUsagePolicyAssignment__c(Id = assignmentId, IsActive__c = isActive == true), AccessLevel.SYSTEM_MODE);

        return AIPoliciesEditorService.getPolicy(assignment.AIUsagePolicy__c);
    }

    // Removes an assignment, and returns the policy as saved.
    public static AIPoliciesDataStructure.PolicyView removeAssignment(Id assignmentId) {

        // [1] Refuse a user who may not use the tab, and an assignment that is gone
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicyAssignment__c assignment = findAssignment(assignmentId);

        // [2] Delete it
        Id policyId = assignment.AIUsagePolicy__c;
        Database.delete(assignment, AccessLevel.SYSTEM_MODE);

        return AIPoliciesEditorService.getPolicy(policyId);
    }

    // How many active users hold each permission set or permission set group, by API name. Only users assigned the set or the group by name are counted, not users who reach a set through another group. A name nobody holds counts 0.
    public static Map<String, Integer> getUsersCovered(Set<String> names) {

        // [1] Start every name at zero
        Map<String, Integer> usersByName = new Map<String, Integer>();

        for (String name : names) usersByName.put(name, 0);

        if (names.isEmpty()) return usersByName;

        // [2] Count the distinct active users assigned each permission set
        for (AggregateResult result : [SELECT PermissionSet.Name setName, COUNT_DISTINCT(AssigneeId) userCount FROM PermissionSetAssignment WHERE PermissionSet.Name IN :names AND PermissionSet.Type != 'Group' AND Assignee.IsActive = TRUE WITH SYSTEM_MODE GROUP BY PermissionSet.Name]) {

            usersByName.put((String) result.get('setName'), (Integer) result.get('userCount'));
        }

        // [3] Count the distinct active users assigned each permission set group
        for (AggregateResult result : [SELECT PermissionSetGroup.DeveloperName groupName, COUNT_DISTINCT(AssigneeId) userCount FROM PermissionSetAssignment WHERE PermissionSetGroup.DeveloperName IN :names AND Assignee.IsActive = TRUE WITH SYSTEM_MODE GROUP BY PermissionSetGroup.DeveloperName]) {

            usersByName.put((String) result.get('groupName'), (Integer) result.get('userCount'));
        }

        return usersByName;
    }

    // The label of each permission set or permission set group, by API name. A name that is not found keeps the name as its label.
    public static Map<String, String> getPermissionSetLabels(Set<String> names) {

        // [1] Start every name with itself as the label
        Map<String, String> labelsByName = new Map<String, String>();

        for (String name : names) labelsByName.put(name, name);

        if (names.isEmpty()) return labelsByName;

        // [2] Read the permission set labels, then the group labels
        for (PermissionSet permissionSet : [SELECT Name, Label FROM PermissionSet WHERE Name IN :names AND IsOwnedByProfile = FALSE WITH SYSTEM_MODE LIMIT 2000]) labelsByName.put(permissionSet.Name, permissionSet.Label);

        for (PermissionSetGroup permissionSetGroup : [SELECT DeveloperName, MasterLabel FROM PermissionSetGroup WHERE DeveloperName IN :names WITH SYSTEM_MODE LIMIT 2000]) labelsByName.put(permissionSetGroup.DeveloperName, permissionSetGroup.MasterLabel);

        return labelsByName;
    }

    // The users whose name or username matches the text, each with the policy they get today.
    private static List<AIPoliciesDataStructure.AssigneeOption> findUsers(Id policyId, String likeText) {

        // [1] Search active standard users
        Integer maxResults = AIAssistApplicationConstants.POLICIES_USER_SEARCH_MAX_RESULTS;
        String standardType = AIAssistApplicationConstants.USER_TYPE_STANDARD;
        List<User> users = [SELECT Id, Name, Username FROM User WHERE IsActive = TRUE AND UserType = :standardType AND (Name LIKE :likeText OR Username LIKE :likeText) WITH SYSTEM_MODE ORDER BY Name LIMIT :maxResults];

        // [2] Find the user assignments of those users
        Map<Id, Id> ownPolicyIdByUserId = new Map<Id, Id>();

        for (AIUsagePolicyAssignment__c assignment : [SELECT User__c, AIUsagePolicy__c FROM AIUsagePolicyAssignment__c WHERE AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_USER AND User__c IN :users WITH SYSTEM_MODE LIMIT 2000]) {

            if (!ownPolicyIdByUserId.containsKey(assignment.User__c) || assignment.AIUsagePolicy__c == policyId) ownPolicyIdByUserId.put(assignment.User__c, assignment.AIUsagePolicy__c);
        }

        // [3] Build an option for each user, with the policy the user gets today
        List<AIPoliciesDataStructure.AssigneeOption> options = new List<AIPoliciesDataStructure.AssigneeOption>();

        for (User user : users) {

            AIPoliciesDataStructure.AssigneeOption option = buildOption(user.Id, user.Name, user.Username, 1);
            option.hasPolicy = ownPolicyIdByUserId.containsKey(user.Id);
            option.isOnThisPolicy = policyId != null && ownPolicyIdByUserId.get(user.Id) == policyId;

            for (AIUsagePolicyService.PolicyCandidate candidate : AIUsagePolicyService.getPolicyCandidates(user.Id)) {

                if (!candidate.isWinner || option.currentPolicyId != null) continue;

                option.currentPolicyId = candidate.policy.Id;
                option.currentPolicyName = candidate.policy.Name;
                option.isCurrentPolicyDefault = candidate.tier == AIAssistApplicationConstants.POLICY_TIER_DEFAULT;
            }

            options.add(option);
        }

        return options;
    }

    // The permission sets and permission set groups whose name or label matches the text, each with the policy they get today.
    private static List<AIPoliciesDataStructure.AssigneeOption> findPermissionSets(Id policyId, String likeText) {

        // [1] Search permission sets, then permission set groups. The API name is what a policy stores.
        Integer maxResults = AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MAX_RESULTS;
        List<AIPoliciesDataStructure.AssigneeOption> options = new List<AIPoliciesDataStructure.AssigneeOption>();

        for (PermissionSet matchingSet : [SELECT Id, Name, Label FROM PermissionSet WHERE IsOwnedByProfile = FALSE AND Type != 'Group' AND (Name LIKE :likeText OR Label LIKE :likeText) WITH SYSTEM_MODE ORDER BY Label LIMIT :maxResults]) options.add(buildOption(matchingSet.Id, matchingSet.Label, matchingSet.Name, null));

        for (PermissionSetGroup matchingGroup : [SELECT Id, DeveloperName, MasterLabel FROM PermissionSetGroup WHERE DeveloperName LIKE :likeText OR MasterLabel LIKE :likeText WITH SYSTEM_MODE ORDER BY MasterLabel LIMIT :maxResults]) options.add(buildOption(matchingGroup.Id, matchingGroup.MasterLabel, matchingGroup.DeveloperName, null));

        // [2] Count the users of each, and find the assignments they already have
        Set<String> names = new Set<String>();

        for (AIPoliciesDataStructure.AssigneeOption option : options) names.add(option.detail);

        Map<String, Integer> usersByName = getUsersCovered(names);
        Map<String, AIUsagePolicyAssignment__c> ownAssignmentByName = new Map<String, AIUsagePolicyAssignment__c>();

        for (AIUsagePolicyAssignment__c assignment : [SELECT PermissionSetName__c, AIUsagePolicy__c, AIUsagePolicy__r.Name FROM AIUsagePolicyAssignment__c WHERE AssigneeType__c = :AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET AND PermissionSetName__c IN :names WITH SYSTEM_MODE LIMIT 2000]) {

            if (!ownAssignmentByName.containsKey(assignment.PermissionSetName__c) || assignment.AIUsagePolicy__c == policyId) ownAssignmentByName.put(assignment.PermissionSetName__c, assignment);
        }

        // [3] Without an assignment of their own they get the default policy
        List<AIUsagePolicy__c> defaultPolicies = [SELECT Id, Name FROM AIUsagePolicy__c WHERE IsDefault__c = TRUE AND IsActive__c = TRUE WITH SYSTEM_MODE ORDER BY Name LIMIT 1];

        for (AIPoliciesDataStructure.AssigneeOption option : options) {

            option.usersCovered = usersByName.get(option.detail);
            AIUsagePolicyAssignment__c ownAssignment = ownAssignmentByName.get(option.detail);
            option.hasPolicy = ownAssignment != null;
            option.isOnThisPolicy = ownAssignment != null && policyId != null && ownAssignment.AIUsagePolicy__c == policyId;

            if (ownAssignment != null) {

                option.currentPolicyId = ownAssignment.AIUsagePolicy__c;
                option.currentPolicyName = ownAssignment.AIUsagePolicy__r.Name;

            } else if (!defaultPolicies.isEmpty()) {

                option.currentPolicyId = defaultPolicies[0].Id;
                option.currentPolicyName = defaultPolicies[0].Name;
                option.isCurrentPolicyDefault = true;
            }
        }

        return options;
    }

    // Builds an option the admin can pick, with nothing known yet about the policy it gets.
    private static AIPoliciesDataStructure.AssigneeOption buildOption(Id assigneeId, String name, String detail, Integer usersCovered) {

        // [1] Copy the values
        AIPoliciesDataStructure.AssigneeOption option = new AIPoliciesDataStructure.AssigneeOption();
        option.assigneeId = assigneeId;
        option.name = name;
        option.detail = detail;
        option.usersCovered = usersCovered;
        option.hasPolicy = false;
        option.isOnThisPolicy = false;
        option.isCurrentPolicyDefault = false;

        return option;
    }

    // The permission set or permission set group with the Id, as an option whose detail is the API name, or a refusal when it is neither.
    private static AIPoliciesDataStructure.AssigneeOption getPermissionSetOption(Id assigneeId) {

        // [1] A blank Id is not a permission set
        if (assigneeId == null) throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Permission_Set);

        // [2] Look for a permission set, then a group
        for (PermissionSet permissionSet : [SELECT Id, Name, Label FROM PermissionSet WHERE Id = :assigneeId AND IsOwnedByProfile = FALSE WITH SYSTEM_MODE LIMIT 1]) return buildOption(permissionSet.Id, permissionSet.Label, permissionSet.Name, null);

        for (PermissionSetGroup permissionSetGroup : [SELECT Id, DeveloperName, MasterLabel FROM PermissionSetGroup WHERE Id = :assigneeId WITH SYSTEM_MODE LIMIT 1]) return buildOption(permissionSetGroup.Id, permissionSetGroup.MasterLabel, permissionSetGroup.DeveloperName, null);

        throw new AIPoliciesAssignmentServiceException(Label.AI_Policies_Error_Permission_Set);
    }

    // The saved policy with the fields the warning needs, or a refusal when it is gone.
    private static AIUsagePolicy__c findPolicy(Id policyId) {

        // [1] Read the policy
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c FROM AIUsagePolicy__c WHERE Id = :policyId WITH SYSTEM_MODE LIMIT 1];
        if (policies.isEmpty()) throw new AIPoliciesAssignmentServiceException(Label.AI_Settings_Error_Row_Not_Found);

        return policies[0];
    }

    // The saved assignment, or a refusal when it is gone.
    private static AIUsagePolicyAssignment__c findAssignment(Id assignmentId) {

        // [1] Read the assignment
        List<AIUsagePolicyAssignment__c> assignments = [SELECT Id, AIUsagePolicy__c, IsActive__c FROM AIUsagePolicyAssignment__c WHERE Id = :assignmentId WITH SYSTEM_MODE LIMIT 1];
        if (assignments.isEmpty()) throw new AIPoliciesAssignmentServiceException(Label.AI_Settings_Error_Row_Not_Found);

        return assignments[0];
    }

    // Says whether the policy already has this user or permission set assigned.
    private static Boolean hasAssignment(AIUsagePolicyAssignment__c assignment) {

        // [1] Look for the same assignee on the same policy
        Id policyId = assignment.AIUsagePolicy__c;
        String assigneeType = assignment.AssigneeType__c;
        Id userId = assignment.User__c;
        String permissionSetName = assignment.PermissionSetName__c;

        Integer matches = [SELECT COUNT() FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :policyId AND AssigneeType__c = :assigneeType AND User__c = :userId AND PermissionSetName__c = :permissionSetName WITH SYSTEM_MODE LIMIT 1];

        return matches > 0;
    }
}
