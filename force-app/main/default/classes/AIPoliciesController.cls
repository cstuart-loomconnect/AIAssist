/*
Class Name: AIPoliciesController

=================================================================
=================================================================

Description: The Apex controller behind the AI Policies tab.

Step 1: Read, save and delete AI Usage Policies
Step 2: Find, add, switch and remove the users and permission sets a policy is assigned to
Step 3: Explain which policy one user gets
Step 4: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPoliciesController {

    public class AIPoliciesControllerException extends Exception {}

    // Every AI Usage Policy with its assignments.
    @AuraEnabled
    public static List<AIPoliciesDataStructure.PolicyView> getPolicies() {

        try {

            // [1] Do the work
            return AIPoliciesEditorService.getPolicies();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getPolicies');
        }
    }

    // Saves one policy, creating it when policyId is blank, and returns it as saved.
    @AuraEnabled
    public static AIPoliciesDataStructure.PolicyView savePolicy(Id policyId, Map<String, Object> values) {

        try {

            // [1] Do the work
            return AIPoliciesEditorService.savePolicy(policyId, values);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'savePolicy');
        }
    }

    // What the delete dialog shows: who the policy covers and where they can move to.
    @AuraEnabled
    public static AIPoliciesDataStructure.DeleteOptions getDeleteOptions(Id policyId) {

        try {

            // [1] Do the work
            return AIPoliciesEditorService.getDeleteOptions(policyId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getDeleteOptions');
        }
    }

    // Moves the people of a policy to another policy, deletes it, and returns every policy as saved.
    @AuraEnabled
    public static List<AIPoliciesDataStructure.PolicyView> deletePolicy(Id policyId, Id moveToPolicyId) {

        try {

            // [1] Do the work
            return AIPoliciesEditorService.deletePolicy(policyId, moveToPolicyId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'deletePolicy');
        }
    }

    // The users or permission sets whose name matches the text, with the policy each gets today.
    @AuraEnabled
    public static List<AIPoliciesDataStructure.AssigneeOption> findAssignees(Id policyId, String assigneeType, String searchText) {

        try {

            // [1] Do the work
            return AIPoliciesAssignmentService.findAssignees(policyId, assigneeType, searchText);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'findAssignees');
        }
    }

    // What happens if the user or permission set is added to the policy.
    @AuraEnabled
    public static AIPoliciesDataStructure.AssignmentWarning getAssignmentWarning(Id policyId, String assigneeType, Id assigneeId) {

        try {

            // [1] Do the work
            return AIPoliciesAssignmentService.getAssignmentWarning(policyId, assigneeType, assigneeId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getAssignmentWarning');
        }
    }

    // Assigns a policy to a user or a permission set, and returns the policy as saved.
    @AuraEnabled
    public static AIPoliciesDataStructure.PolicyView addAssignment(Id policyId, String assigneeType, Id assigneeId) {

        try {

            // [1] Do the work
            return AIPoliciesAssignmentService.addAssignment(policyId, assigneeType, assigneeId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'addAssignment');
        }
    }

    // Switches an assignment on or off, and returns the policy as saved.
    @AuraEnabled
    public static AIPoliciesDataStructure.PolicyView setAssignmentActive(Id assignmentId, Boolean isActive) {

        try {

            // [1] Do the work
            return AIPoliciesAssignmentService.setAssignmentActive(assignmentId, isActive);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setAssignmentActive');
        }
    }

    // Removes an assignment, and returns the policy as saved.
    @AuraEnabled
    public static AIPoliciesDataStructure.PolicyView removeAssignment(Id assignmentId) {

        try {

            // [1] Do the work
            return AIPoliciesAssignmentService.removeAssignment(assignmentId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'removeAssignment');
        }
    }

    // Which policy a user gets and why.
    @AuraEnabled
    public static AIPoliciesDataStructure.UserCheck checkUser(Id userId) {

        try {

            // [1] Do the work
            return AIPoliciesCheckService.checkUser(userId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'checkUser');
        }
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIPoliciesController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
