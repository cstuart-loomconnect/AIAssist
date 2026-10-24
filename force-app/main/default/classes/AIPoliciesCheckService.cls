/*
Class Name: AIPoliciesCheckService

=================================================================
=================================================================

Description: Explains which usage policy one user gets and why, for the Check a user box on the AI Policies tab.

Step 1: Find every policy that could apply to the user, and which one wins, using the same rules as the chat
Step 2: Build one line for each, saying where it came from, its limits and what became of it
Step 3: Write the reason in plain English, and a hint when a policy was ignored
Step 4: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPoliciesCheckService {

    public class AIPoliciesCheckServiceException extends Exception {}

    // Which policy the user gets, where every policy that could apply came from, and what became of each.
    public static AIPoliciesDataStructure.UserCheck checkUser(Id userId) {

        // [1] Refuse a user who may not use the tab, and a user who is gone
        AIAssistSettingsEditorService.requireManager();
        List<User> users = [SELECT Id, Name FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (users.isEmpty()) throw new AIPoliciesCheckServiceException(Label.AI_Settings_Error_Row_Not_Found);

        AIPoliciesDataStructure.UserCheck check = new AIPoliciesDataStructure.UserCheck();
        check.userId = users[0].Id;
        check.userName = users[0].Name;

        // [2] Find the policies that could apply, and the labels of their permission sets
        List<AIUsagePolicyService.PolicyCandidate> candidates = AIUsagePolicyService.getPolicyCandidates(userId);
        Set<String> permissionSetNames = new Set<String>();

        for (AIUsagePolicyService.PolicyCandidate candidate : candidates) {

            if (candidate.assigneeName != null) permissionSetNames.add(candidate.assigneeName);
        }

        Map<String, String> labelsByName = AIPoliciesAssignmentService.getPermissionSetLabels(permissionSetNames);

        // [3] Build one line for each candidate, and note the winner
        AIUsagePolicyService.PolicyCandidate winner = null;
        String winnerSourceLabel = null;
        Set<Id> userPolicyIds = new Set<Id>();
        Set<Id> permissionSetPolicyIds = new Set<Id>();
        Integer userCount = 0;
        Integer permissionSetCount = 0;

        for (AIUsagePolicyService.PolicyCandidate candidate : candidates) {

            AIPoliciesDataStructure.CheckSource source = new AIPoliciesDataStructure.CheckSource();
            source.policyId = candidate.policy.Id;
            source.policyName = candidate.policy.Name;
            source.maxTokensPer24Hours = candidate.policy.MaxTokensPer24Hours__c;
            source.maxConversationsPer24Hours = candidate.policy.MaxConversationsPer24Hours__c;

            if (candidate.tier == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) {

                source.sourceLabel = Label.AI_Policies_Source_User;
                userPolicyIds.add(candidate.policy.Id);
                userCount++;

            } else if (candidate.tier == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) {

                source.sourceLabel = String.format(Label.AI_Policies_Source_Permission_Set, new List<String>{labelsByName.get(candidate.assigneeName)});
                permissionSetPolicyIds.add(candidate.policy.Id);
                permissionSetCount++;

            } else {

                source.sourceLabel = Label.AI_Policies_Source_Default;
            }

            Boolean isDefault = candidate.tier == AIAssistApplicationConstants.POLICY_TIER_DEFAULT;

            if (candidate.isWinner) source.outcome = isDefault ? AIAssistApplicationConstants.POLICY_OUTCOME_APPLIES : AIAssistApplicationConstants.POLICY_OUTCOME_WINS;
            else source.outcome = isDefault ? AIAssistApplicationConstants.POLICY_OUTCOME_NOT_NEEDED : AIAssistApplicationConstants.POLICY_OUTCOME_IGNORED;

            if (candidate.isWinner && winner == null) {

                winner = candidate;
                winnerSourceLabel = source.sourceLabel;
            }

            check.sources.add(source);
        }

        // [4] Nothing applies, so the user has no policy
        if (winner == null) {

            check.reason = Label.AI_Policies_Check_Reason_None;

            return check;
        }

        check.policyId = winner.policy.Id;
        check.policyName = winner.policy.Name;

        // [5] Write the reason for the group the winner came from
        if (winner.tier == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) check.reason = userPolicyIds.size() > 1 ? String.format(Label.AI_Policies_Check_Reason_User_Several, new List<String>{String.valueOf(userCount)}) : Label.AI_Policies_Check_Reason_User;
        else if (winner.tier == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) check.reason = permissionSetPolicyIds.size() > 1 ? String.format(Label.AI_Policies_Check_Reason_Permission_Set_Several, new List<String>{String.valueOf(permissionSetCount)}) : Label.AI_Policies_Check_Reason_Permission_Set;
        else check.reason = Label.AI_Policies_Check_Reason_Default;

        // [6] A permission set won, so offer a way to give the user a policy that was ignored
        if (winner.tier != AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) return check;

        for (Integer index = 0; index < candidates.size(); index++) {

            AIPoliciesDataStructure.CheckSource source = check.sources[index];
            Boolean isIgnored = source.outcome == AIAssistApplicationConstants.POLICY_OUTCOME_IGNORED && source.policyId != winner.policy.Id;
            if (!isIgnored || check.ignoredPolicyId != null) continue;

            check.ignoredPolicyId = source.policyId;
            check.ignoredPolicyName = source.policyName;
            check.hintText = String.format(Label.AI_Policies_Check_Hint, new List<String>{source.policyName, winnerSourceLabel});
        }

        return check;
    }
}
