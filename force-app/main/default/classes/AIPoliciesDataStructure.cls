/*
Class Name: AIPoliciesDataStructure

=================================================================
=================================================================

Description: The shapes the AI Policies tab (aiPolicies) sends to and receives from Apex.

Step 1: PolicyView is one AI Usage Policy with its assignments, and AssignmentView is one assignment
Step 2: AssigneeOption is a user or permission set the admin can pick, and AssignmentWarning explains what picking it does
Step 3: DeleteOptions says what happens to the people of a policy that is deleted
Step 4: UserCheck explains which policy one user gets, and CheckSource is one line of that explanation

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPoliciesDataStructure {

    // One AI Usage Policy with the people and permission sets it is assigned to.
    public class PolicyView {

        @AuraEnabled public Id policyId;
        @AuraEnabled public String name;
        @AuraEnabled public Map<String, Object> values = new Map<String, Object>(); // The field values, keyed by field name such as MaxTokensPer24Hours__c.
        @AuraEnabled public List<AssignmentView> assignments = new List<AssignmentView>();
    }

    // One assignment of a policy to a user or to a permission set.
    public class AssignmentView {

        @AuraEnabled public Id assignmentId;
        @AuraEnabled public String assigneeType; // User or Permission Set.
        @AuraEnabled public String assigneeName; // The user's name, or the permission set label.
        @AuraEnabled public String assigneeDetail; // The username for a user, or the API name of a permission set.
        @AuraEnabled public Integer usersCovered; // 1 for a user, the number of active users holding the permission set otherwise.
        @AuraEnabled public Boolean isActive;
    }

    // A user or permission set the admin can pick in the Add assignment dialog or the Check a user box.
    public class AssigneeOption {

        @AuraEnabled public Id assigneeId; // The user Id, or the permission set or permission set group Id.
        @AuraEnabled public String name; // The user's name, or the permission set label.
        @AuraEnabled public String detail; // The username for a user, or the API name of a permission set.
        @AuraEnabled public Integer usersCovered; // 1 for a user, the number of active users holding the permission set otherwise.
        @AuraEnabled public Id currentPolicyId; // The policy the assignee gets today.
        @AuraEnabled public String currentPolicyName;
        @AuraEnabled public Boolean isCurrentPolicyDefault; // True when they get it only because it is the default.
        @AuraEnabled public Boolean hasPolicy; // True when the assignee is already assigned to a policy of their own.
        @AuraEnabled public Boolean isOnThisPolicy; // True when the assignee is already assigned to the policy being edited.
    }

    // What picking an assignee does when they already have a policy.
    public class AssignmentWarning {

        @AuraEnabled public Boolean hasWarning = false;
        @AuraEnabled public String message; // Plain-English sentence, built from a Custom Label.
    }

    // What the delete dialog needs: how many people the policy covers and where they can move to.
    public class DeleteOptions {

        @AuraEnabled public Id policyId;
        @AuraEnabled public String policyName;
        @AuraEnabled public Boolean isDefault; // The default policy cannot be deleted.
        @AuraEnabled public Integer assignmentCount;
        @AuraEnabled public Integer userCount; // Users covered by the policy's assignments.
        @AuraEnabled public Id defaultPolicyId; // The default policy, blank when the policy being deleted is it.
        @AuraEnabled public String defaultPolicyName;
        @AuraEnabled public List<PolicyOption> otherPolicies = new List<PolicyOption>(); // Every other policy, to move the people to.
    }

    // A policy the admin can move people to.
    public class PolicyOption {

        @AuraEnabled public Id policyId;
        @AuraEnabled public String name;
    }

    // The answer to "which policy does this user get, and why".
    public class UserCheck {

        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Id policyId; // The policy that applies, blank when none does.
        @AuraEnabled public String policyName;
        @AuraEnabled public String reason; // Plain-English sentence, built from Custom Labels.
        @AuraEnabled public List<CheckSource> sources = new List<CheckSource>();
        @AuraEnabled public String hintText; // Shown when a policy was ignored. Blank otherwise.
        @AuraEnabled public Id ignoredPolicyId; // The first policy that was ignored, so the tab can offer a user assignment to it.
        @AuraEnabled public String ignoredPolicyName;
    }

    // One line of the explanation: where a policy came from, its limits and what became of it.
    public class CheckSource {

        @AuraEnabled public String sourceLabel; // For example "Permission set · Mortgage Advisers", "User assignment" or "Default".
        @AuraEnabled public Id policyId;
        @AuraEnabled public String policyName;
        @AuraEnabled public Decimal maxTokensPer24Hours;
        @AuraEnabled public Decimal maxConversationsPer24Hours;
        @AuraEnabled public String outcome; // Wins, Ignored, Not needed or Applies.
    }
}
