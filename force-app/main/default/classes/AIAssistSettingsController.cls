/*
Class Name: AIAssistSettingsController

=================================================================
=================================================================

Description: The Apex controller behind the AI Assist Settings tab.

Step 1: Read every row of AI Assist Settings and AI Assist UI Settings
Step 2: Save or delete one row, at organisation, profile or user level
Step 3: Find a profile or user to create a row for
Step 4: Read, save and delete AI Usage Policies, and add, switch and remove their assignments
Step 5: Show an expected refusal as it is, and log anything unexpected once and show the generic label

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistSettingsController {

    public class AIAssistSettingsControllerException extends Exception {}

    // Every row of both settings, for the tab to show.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.SettingsPage getSettingsPage() {

        try {

            // [1] Read the rows
            return AIAssistSettingsEditorService.getSettingsPage();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getSettingsPage');
        }
    }

    // Saves one row and returns it as saved. The tab sends the settings name, the scope (Organisation, Profile or User), the profile or user Id for those scopes, and the values by field name.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.SettingsRow saveSettingsRow(String settingsName, String scope, Id ownerId, Map<String, Object> values) {

        try {

            // [1] Check and save the row
            return AIAssistSettingsEditorService.saveRow(settingsName, scope, ownerId, values);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'saveSettingsRow');
        }
    }

    // Deletes a profile or user row.
    @AuraEnabled
    public static void deleteSettingsRow(String settingsName, Id rowId) {

        try {

            // [1] Delete the row
            AIAssistSettingsEditorService.deleteRow(settingsName, rowId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'deleteSettingsRow');
        }
    }

    // The profiles or users whose name matches the text.
    @AuraEnabled
    public static List<AIAssistSettingsDataStructure.OwnerOption> findOwners(String scope, String searchText) {

        try {

            // [1] Search
            return AIAssistSettingsEditorService.findOwners(scope, searchText);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'findOwners');
        }
    }

    // Every AI Usage Policy with its assignments.
    @AuraEnabled
    public static List<AIAssistSettingsDataStructure.PolicyView> getPolicies() {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.getPolicies();

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'getPolicies');
        }
    }

    // Saves one policy, creating it when policyId is blank, and returns it as saved.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.PolicyView savePolicy(Id policyId, Map<String, Object> values) {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.savePolicy(policyId, values);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'savePolicy');
        }
    }

    // Deletes a policy and its assignments.
    @AuraEnabled
    public static void deletePolicy(Id policyId) {

        try {

            // [1] Do the work
            AIAssistPolicyEditorService.deletePolicy(policyId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'deletePolicy');
        }
    }

    // Assigns a policy to a user or a permission set.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.PolicyView addPolicyAssignment(Id policyId, String assigneeType, Id userId, String permissionSetName) {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.addAssignment(policyId, assigneeType, userId, permissionSetName);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'addPolicyAssignment');
        }
    }

    // Switches an assignment on or off.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.PolicyView setPolicyAssignmentActive(Id assignmentId, Boolean isActive) {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.setAssignmentActive(assignmentId, isActive);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'setPolicyAssignmentActive');
        }
    }

    // Removes an assignment.
    @AuraEnabled
    public static AIAssistSettingsDataStructure.PolicyView removePolicyAssignment(Id assignmentId) {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.removeAssignment(assignmentId);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'removePolicyAssignment');
        }
    }

    // The permission sets and groups whose name matches the text.
    @AuraEnabled
    public static List<AIAssistSettingsDataStructure.OwnerOption> findPermissionSets(String searchText) {

        try {

            // [1] Do the work
            return AIAssistPolicyEditorService.findPermissionSets(searchText);

        } catch (Exception ex) {

            // [2] Hand the tab a message it can show
            throw buildAuraException(ex, 'findPermissionSets');
        }
    }

    // Shows a package refusal as it is, which is already a Custom Label, and logs anything else once so the tab gets the generic label.
    private static AuraHandledException buildAuraException(Exception ex, String methodName) {

        // [1] Choose the text
        String errorText = Label.AI_Error_Generic;
        if (!ex.getTypeName().startsWith('System.')) errorText = ex.getMessage();
        else AIPlatformLogManager.logException(ex, 'AIAssistSettingsController', methodName);

        // [2] Build the exception the tab can read
        AuraHandledException auraException = new AuraHandledException(errorText);
        auraException.setMessage(errorText);

        return auraException;
    }
}
