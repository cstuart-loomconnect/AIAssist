/*
Class Name: AIAssistSettingsDataStructure

=================================================================
=================================================================

Description: The shapes the Settings tab (aiAssistSettings) sends to and receives from Apex.

Step 1: SettingsPage holds every row of both settings, ready to show
Step 2: SettingsRow is one row, at organisation, profile or user level, with its values by field name
Step 3: OwnerOption is a profile or user the admin can pick for a new row
Step 4: PolicyView is one AI Usage Policy with its assignments, and PolicyAssignmentView is one assignment

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistSettingsDataStructure {

    // Everything the tab needs to open: the rows of AI Assist Settings and of AI Assist UI Settings.
    public class SettingsPage {

        @AuraEnabled public List<SettingsRow> assistRows = new List<SettingsRow>();
        @AuraEnabled public List<SettingsRow> uiRows = new List<SettingsRow>();
    }

    // One settings row. The organisation row comes first and always exists, with a blank rowId until it is first saved.
    public class SettingsRow {

        @AuraEnabled public Id rowId; // Blank for an organisation row that has never been saved.
        @AuraEnabled public String scope; // Organisation, Profile or User.
        @AuraEnabled public Id ownerId; // The organisation, profile or user the row is for.
        @AuraEnabled public String ownerName;
        @AuraEnabled public Map<String, Object> values = new Map<String, Object>(); // The field values, keyed by field name such as MaxMessageLength__c.
    }

    // A profile or user the admin can create a row for.
    public class OwnerOption {

        @AuraEnabled public Id ownerId;
        @AuraEnabled public String name;
        @AuraEnabled public String detail; // The username for a user, blank for a profile.
    }

    // One AI Usage Policy with the people and permission sets it is assigned to.
    public class PolicyView {

        @AuraEnabled public Id policyId;
        @AuraEnabled public String name;
        @AuraEnabled public Map<String, Object> values = new Map<String, Object>(); // The field values, keyed by field name such as MaxTokensPer24Hours__c.
        @AuraEnabled public List<PolicyAssignmentView> assignments = new List<PolicyAssignmentView>();
    }

    // One assignment of a policy to a user or to a permission set.
    public class PolicyAssignmentView {

        @AuraEnabled public Id assignmentId;
        @AuraEnabled public String assigneeType; // User or Permission Set.
        @AuraEnabled public String assigneeName; // The user's name, or the permission set API name.
        @AuraEnabled public String assigneeDetail; // The username for a user, blank for a permission set.
        @AuraEnabled public Boolean isActive;
    }
}
