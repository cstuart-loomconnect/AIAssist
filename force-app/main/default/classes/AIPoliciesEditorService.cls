/*
Class Name: AIPoliciesEditorService

=================================================================
=================================================================

Description: Reads, checks, saves and deletes the AI Usage Policies that the AI Policies tab edits.

Step 1: Read every policy with its assignments
Step 2: Check and save one policy, creating it when it is new, and keep only one default policy
Step 3: Say who a policy covers, and delete a policy after moving its people to another policy
Step 4: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIPoliciesEditorService {

    public class AIPoliciesEditorServiceException extends Exception {}

    // Every policy field the tab may read or write, by the name the tab uses. Anything not listed here is refused.
    private static final Map<String, Schema.SObjectField> POLICY_FIELDS = new Map<String, Schema.SObjectField>{
        'Name' => AIUsagePolicy__c.Name,
        'Description__c' => AIUsagePolicy__c.Description__c,
        'IsActive__c' => AIUsagePolicy__c.IsActive__c,
        'IsDefault__c' => AIUsagePolicy__c.IsDefault__c,
        'MaxTokensPer24Hours__c' => AIUsagePolicy__c.MaxTokensPer24Hours__c,
        'MaxConversationsPer24Hours__c' => AIUsagePolicy__c.MaxConversationsPer24Hours__c,
        'MaxConcurrentConversations__c' => AIUsagePolicy__c.MaxConcurrentConversations__c,
        'UsageLimitReachedBehavior__c' => AIUsagePolicy__c.UsageLimitReachedBehavior__c,
        'IsUserInitiatedChatEnabled__c' => AIUsagePolicy__c.IsUserInitiatedChatEnabled__c,
        'AllowedChannels__c' => AIUsagePolicy__c.AllowedChannels__c,
        'ConversationVisibilityScope__c' => AIUsagePolicy__c.ConversationVisibilityScope__c,
        'ConversationExportEnabled__c' => AIUsagePolicy__c.ConversationExportEnabled__c,
        'DebugModeEnabled__c' => AIUsagePolicy__c.DebugModeEnabled__c,
        'ShouldCaptureExecutionSteps__c' => AIUsagePolicy__c.ShouldCaptureExecutionSteps__c
    };

    // The three numeric limits. Each is a whole number above zero, or blank for no limit.
    private static final Set<String> LIMIT_FIELDS = new Set<String>{'MaxTokensPer24Hours__c', 'MaxConversationsPer24Hours__c', 'MaxConcurrentConversations__c'};

    // Every policy, with its assignments, for the tab to show. The default policy comes first.
    public static List<AIPoliciesDataStructure.PolicyView> getPolicies() {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the policies and the assignments of each
        Integer maxResults = AIAssistApplicationConstants.POLICIES_LIST_MAX_RESULTS;
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, Description__c, IsActive__c, IsDefault__c, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, AllowedChannels__c, ConversationVisibilityScope__c, ConversationExportEnabled__c, DebugModeEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WITH SYSTEM_MODE ORDER BY IsDefault__c DESC, Name LIMIT :maxResults];
        Map<Id, List<AIPoliciesDataStructure.AssignmentView>> assignmentsByPolicyId = getAssignmentsByPolicyId(new Map<Id, AIUsagePolicy__c>(policies).keySet());

        // [3] Build one view per policy
        List<AIPoliciesDataStructure.PolicyView> views = new List<AIPoliciesDataStructure.PolicyView>();

        for (AIUsagePolicy__c policy : policies) {

            views.add(buildView(policy, assignmentsByPolicyId.get(policy.Id)));
        }

        return views;
    }

    // One policy as the tab shows it, read fresh.
    public static AIPoliciesDataStructure.PolicyView getPolicy(Id policyId) {

        // [1] Read the policy with its assignments
        AIUsagePolicy__c policy = findPolicy(policyId);
        Map<Id, List<AIPoliciesDataStructure.AssignmentView>> assignmentsByPolicyId = getAssignmentsByPolicyId(new Set<Id>{policyId});

        return buildView(policy, assignmentsByPolicyId.get(policyId));
    }

    // Saves one policy, creating it when policyId is blank, and returns it as saved. The values are keyed by field name. A policy that becomes the default takes the default off every other policy.
    public static AIPoliciesDataStructure.PolicyView savePolicy(Id policyId, Map<String, Object> values) {

        // [1] Refuse a user who may not use the tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Find the policy, or start a new one
        AIUsagePolicy__c record = policyId == null ? new AIUsagePolicy__c() : findPolicy(policyId);
        Boolean wasDefault = record.IsDefault__c == true;
        Map<String, Object> newValues = values == null ? new Map<String, Object>() : values;

        // [3] Put each value on the policy, refusing a field the tab may not change
        for (String fieldName : newValues.keySet()) {

            if (!POLICY_FIELDS.containsKey(fieldName)) throw new AIPoliciesEditorServiceException(String.format(Label.AI_Settings_Error_Field_Not_Allowed, new List<String>{fieldName}));

            setValue(record, fieldName, POLICY_FIELDS.get(fieldName), newValues.get(fieldName));
            AIAssistSettingsEditorService.validateChoice(record, fieldName, POLICY_FIELDS.get(fieldName));
        }

        // [4] A policy needs a name, and the only default policy cannot be switched off
        if (String.isBlank(record.Name)) throw new AIPoliciesEditorServiceException(String.format(Label.AI_Settings_Error_Required, new List<String>{Schema.AIUsagePolicy__c.Name.getDescribe().getLabel()}));
        if (wasDefault && record.IsDefault__c != true) throw new AIPoliciesEditorServiceException(Label.AI_Policies_Error_Last_Default);

        // [5] Save it
        Database.upsert(record, AccessLevel.SYSTEM_MODE);

        // [6] Take the default off every other policy
        if (record.IsDefault__c == true) {

            List<AIUsagePolicy__c> otherDefaults = [SELECT Id FROM AIUsagePolicy__c WHERE IsDefault__c = TRUE AND Id != :record.Id WITH SYSTEM_MODE LIMIT 200];

            for (AIUsagePolicy__c otherDefault : otherDefaults) otherDefault.IsDefault__c = false;

            Database.update(otherDefaults, AccessLevel.SYSTEM_MODE);
        }

        AIAssistSettingsService.clearCache();

        return getPolicy(record.Id);
    }

    // What the delete dialog needs: who the policy covers and the policies they can move to.
    public static AIPoliciesDataStructure.DeleteOptions getDeleteOptions(Id policyId) {

        // [1] Refuse a user who may not use the tab, and a policy that is gone
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicy__c policy = findPolicy(policyId);

        // [2] Count the assignments and the users they cover
        AIPoliciesDataStructure.PolicyView view = getPolicy(policyId);
        AIPoliciesDataStructure.DeleteOptions options = new AIPoliciesDataStructure.DeleteOptions();
        options.policyId = policy.Id;
        options.policyName = policy.Name;
        options.isDefault = policy.IsDefault__c == true;
        options.assignmentCount = view.assignments.size();
        options.userCount = 0;

        for (AIPoliciesDataStructure.AssignmentView assignment : view.assignments) options.userCount += assignment.usersCovered;

        // [3] List every other policy, and note the default one
        for (AIUsagePolicy__c other : [SELECT Id, Name, IsDefault__c FROM AIUsagePolicy__c WHERE Id != :policyId WITH SYSTEM_MODE ORDER BY Name LIMIT 200]) {

            AIPoliciesDataStructure.PolicyOption option = new AIPoliciesDataStructure.PolicyOption();
            option.policyId = other.Id;
            option.name = other.Name;
            options.otherPolicies.add(option);

            if (other.IsDefault__c == true && options.defaultPolicyId == null) {

                options.defaultPolicyId = other.Id;
                options.defaultPolicyName = other.Name;
            }
        }

        return options;
    }

    // Moves the assignments of a policy to another policy, deletes it, and returns every policy as saved. The default policy cannot be deleted.
    public static List<AIPoliciesDataStructure.PolicyView> deletePolicy(Id policyId, Id moveToPolicyId) {

        // [1] Refuse a user who may not use the tab, a policy that is gone, and the default policy
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicy__c policy = findPolicy(policyId);
        if (policy.IsDefault__c == true) throw new AIPoliciesEditorServiceException(Label.AI_Policies_Error_Delete_Default);

        // [2] Read the assignments that would be lost
        List<AIUsagePolicyAssignment__c> assignments = [SELECT Id, AssigneeType__c, User__c, PermissionSetName__c, IsActive__c FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :policyId WITH SYSTEM_MODE LIMIT 2000];

        if (!assignments.isEmpty()) {

            // [3] They need another policy to move to
            if (moveToPolicyId == null || moveToPolicyId == policyId) throw new AIPoliciesEditorServiceException(Label.AI_Policies_Error_Move_To);
            findPolicy(moveToPolicyId);

            // [4] Copy each assignment to the other policy, unless it already has the same user or permission set. A policy cannot be changed on an assignment, so the old one is deleted with its policy.
            List<AIUsagePolicyAssignment__c> toMove = new List<AIUsagePolicyAssignment__c>();
            Set<String> targetKeys = new Set<String>();

            for (AIUsagePolicyAssignment__c existing : [SELECT AssigneeType__c, User__c, PermissionSetName__c FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c = :moveToPolicyId WITH SYSTEM_MODE LIMIT 2000]) targetKeys.add(existing.AssigneeType__c + '|' + existing.User__c + '|' + existing.PermissionSetName__c);

            for (AIUsagePolicyAssignment__c assignment : assignments) {

                String key = assignment.AssigneeType__c + '|' + assignment.User__c + '|' + assignment.PermissionSetName__c;

                if (targetKeys.add(key)) {

                    toMove.add(new AIUsagePolicyAssignment__c(AIUsagePolicy__c = moveToPolicyId, AssigneeType__c = assignment.AssigneeType__c, User__c = assignment.User__c, PermissionSetName__c = assignment.PermissionSetName__c, IsActive__c = assignment.IsActive__c));
                }
            }

            Database.insert(toMove, AccessLevel.SYSTEM_MODE);
        }

        // [5] Delete the policy and read the rest back
        Database.delete(policy, AccessLevel.SYSTEM_MODE);
        AIAssistSettingsService.clearCache();

        return getPolicies();
    }

    // The saved policy, or a refusal when it is gone.
    private static AIUsagePolicy__c findPolicy(Id policyId) {

        // [1] Read the policy and every field the tab edits
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, Description__c, IsActive__c, IsDefault__c, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, AllowedChannels__c, ConversationVisibilityScope__c, ConversationExportEnabled__c, DebugModeEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WHERE Id = :policyId WITH SYSTEM_MODE LIMIT 1];
        if (policies.isEmpty()) throw new AIPoliciesEditorServiceException(Label.AI_Settings_Error_Row_Not_Found);

        return policies[0];
    }

    // The assignments of the policies, grouped by policy, with the name of each user or permission set and how many users each covers.
    private static Map<Id, List<AIPoliciesDataStructure.AssignmentView>> getAssignmentsByPolicyId(Set<Id> policyIds) {

        // [1] Read the assignments
        List<AIUsagePolicyAssignment__c> assignments = [SELECT Id, AIUsagePolicy__c, AssigneeType__c, User__c, User__r.Name, User__r.Username, PermissionSetName__c, IsActive__c FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c IN :policyIds WITH SYSTEM_MODE ORDER BY AssigneeType__c, CreatedDate LIMIT 2000];

        // [2] Look up the label and the user count of each permission set in one go
        Set<String> permissionSetNames = new Set<String>();

        for (AIUsagePolicyAssignment__c assignment : assignments) {

            if (assignment.AssigneeType__c == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) permissionSetNames.add(assignment.PermissionSetName__c);
        }

        Map<String, String> labelsByName = AIPoliciesAssignmentService.getPermissionSetLabels(permissionSetNames);
        Map<String, Integer> usersByName = AIPoliciesAssignmentService.getUsersCovered(permissionSetNames);

        // [3] Build the view of each assignment and group it by policy
        Map<Id, List<AIPoliciesDataStructure.AssignmentView>> assignmentsByPolicyId = new Map<Id, List<AIPoliciesDataStructure.AssignmentView>>();

        for (AIUsagePolicyAssignment__c assignment : assignments) {

            Boolean isUserAssignment = assignment.AssigneeType__c == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER;
            AIPoliciesDataStructure.AssignmentView view = new AIPoliciesDataStructure.AssignmentView();
            view.assignmentId = assignment.Id;
            view.assigneeType = assignment.AssigneeType__c;
            view.isActive = assignment.IsActive__c;
            view.assigneeName = isUserAssignment ? assignment.User__r.Name : labelsByName.get(assignment.PermissionSetName__c);
            view.assigneeDetail = isUserAssignment ? assignment.User__r.Username : assignment.PermissionSetName__c;
            view.usersCovered = isUserAssignment ? 1 : usersByName.get(assignment.PermissionSetName__c);

            if (!assignmentsByPolicyId.containsKey(assignment.AIUsagePolicy__c)) assignmentsByPolicyId.put(assignment.AIUsagePolicy__c, new List<AIPoliciesDataStructure.AssignmentView>());
            assignmentsByPolicyId.get(assignment.AIUsagePolicy__c).add(view);
        }

        return assignmentsByPolicyId;
    }

    // Builds the view of one policy.
    private static AIPoliciesDataStructure.PolicyView buildView(AIUsagePolicy__c policy, List<AIPoliciesDataStructure.AssignmentView> assignments) {

        // [1] Copy the id, the name and the assignments
        AIPoliciesDataStructure.PolicyView view = new AIPoliciesDataStructure.PolicyView();
        view.policyId = policy.Id;
        view.name = policy.Name;
        if (assignments != null) view.assignments = assignments;

        // [2] Copy each field the tab edits
        for (String fieldName : POLICY_FIELDS.keySet()) {

            view.values.put(fieldName, policy.get(POLICY_FIELDS.get(fieldName)));
        }

        return view;
    }

    // Puts one value from the tab on a policy, turning it into the type the field holds.
    private static void setValue(AIUsagePolicy__c record, String fieldName, Schema.SObjectField fieldToken, Object rawValue) {

        // [1] Work out the type of the field and a readable label for any message
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        Schema.DisplayType fieldType = fieldDescribe.getType();
        String fieldLabel = fieldDescribe.getLabel();
        Boolean isBlank = rawValue == null || (rawValue instanceof String && String.isBlank((String) rawValue));

        // [2] A checkbox is never blank
        if (fieldType == Schema.DisplayType.BOOLEAN) {

            record.put(fieldToken, rawValue instanceof Boolean && (Boolean) rawValue);
            return;
        }

        // [3] A blank value clears the field
        if (isBlank) {

            record.put(fieldToken, null);
            return;
        }

        // [4] A limit must be a whole number above zero
        if (LIMIT_FIELDS.contains(fieldName)) {

            record.put(fieldToken, parseLimit(fieldLabel, rawValue));
            return;
        }

        // [5] A multi-select list arrives as a list and is saved as text split by semicolons
        if (fieldType == Schema.DisplayType.MULTIPICKLIST) {

            List<String> choices = new List<String>();

            if (rawValue instanceof List<Object>) {

                for (Object choice : (List<Object>) rawValue) {

                    choices.add(String.valueOf(choice));
                }

            } else {

                choices.addAll(String.valueOf(rawValue).split(AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR));
            }

            record.put(fieldToken, String.join(choices, AIAssistApplicationConstants.DELIMITER_MULTI_SELECT_SEPARATOR));
            return;
        }

        // [6] Everything else is text, which must fit the field
        String textValue = String.valueOf(rawValue).trim();
        Integer maxLength = fieldDescribe.getLength();

        if (fieldType == Schema.DisplayType.STRING && maxLength > 0 && textValue.length() > maxLength) throw new AIPoliciesEditorServiceException(String.format(Label.AI_Settings_Error_Text_Length, new List<String>{fieldLabel, String.valueOf(maxLength)}));

        record.put(fieldToken, textValue);
    }

    // Turns a limit from the tab into a whole number above zero, or refuses it.
    private static Decimal parseLimit(String fieldLabel, Object rawValue) {

        // [1] Read the value as a number
        Decimal numberValue;

        try {

            numberValue = Decimal.valueOf(String.valueOf(rawValue).replace(',', ''));

        } catch (Exception ex) {

            throw new AIPoliciesEditorServiceException(String.format(Label.AI_Policies_Error_Limit, new List<String>{fieldLabel}));
        }

        // [2] A decimal part, zero or a negative number is refused
        if (numberValue != numberValue.setScale(0) || numberValue <= 0) throw new AIPoliciesEditorServiceException(String.format(Label.AI_Policies_Error_Limit, new List<String>{fieldLabel}));

        return numberValue;
    }
}
