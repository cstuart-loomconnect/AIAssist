/*
Class Name: AIAssistPolicyEditorService

=================================================================
=================================================================

Description: Reads, checks and saves the AI Usage Policies and their assignments that the AI Usage Policies tab edits.

Step 1: Read every policy with its assignments
Step 2: Check and save one policy, creating it when it is new, and delete a policy
Step 3: Add, switch on or off, and remove an assignment to a user or a permission set
Step 4: Find a permission set or permission set group to assign
Step 5: Refuse anyone who does not hold the Manage Settings custom permission

=================================================================
=================================================================

Version      Author                   Description
1.0          Chandler Stuart          Initial development
*/

public without sharing class AIAssistPolicyEditorService {

    public class AIAssistPolicyEditorServiceException extends Exception {}

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

    // Every policy, with its assignments, for the tab to show. The default policies come first.
    public static List<AIAssistSettingsDataStructure.PolicyView> getPolicies() {

        // [1] Refuse a user who may not use the Settings tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Read the policies and the assignments of each
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, Description__c, IsActive__c, IsDefault__c, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, AllowedChannels__c, ConversationVisibilityScope__c, ConversationExportEnabled__c, DebugModeEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WITH SYSTEM_MODE ORDER BY IsDefault__c DESC, Name LIMIT :AIAssistApplicationConstants.SETTINGS_POLICY_LIST_MAX_RESULTS];
        Map<Id, List<AIAssistSettingsDataStructure.PolicyAssignmentView>> assignmentsByPolicyId = getAssignmentsByPolicyId(new Map<Id, AIUsagePolicy__c>(policies).keySet());

        // [3] Build one view per policy
        List<AIAssistSettingsDataStructure.PolicyView> views = new List<AIAssistSettingsDataStructure.PolicyView>();

        for (AIUsagePolicy__c policy : policies) {

            views.add(buildView(policy, assignmentsByPolicyId.get(policy.Id)));
        }

        return views;
    }

    // Saves one policy, creating it when policyId is blank, and returns it as saved. The values are keyed by field name.
    public static AIAssistSettingsDataStructure.PolicyView savePolicy(Id policyId, Map<String, Object> values) {

        // [1] Refuse a user who may not use the Settings tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Find the policy, or start a new one
        AIUsagePolicy__c record = policyId == null ? new AIUsagePolicy__c() : findPolicy(policyId);
        Map<String, Object> newValues = values == null ? new Map<String, Object>() : values;

        // [3] Put each value on the policy, refusing a field the tab may not change
        for (String fieldName : newValues.keySet()) {

            if (!POLICY_FIELDS.containsKey(fieldName)) throw new AIAssistPolicyEditorServiceException(String.format(Label.AI_Settings_Error_Field_Not_Allowed, new List<String>{fieldName}));

            setValue(record, fieldName, POLICY_FIELDS.get(fieldName), newValues.get(fieldName));
            AIAssistSettingsEditorService.validateChoice(record, fieldName, POLICY_FIELDS.get(fieldName));
        }

        // [4] A policy needs a name
        if (String.isBlank(record.Name)) throw new AIAssistPolicyEditorServiceException(String.format(Label.AI_Settings_Error_Required, new List<String>{Schema.AIUsagePolicy__c.Name.getDescribe().getLabel()}));

        // [5] Save it and read it back
        upsert record;
        AIAssistSettingsService.clearCache();

        return getPolicy(record.Id);
    }

    // Deletes a policy. Its assignments go with it.
    public static void deletePolicy(Id policyId) {

        // [1] Refuse a user who may not use the Settings tab
        AIAssistSettingsEditorService.requireManager();

        // [2] Delete the policy
        delete findPolicy(policyId);
    }

    // Assigns a policy to a user or to a permission set, and returns the policy as saved.
    public static AIAssistSettingsDataStructure.PolicyView addAssignment(Id policyId, String assigneeType, Id userId, String permissionSetName) {

        // [1] Refuse a user who may not use the Settings tab, and a policy that is gone
        AIAssistSettingsEditorService.requireManager();
        findPolicy(policyId);

        // [2] Build the assignment for the chosen type
        AIUsagePolicyAssignment__c assignment = new AIUsagePolicyAssignment__c(AIUsagePolicy__c = policyId, AssigneeType__c = assigneeType, IsActive__c = true);

        if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER) {

            if (userId == null || userId.getSobjectType() != Schema.User.SObjectType) throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Policy_Error_Assignee);
            assignment.User__c = userId;

        } else if (assigneeType == AIAssistApplicationConstants.ASSIGNEE_TYPE_PERMISSION_SET) {

            String trimmedName = String.isBlank(permissionSetName) ? '' : permissionSetName.trim();
            if (!isPermissionSetName(trimmedName)) throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Policy_Error_Permission_Set);
            assignment.PermissionSetName__c = trimmedName;

        } else {

            throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Policy_Error_Assignee);
        }

        // [3] The same assignee twice on one policy is refused
        if (hasAssignment(assignment)) throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Policy_Error_Duplicate);

        insert assignment;

        return getPolicy(policyId);
    }

    // Switches an assignment on or off, and returns the policy as saved.
    public static AIAssistSettingsDataStructure.PolicyView setAssignmentActive(Id assignmentId, Boolean isActive) {

        // [1] Refuse a user who may not use the Settings tab, and an assignment that is gone
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicyAssignment__c assignment = findAssignment(assignmentId);

        // [2] Save the new state
        update new AIUsagePolicyAssignment__c(Id = assignmentId, IsActive__c = isActive == true);

        return getPolicy(assignment.AIUsagePolicy__c);
    }

    // Removes an assignment, and returns the policy as saved.
    public static AIAssistSettingsDataStructure.PolicyView removeAssignment(Id assignmentId) {

        // [1] Refuse a user who may not use the Settings tab, and an assignment that is gone
        AIAssistSettingsEditorService.requireManager();
        AIUsagePolicyAssignment__c assignment = findAssignment(assignmentId);

        // [2] Delete it
        Id policyId = assignment.AIUsagePolicy__c;
        delete assignment;

        return getPolicy(policyId);
    }

    // Finds the permission sets and permission set groups whose name or label matches the text.
    public static List<AIAssistSettingsDataStructure.OwnerOption> findPermissionSets(String searchText) {

        // [1] Refuse a user who may not use the Settings tab
        AIAssistSettingsEditorService.requireManager();
        List<AIAssistSettingsDataStructure.OwnerOption> options = new List<AIAssistSettingsDataStructure.OwnerOption>();

        // [2] Wait for enough text to make the search worth running
        String trimmedText = String.isBlank(searchText) ? '' : searchText.trim();
        if (trimmedText.length() < AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MIN_LENGTH) return options;

        String likeText = '%' + String.escapeSingleQuotes(trimmedText) + '%';
        Integer maxResults = AIAssistApplicationConstants.SETTINGS_OWNER_SEARCH_MAX_RESULTS;

        // [3] Search permission sets, then permission set groups. The name is what a policy stores.
        for (PermissionSet matchingSet : [SELECT Id, Name, Label FROM PermissionSet WHERE IsOwnedByProfile = FALSE AND Type != 'Group' AND (Name LIKE :likeText OR Label LIKE :likeText) WITH SYSTEM_MODE ORDER BY Label LIMIT :maxResults]) {

            options.add(buildOption(matchingSet.Id, matchingSet.Name, matchingSet.Label));
        }

        for (PermissionSetGroup matchingGroup : [SELECT Id, DeveloperName, MasterLabel FROM PermissionSetGroup WHERE DeveloperName LIKE :likeText OR MasterLabel LIKE :likeText WITH SYSTEM_MODE ORDER BY MasterLabel LIMIT :maxResults]) {

            options.add(buildOption(matchingGroup.Id, matchingGroup.DeveloperName, matchingGroup.MasterLabel));
        }

        return options;
    }

    // One policy as the tab shows it, read fresh.
    private static AIAssistSettingsDataStructure.PolicyView getPolicy(Id policyId) {

        // [1] Read the policy with its assignments
        AIUsagePolicy__c policy = findPolicy(policyId);
        Map<Id, List<AIAssistSettingsDataStructure.PolicyAssignmentView>> assignmentsByPolicyId = getAssignmentsByPolicyId(new Set<Id>{policyId});

        return buildView(policy, assignmentsByPolicyId.get(policyId));
    }

    // The saved policy, or a refusal when it is gone.
    private static AIUsagePolicy__c findPolicy(Id policyId) {

        // [1] Read the policy and every field the tab edits
        List<AIUsagePolicy__c> policies = [SELECT Id, Name, Description__c, IsActive__c, IsDefault__c, MaxTokensPer24Hours__c, MaxConversationsPer24Hours__c, MaxConcurrentConversations__c, UsageLimitReachedBehavior__c, IsUserInitiatedChatEnabled__c, AllowedChannels__c, ConversationVisibilityScope__c, ConversationExportEnabled__c, DebugModeEnabled__c, ShouldCaptureExecutionSteps__c FROM AIUsagePolicy__c WHERE Id = :policyId WITH SYSTEM_MODE LIMIT 1];
        if (policies.isEmpty()) throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Error_Row_Not_Found);

        return policies[0];
    }

    // The saved assignment, or a refusal when it is gone.
    private static AIUsagePolicyAssignment__c findAssignment(Id assignmentId) {

        // [1] Read the assignment
        List<AIUsagePolicyAssignment__c> assignments = [SELECT Id, AIUsagePolicy__c, IsActive__c FROM AIUsagePolicyAssignment__c WHERE Id = :assignmentId WITH SYSTEM_MODE LIMIT 1];
        if (assignments.isEmpty()) throw new AIAssistPolicyEditorServiceException(Label.AI_Settings_Error_Row_Not_Found);

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

    // Says whether a name is a permission set or a permission set group.
    private static Boolean isPermissionSetName(String name) {

        // [1] A blank name is not a permission set
        if (String.isBlank(name)) return false;

        // [2] Look for a permission set, then a group
        Boolean isSet = [SELECT COUNT() FROM PermissionSet WHERE Name = :name AND IsOwnedByProfile = FALSE WITH SYSTEM_MODE LIMIT 1] > 0;
        if (isSet) return true;

        return [SELECT COUNT() FROM PermissionSetGroup WHERE DeveloperName = :name WITH SYSTEM_MODE LIMIT 1] > 0;
    }

    // The assignments of the policies, with the name of each user, grouped by policy.
    private static Map<Id, List<AIAssistSettingsDataStructure.PolicyAssignmentView>> getAssignmentsByPolicyId(Set<Id> policyIds) {

        // [1] Read the assignments
        Map<Id, List<AIAssistSettingsDataStructure.PolicyAssignmentView>> assignmentsByPolicyId = new Map<Id, List<AIAssistSettingsDataStructure.PolicyAssignmentView>>();

        for (AIUsagePolicyAssignment__c assignment : [SELECT Id, AIUsagePolicy__c, AssigneeType__c, User__c, User__r.Name, User__r.Username, PermissionSetName__c, IsActive__c FROM AIUsagePolicyAssignment__c WHERE AIUsagePolicy__c IN :policyIds WITH SYSTEM_MODE ORDER BY AssigneeType__c, CreatedDate LIMIT 2000]) {

            // [2] Build the view of one assignment
            AIAssistSettingsDataStructure.PolicyAssignmentView view = new AIAssistSettingsDataStructure.PolicyAssignmentView();
            view.assignmentId = assignment.Id;
            view.assigneeType = assignment.AssigneeType__c;
            view.isActive = assignment.IsActive__c;
            view.assigneeName = assignment.AssigneeType__c == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER ? assignment.User__r.Name : assignment.PermissionSetName__c;
            view.assigneeDetail = assignment.AssigneeType__c == AIAssistApplicationConstants.ASSIGNEE_TYPE_USER ? assignment.User__r.Username : null;

            if (!assignmentsByPolicyId.containsKey(assignment.AIUsagePolicy__c)) assignmentsByPolicyId.put(assignment.AIUsagePolicy__c, new List<AIAssistSettingsDataStructure.PolicyAssignmentView>());
            assignmentsByPolicyId.get(assignment.AIUsagePolicy__c).add(view);
        }

        return assignmentsByPolicyId;
    }

    // Builds the view of one policy.
    private static AIAssistSettingsDataStructure.PolicyView buildView(AIUsagePolicy__c policy, List<AIAssistSettingsDataStructure.PolicyAssignmentView> assignments) {

        // [1] Copy the id, the name and the assignments
        AIAssistSettingsDataStructure.PolicyView view = new AIAssistSettingsDataStructure.PolicyView();
        view.policyId = policy.Id;
        view.name = policy.Name;
        if (assignments != null) view.assignments = assignments;

        // [2] Copy each field the tab edits
        for (String fieldName : POLICY_FIELDS.keySet()) {

            view.values.put(fieldName, policy.get(POLICY_FIELDS.get(fieldName)));
        }

        return view;
    }

    // Builds a permission set the admin can pick: the API name is the name, and the label is the detail.
    private static AIAssistSettingsDataStructure.OwnerOption buildOption(Id optionId, String name, String detail) {

        // [1] Copy the values
        AIAssistSettingsDataStructure.OwnerOption option = new AIAssistSettingsDataStructure.OwnerOption();
        option.ownerId = optionId;
        option.name = name;
        option.detail = detail;

        return option;
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

        if (fieldType == Schema.DisplayType.STRING && maxLength > 0 && textValue.length() > maxLength) throw new AIAssistPolicyEditorServiceException(String.format(Label.AI_Settings_Error_Text_Length, new List<String>{fieldLabel, String.valueOf(maxLength)}));

        record.put(fieldToken, textValue);
    }

    // Turns a limit from the tab into a whole number above zero, or refuses it.
    private static Decimal parseLimit(String fieldLabel, Object rawValue) {

        // [1] Read the value as a number
        Decimal numberValue;

        try {

            numberValue = Decimal.valueOf(String.valueOf(rawValue).replace(',', ''));

        } catch (Exception ex) {

            throw new AIAssistPolicyEditorServiceException(String.format(Label.AI_Settings_Policy_Error_Limit, new List<String>{fieldLabel}));
        }

        // [2] A decimal part, zero or a negative number is refused
        if (numberValue != numberValue.setScale(0) || numberValue <= 0) throw new AIAssistPolicyEditorServiceException(String.format(Label.AI_Settings_Policy_Error_Limit, new List<String>{fieldLabel}));

        return numberValue;
    }
}
